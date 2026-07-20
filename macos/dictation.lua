-- ============================================================
--  dictate-anywhere: system-wide voice dictation via whisper.cpp
--  Works in any text field on macOS. Fully local, no cloud.
--
--  Ctrl+Alt+D  - start recording / stop and paste recognized text
--  Ctrl+Alt+X  - emergency reset from any state
--
--  While recording, a panel at the bottom of the screen shows an
--  equalizer (bars move when you speak, flatten to a line in
--  silence) with "⏹ Stop" and "✕" buttons.
--
--  Menu bar icon: 🎤 idle / 🔴 recording / ⏳ transcribing.
--  Clicking the icon = same as Ctrl+Alt+D.
--
--  Recognition: local whisper-server on 127.0.0.1:8765 (auto-detect
--  language), auto-started at login via LaunchAgent (see install.sh).
--  Your voice never leaves the machine.
--
--  https://github.com/arthur1234/dictate-anywhere
-- ============================================================

hs.autoLaunch(true)   -- start Hammerspoon at login
hs.dockIcon(false)    -- no Dock icon
hs.menuIcon(false)    -- hide the default HS menu icon (we have our own 🎤)

-- change the hotkey here if you like
local HOTKEY_MODS = {"ctrl", "alt"}
local HOTKEY_KEY  = "d"
local RESET_KEY   = "x"

-- Homebrew lives in /opt/homebrew on Apple Silicon, /usr/local on Intel
local BREW        = hs.fs.attributes("/opt/homebrew/bin") and "/opt/homebrew" or "/usr/local"
local FFMPEG      = BREW .. "/bin/ffmpeg"
local CURL        = "/usr/bin/curl"
local WAV         = os.getenv("HOME") .. "/.hammerspoon/dictation.wav"
local SERVER_URL  = "http://127.0.0.1:8765/inference"
local MAX_SECONDS = 600   -- safety net: auto-stop recording after 10 minutes

local state = "idle"      -- idle | recording | processing
local recTask, recStartedAt, maxTimer
local pendingAction = nil  -- what to do once ffmpeg exits: "transcribe" | "cancel"
local processingStartedAt, procWatchdog -- guards against a stuck transcription phase

-- equalizer (visual recording indicator)
local NUM_BARS = 22
local BAR_MIN, BAR_MAX, EQ_MIDY = 3, 52, 52
local BAR_W = 6
local barX = {}
local WAV_TAIL = 2048              -- bytes from the end of WAV to measure loudness (~64ms)
local RMS_FLOOR, RMS_CEIL = 250, 1500  -- silence/speech threshold (tune if bars are too/not sensitive)
local eqCanvas, eqTimer, eqFrame = nil, nil, 0
local currentLevel, displayLevel = 0, 0

-- forward declarations for functions that reference each other
local finishIdle, transcribe, onRecordingExit, startRecording, stopRecording, resetToIdle
local buildEqualizer, showEqualizer, hideEqualizer, eqTick

local menu = hs.menubar.new()

local function setIcon()
  if     state == "recording"  then menu:setTitle("🔴")
  elseif state == "processing" then menu:setTitle("⏳")
  else                              menu:setTitle("🎤") end
end

local function playSound(name)
  local s = hs.sound.getByName(name)
  if s then s:play() end
end

function finishIdle()
  if procWatchdog then procWatchdog:stop(); procWatchdog = nil end
  pendingAction = nil
  processingStartedAt = nil
  state = "idle"; setIcon()
end

local function insertText(text)
  -- text also stays on the clipboard: if pasting fails, press Cmd+V manually
  hs.pasteboard.setContents(text)
  hs.timer.doAfter(0.05, function() hs.eventtap.keyStroke({"cmd"}, "v", 0) end)
end

-- ---------- equalizer ----------

-- read the tail of the growing WAV and compute loudness (for the equalizer).
-- ffmpeg buffers its stdout, so we read the level straight from the file instead.
local function readMicLevel()
  local f = io.open(WAV, "rb")
  if not f then return end
  local size = f:seek("end")
  local start = size - WAV_TAIL
  if start < 44 then start = 44 end   -- skip the WAV header
  f:seek("set", start)
  local data = f:read(WAV_TAIL)
  f:close()
  if not data or #data < 64 then return end
  local n = #data - (#data % 2)
  local sum, cnt = 0, 0
  for i = 1, n - 1, 2 do
    local v = data:byte(i + 1) * 256 + data:byte(i)  -- s16le
    if v >= 32768 then v = v - 65536 end
    sum = sum + v * v
    cnt = cnt + 1
  end
  if cnt == 0 then return end
  local rms = math.sqrt(sum / cnt)
  local lvl = (rms - RMS_FLOOR) / (RMS_CEIL - RMS_FLOOR)
  if lvl < 0 then lvl = 0 elseif lvl > 1 then lvl = 1 end
  currentLevel = lvl
end

