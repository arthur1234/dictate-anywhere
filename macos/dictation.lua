-- ============================================================
--  dictate-anywhere: system-wide voice dictation via whisper.cpp
--  Works in any text field on macOS. Fully local, no cloud.
--
--  Ctrl+Alt+D  - start recording / stop and paste recognized text
--  Ctrl+Alt+X  - cancel recording (paste nothing)
--
--  Menu bar icon: 🎤 idle / 🔴 recording / ⏳ transcribing.
--  Clicking the icon = same as Ctrl+Alt+D.
--
--  Speech recognition: local whisper-server on 127.0.0.1:8765,
--  auto-started at login via LaunchAgent (see install.sh).
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
local CANCEL_KEY  = "x"

-- Homebrew lives in /opt/homebrew on Apple Silicon, /usr/local on Intel
local BREW        = hs.fs.attributes("/opt/homebrew/bin") and "/opt/homebrew" or "/usr/local"
local FFMPEG      = BREW .. "/bin/ffmpeg"
local CURL        = "/usr/bin/curl"
local WAV         = os.getenv("HOME") .. "/.hammerspoon/dictation.wav"
local SERVER_URL  = "http://127.0.0.1:8765/inference"
local MAX_SECONDS = 600   -- safety net: auto-stop recording after 10 minutes

local state = "idle"      -- idle | recording | processing
local recTask, recAlert, recStartedAt, maxTimer
local pendingAction = nil -- what to do once ffmpeg exits: "transcribe" | "cancel"

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

local function finishIdle()
  state = "idle"; setIcon()
end

local function insertText(text)
  -- the text also stays on the clipboard: if pasting fails, hit Cmd+V yourself
  hs.pasteboard.setContents(text)
  hs.timer.doAfter(0.05, function() hs.eventtap.keyStroke({"cmd"}, "v", 0) end)
end

local function transcribe()
  state = "processing"; setIcon()
  local waiting = hs.alert.show("⏳ Transcribing…", 120)
  hs.task.new(CURL, function(rc, out, err)
    hs.alert.closeSpecific(waiting)
    if rc ~= 0 then
      hs.alert.show("⚠️ whisper-server is not responding.\nIt needs ~10 s after login. Try again.", 5)
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

local function onRecordingExit()
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

local function startRecording()
  state = "recording"; setIcon()
  recStartedAt = hs.timer.secondsSinceEpoch()
  recTask = hs.task.new(FFMPEG, onRecordingExit,
    { "-y", "-hide_banner", "-loglevel", "error", "-nostats",
      "-f", "avfoundation", "-i", ":default",
      "-ar", "16000", "-ac", "1", WAV })
  recTask:start()
  playSound("Tink")
  recAlert = hs.alert.show("🎤 Speak…   ⌃⌥D = paste, ⌃⌥X = cancel", 3600)
  maxTimer = hs.timer.doAfter(MAX_SECONDS, function()
    if state == "recording" then
      pendingAction = "transcribe"
      if recTask and recTask:isRunning() then recTask:terminate() end
    end
  end)
end

local function stopRecording(action)
  if recAlert then hs.alert.closeSpecific(recAlert); recAlert = nil end
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
    -- an accidental double-press (<0.4 s of audio) is not worth transcribing
    if hs.timer.secondsSinceEpoch() - recStartedAt < 0.4 then
      stopRecording("cancel")
    else
      stopRecording("transcribe")
    end
  end
  -- while state == "processing", presses are ignored
end

local function cancelDictation()
  if state == "recording" then stopRecording("cancel") end
end

hs.hotkey.bind(HOTKEY_MODS, HOTKEY_KEY, toggleDictation)
hs.hotkey.bind(HOTKEY_MODS, CANCEL_KEY, cancelDictation)
menu:setClickCallback(toggleDictation)
setIcon()

hs.alert.show("🎤 Dictation ready:  Ctrl+Alt+D", 3)
