#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  dictate-anywhere - macOS installer
#  Usage: ./install.sh [--model large-v3|large-v3-turbo] [--port 8765]
# ============================================================

MODEL=""
PORT=8765
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --port)  PORT="$2";  shift 2 ;;
    *) echo "Unknown option: $1 (supported: --model, --port)"; exit 1 ;;
  esac
done

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

command -v brew >/dev/null || { echo "Homebrew is required first: https://brew.sh"; exit 1; }

bold "1/6 Installing packages (Hammerspoon, whisper-cpp, ffmpeg)…"
brew list --cask hammerspoon &>/dev/null || brew install --cask hammerspoon
brew list whisper-cpp        &>/dev/null || brew install whisper-cpp
brew list ffmpeg             &>/dev/null || brew install ffmpeg
BREW_PREFIX=$(brew --prefix)

bold "2/6 Choosing and downloading the model…"
if [[ -z "$MODEL" ]]; then
  RAM_GB=$(( $(sysctl -n hw.memsize) / 1073741824 ))
  if (( RAM_GB >= 16 )); then MODEL="large-v3"; else MODEL="large-v3-turbo"; fi
  echo "   Detected ${RAM_GB} GB RAM → model: $MODEL (override with --model)"
fi
MODEL_DIR="$HOME/Models/whisper"
MODEL_PATH="$MODEL_DIR/ggml-$MODEL.bin"
mkdir -p "$MODEL_DIR"
if [[ -f "$MODEL_PATH" ]]; then
  echo "   Already downloaded: $MODEL_PATH"
else
  curl -L --progress-bar -o "$MODEL_PATH.tmp" \
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL.bin"
  mv "$MODEL_PATH.tmp" "$MODEL_PATH"
fi

bold "3/6 Setting up whisper-server autostart (LaunchAgent)…"
LABEL="com.dictate-anywhere.whisper-server"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/whisper-server.log"
# refuse to fight another process for the port
if curl -s -o /dev/null --max-time 1 "http://127.0.0.1:$PORT/" \
   && ! launchctl print "gui/$(id -u)/$LABEL" &>/dev/null; then
  echo "⚠️  Port $PORT is already in use by another process."
  echo "   Re-run with a different port: ./install.sh --port 8766"
  exit 1
fi
sed -e "s|@@WHISPER_SERVER@@|$BREW_PREFIX/bin/whisper-server|g" \
    -e "s|@@MODEL_PATH@@|$MODEL_PATH|g" \
    -e "s|@@PORT@@|$PORT|g" \
    -e "s|@@LOG_PATH@@|$LOG|g" \
    "$SCRIPT_DIR/$LABEL.plist.template" > "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

bold "4/6 Installing the Hammerspoon dictation config…"
mkdir -p "$HOME/.hammerspoon"
sed "s|127.0.0.1:8765/|127.0.0.1:$PORT/|" "$SCRIPT_DIR/dictation.lua" > "$HOME/.hammerspoon/dictation.lua"
INIT="$HOME/.hammerspoon/init.lua"
if [[ -f "$INIT" ]] && grep -q 'require("dictation")' "$INIT"; then
  echo "   init.lua already loads dictation"
else
  printf '\nrequire("dictation")\n' >> "$INIT"
fi

bold "5/6 Starting Hammerspoon…"
open -a Hammerspoon

bold "6/6 Done! Two one-time permissions remain:"
cat <<'EOF'
   1. System Settings → Privacy & Security → Accessibility → enable Hammerspoon
      (needed to paste text into the active field)
   2. Press Ctrl+Alt+D, speak, press Ctrl+Alt+D again.
      On first use macOS will ask for Microphone access for Hammerspoon → Allow.

   Note: the model loads ~10 s after login/install, so the very first
   dictation may say "server not responding" — just try again.
EOF