function buildEqualizer()
  local scr = hs.screen.mainScreen():frame()
  local W, H = 390, 90
  local x = scr.x + (scr.w - W) / 2
  local y = scr.y + scr.h - H - 100
  eqCanvas = hs.canvas.new({x = x, y = y, w = W, h = H})
  eqCanvas:level(hs.canvas.windowLevels.overlay)
  eqCanvas:behavior(hs.canvas.windowBehaviors.canJoinAllSpaces)
  eqCanvas:clickActivating(false)  -- clicking a button does NOT steal focus from the text field

  eqCanvas[1] = { type = "rectangle", action = "fill",
    fillColor = {red = 0.10, green = 0.11, blue = 0.13, alpha = 0.94},
    roundedRectRadii = {xRadius = 18, yRadius = 18},
    frame = {x = 0, y = 0, w = W, h = H} }
  eqCanvas[2] = { type = "circle", action = "fill",
    fillColor = {red = 0.95, green = 0.27, blue = 0.27, alpha = 1.0},
    center = {x = 22, y = 20}, radius = 5 }
  eqCanvas[3] = { type = "text", text = "recording",
    textColor = {white = 0.85, alpha = 1.0}, textSize = 12,
    frame = {x = 32, y = 11, w = 90, h = 18} }

  barX = {}
  local x0, barsW = 16, 226
  local gap = barsW / NUM_BARS
  BAR_W = gap * 0.55
  for i = 1, NUM_BARS do
    barX[i] = x0 + (i - 1) * gap
    eqCanvas[3 + i] = { type = "rectangle", action = "fill",
      fillColor = {red = 0.30, green = 0.82, blue = 0.62, alpha = 1.0},
      roundedRectRadii = {xRadius = BAR_W / 2, yRadius = BAR_W / 2},
      frame = {x = barX[i], y = EQ_MIDY - BAR_MIN / 2, w = BAR_W, h = BAR_MIN} }
  end

  local si = 4 + NUM_BARS
  eqCanvas[si] = { type = "rectangle", action = "fill", id = "stop", trackMouseUp = true,
    fillColor = {red = 0.85, green = 0.32, blue = 0.32, alpha = 1.0},
    roundedRectRadii = {xRadius = 10, yRadius = 10},
    frame = {x = 248, y = 28, w = 84, h = 34} }
  eqCanvas[si + 1] = { type = "text", text = "⏹ Stop", id = "stop", trackMouseUp = true,
    textColor = {white = 1.0}, textSize = 13, textAlignment = "center",
    frame = {x = 248, y = 37, w = 84, h = 20} }
  eqCanvas[si + 2] = { type = "rectangle", action = "fill", id = "cancel", trackMouseUp = true,
    fillColor = {red = 0.28, green = 0.28, blue = 0.32, alpha = 1.0},
    roundedRectRadii = {xRadius = 9, yRadius = 9},
    frame = {x = 342, y = 30, w = 32, h = 30} }
  eqCanvas[si + 3] = { type = "text", text = "✕", id = "cancel", trackMouseUp = true,
    textColor = {white = 0.85}, textSize = 15, textAlignment = "center",
    frame = {x = 342, y = 35, w = 32, h = 22} }

  eqCanvas:mouseCallback(function(c, msg, elemId, ex, ey)
    if msg == "mouseUp" then
      if elemId == "stop" then stopRecording("transcribe")
      elseif elemId == "cancel" then resetToIdle() end
    end
  end)
end

function eqTick()
  local ok, err = pcall(function()
    if not eqCanvas then return end
    eqFrame = eqFrame + 1
    readMicLevel()  -- fresh loudness from the growing WAV file
    displayLevel = displayLevel + (currentLevel - displayLevel) * 0.45  -- smoothing
    -- pulsing red "recording" dot
    local pulse = 0.55 + 0.45 * math.abs(math.sin(eqFrame * 0.12))
    eqCanvas:elementAttribute(2, "fillColor", {red = 0.95, green = 0.27, blue = 0.27, alpha = pulse})
    local speaking = displayLevel > 0.05
    for i = 1, NUM_BARS do
      local h
      if speaking then
        local wobble = 0.35 + 0.65 * math.abs(math.sin(i * 0.7 + eqFrame * 0.35))
        h = BAR_MIN + (BAR_MAX - BAR_MIN) * math.min(displayLevel * 1.3, 1) * wobble
      else
        h = BAR_MIN  -- silence = flat line
      end
      eqCanvas:elementAttribute(3 + i, "frame", {x = barX[i], y = EQ_MIDY - h / 2, w = BAR_W, h = h})
    end
  end)
  if not ok then
    print("[dictation eq] " .. tostring(err))
    if eqTimer then eqTimer:stop(); eqTimer = nil end
  end
end

function showEqualizer()
  local ok = pcall(function()
    buildEqualizer()
    eqFrame = 0; currentLevel = 0; displayLevel = 0
    eqCanvas:show()
    if eqTimer then eqTimer:stop() end
    eqTimer = hs.timer.doEvery(0.04, eqTick)  -- ~25 fps
  end)
  if not ok and eqCanvas then eqCanvas:delete(); eqCanvas = nil end
end

