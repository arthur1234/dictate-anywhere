#!/usr/bin/env bash
set -u

# ============================================================
#  dictate-anywhere - Linux toggle script
#  First run starts recording; second run stops it, transcribes
#  via the local whisper-server and types/pastes the text.
#  Bind this script to a hotkey (install.sh does it for GNOME).
# ============================================================

PORT="${DICTATE_PORT:-8765}"
RUNDIR="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="$RUNDIR/dictate-anywhere.pid"
WAV="$RUNDIR/dictate-anywhere.wav"

notify() { command -v notify-send >/dev/null && notify-send -t 2500 "dictate-anywhere" "$1" || true; }

if [[ -f "$PIDFILE" ]]; then
  # ---------- stop & transcribe ----------
  PID=$(cat "$PIDFILE"); rm -f "$PIDFILE"
  if kill -TERM "$PID" 2>/dev/null; then
    # wait for ffmpeg to finalize the wav (max 3 s)
    for _ in $(seq 1 30); do kill -0 "$PID" 2>/dev/null || break; sleep 0.1; done
  fi
  [[ -s "$WAV" ]] || { notify "⚠️ No audio was recorded"; exit 1; }

  notify "⏳ Transcribing…"
  RESP=$(curl -s --max-time 180 "http://127.0.0.1:$PORT/inference" \
           -F "file=@$WAV" -F temperature=0.0 -F response_format=json) || {
    notify "⚠️ whisper-server is not responding (it needs ~15 s after login)"
    exit 1
  }
  TEXT=$(printf '%s' "$RESP" | jq -r '.text // empty' \
         | tr '\r\n' '  ' | sed -e 's/  */ /g' -e 's/^ *//' -e 's/ *$//')
  [[ -z "$TEXT" ]] && { notify "🤷 Heard nothing"; exit 0; }

  # always put the text on the clipboard first
  if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]] && command -v wl-copy >/dev/null; then
    printf '%s' "$TEXT" | wl-copy
  elif command -v xclip >/dev/null; then
    printf '%s' "$TEXT" | xclip -selection clipboard
  fi

  # then try to deliver it into the focused field
  if [[ "${XDG_SESSION_TYPE:-}" == "x11" ]] && command -v xdotool >/dev/null; then
    # typing directly handles unicode well on X11
    xdotool type --clearmodifiers -- "$TEXT"
  elif command -v ydotool >/dev/null; then
    # on Wayland we paste from the clipboard: Ctrl+V (keycodes 29=Ctrl, 47=V)
    ydotool key 29:1 47:1 47:0 29:0 2>/dev/null || notify "📋 Copied — press Ctrl+V to paste"
  else
    notify "📋 Copied — press Ctrl+V to paste"
  fi
else
  # ---------- start recording ----------
  rm -f "$WAV"
  ffmpeg -y -hide_banner -loglevel error -nostats \
    -f pulse -i default -ar 16000 -ac 1 "$WAV" &
  echo $! > "$PIDFILE"
  notify "🎤 Recording… press the hotkey again to stop"
fi