function hideEqualizer()
  if eqTimer then eqTimer:stop(); eqTimer = nil end
  if eqCanvas then pcall(function() eqCanvas:delete() end); eqCanvas = nil end
end

-- ---------- recording and transcription ----------

function transcribe()
  state = "processing"; setIcon()
  processingStartedAt = hs.timer.secondsSinceEpoch()
  local waiting = hs.alert.show("⏳ Transcribing…", 120)
  -- watchdog: if transcription stalls (e.g. Mac slept), return to idle by itself
  if procWatchdog then procWatchdog:stop() end
  procWatchdog = hs.timer.doAfter(30, function()
    if state == "processing" then
      hs.alert.closeSpecific(waiting)
      hs.alert.show("↺ Transcription stalled, reset. Press the hotkey again.", 4)
      finishIdle()
    end
  end)
  hs.task.new(CURL, function(rc, out, err)
    hs.alert.closeSpecific(waiting)
    if procWatchdog then procWatchdog:stop(); procWatchdog = nil end
    if rc ~= 0 then
      hs.alert.show("⚠️ Whisper server not responding.\nIt needs ~10s after login. Try again.", 5)
      finishIdle(); return
    end
    local ok, resp = pcall(hs.json.decode, out)
    local text = ok and resp and resp.text or nil
    if not text then
      hs.alert.show("⚠️ Transcription error", 4)
      finishIdle(); return
    end
    -- whisper splits speech into segments; join them into a single line
    text = text:gsub("[\r\n]+", " "):gsub("%s%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then
      hs.alert.show("🤷 Heard nothing", 3)
      finishIdle(); return
    end
    insertText(text)
    playSound("Pop")
    finishIdle()
  end, { "-s", "--max-time", "180",
         SERVER_URL,
         "-F", "file=@" .. WAV,
         "-F", "temperature=0.0",
         "-F", "response_format=json" }):start()
end

function onRecordingExit()
  hideEqualizer()
  if maxTimer then maxTimer:stop(); maxTimer = nil end
  local action = pendingAction
  pendingAction = nil
  if action == "transcribe" then
    transcribe()
  elseif action == "cancel" then
    hs.alert.show("✖️ Cancelled", 2)
    finishIdle()
  else
    -- ffmpeg exited on its own - most likely no microphone access
    hs.alert.show("⚠️ Recording failed.\nCheck: System Settings → Privacy & Security → Microphone → Hammerspoon", 6)
    finishIdle()
  end
end

function startRecording()
  state = "recording"; setIcon()
  recStartedAt = hs.timer.secondsSinceEpoch()
  -- ffmpeg writes the WAV and flushes to disk immediately so we can read the level live
  recTask = hs.task.new(FFMPEG, onRecordingExit,
    { "-y", "-hide_banner", "-loglevel", "error", "-nostats",
      "-f", "avfoundation", "-i", ":default",
      "-flush_packets", "1",
      "-ar", "16000", "-ac", "1", WAV })
  recTask:start()
  playSound("Tink")
  pcall(showEqualizer)
  maxTimer = hs.timer.doAfter(MAX_SECONDS, function()
    if state == "recording" then
      pendingAction = "transcribe"
      if recTask and recTask:isRunning() then recTask:terminate() end
    end
  end)
end

function stopRecording(action)
  hideEqualizer()
  state = "processing"; setIcon()  -- blocks repeated presses while ffmpeg finalizes the file
  pendingAction = action
  if recTask and recTask:isRunning() then
    recTask:terminate()  -- SIGTERM: ffmpeg closes the wav cleanly, then onRecordingExit fires
  end
end

local function toggleDictation()
  if state == "idle" then
    startRecording()
  elseif state == "recording" then
    -- an accidental double-press (<0.4s of audio) is not worth transcribing
    if hs.timer.secondsSinceEpoch() - recStartedAt < 0.4 then
      stopRecording("cancel")
    else
      stopRecording("transcribe")
    end
  elseif state == "processing" then
    -- if "transcribing" has hung too long, treat it as stuck and start fresh
    if processingStartedAt and (hs.timer.secondsSinceEpoch() - processingStartedAt) > 20 then
      finishIdle()
      startRecording()
    end
  end
end

-- Reset hotkey: emergency reset to idle from ANY state
function resetToIdle()
  if maxTimer then maxTimer:stop(); maxTimer = nil end
  if procWatchdog then procWatchdog:stop(); procWatchdog = nil end
  hideEqualizer()
  pendingAction = "cancel"  -- if a recording is still running, onRecordingExit cancels it quietly
  if recTask and recTask:isRunning() then recTask:terminate() end
  processingStartedAt = nil
  state = "idle"; setIcon()
  hs.alert.show("↺ Reset to idle", 2)
end

hs.hotkey.bind(HOTKEY_MODS, HOTKEY_KEY, toggleDictation)
hs.hotkey.bind(HOTKEY_MODS, RESET_KEY, resetToIdle)
menu:setClickCallback(toggleDictation)
setIcon()

hs.alert.show("🎤 Dictation ready:  Ctrl+Alt+D", 3)
