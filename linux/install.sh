#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  dictate-anywhere - Linux installer (Ubuntu/Debian, GNOME)
#  Usage: ./install.sh [--model MODEL] [--port PORT]
#  Models: large-v3-turbo (default on CPU), large-v3 (default
#  with CUDA), medium, small
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

bold "1/7 Installing packages (sudo required)…"
sudo apt-get update -qq
sudo apt-get install -y ffmpeg curl jq git build-essential cmake \
  libnotify-bin wl-clipboard xclip xdotool ydotool

bold "2/7 Building whisper.cpp (one-time, a few minutes)…"
SRC="$HOME/.local/src/whisper.cpp"
if [[ ! -d "$SRC" ]]; then
  mkdir -p "$HOME/.local/src"
  git clone --depth 1 https://github.com/ggml-org/whisper.cpp "$SRC"
fi
CMAKE_FLAGS=()
if command -v nvcc >/dev/null; then
  CMAKE_FLAGS+=("-DGGML_CUDA=1")
  echo "   NVIDIA CUDA toolkit found → building with GPU support"
fi
cmake -S "$SRC" -B "$SRC/build" -DCMAKE_BUILD_TYPE=Release "${CMAKE_FLAGS[@]+"${CMAKE_FLAGS[@]}"}" >/dev/null
cmake --build "$SRC/build" -j"$(nproc)" >/dev/null
mkdir -p "$HOME/.local/bin"
ln -sf "$SRC/build/bin/whisper-server" "$HOME/.local/bin/whisper-server"
ln -sf "$SRC/build/bin/whisper-cli"    "$HOME/.local/bin/whisper-cli"

bold "3/7 Choosing and downloading the model…"
if [[ -z "$MODEL" ]]; then
  if command -v nvcc >/dev/null; then MODEL="large-v3"; else MODEL="large-v3-turbo"; fi
  echo "   Model: $MODEL (override with --model large-v3 / large-v3-turbo / medium / small)"
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

bold "4/7 Setting up whisper-server autostart (systemd user unit)…"
mkdir -p "$HOME/.config/systemd/user"
sed -e "s|@@WHISPER_SERVER@@|$HOME/.local/bin/whisper-server|g" \
    -e "s|@@MODEL_PATH@@|$MODEL_PATH|g" \
    -e "s|@@PORT@@|$PORT|g" \
    -e "s|@@THREADS@@|$(nproc)|g" \
    "$SCRIPT_DIR/whisper-server.service.template" \
    > "$HOME/.config/systemd/user/whisper-server.service"
systemctl --user daemon-reload
systemctl --user enable --now whisper-server.service

bold "5/7 Installing dictate.sh…"
install -m 0755 "$SCRIPT_DIR/dictate.sh" "$HOME/.local/bin/dictate.sh"

bold "6/7 Wayland typing support (ydotool)…"
if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
  echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' \
    | sudo tee /etc/udev/rules.d/60-dictate-anywhere-uinput.rules >/dev/null
  sudo modprobe uinput || true
  sudo udevadm control --reload-rules || true
  sudo udevadm trigger || true
  sudo usermod -aG input "$USER"
  cat > "$HOME/.config/systemd/user/ydotoold.service" <<'UNIT'
[Unit]
Description=ydotool user daemon

[Service]
ExecStart=/usr/bin/ydotoold
Restart=on-failure

[Install]
WantedBy=default.target
UNIT
  systemctl --user daemon-reload
  systemctl --user enable --now ydotoold.service || true
  echo "   NOTE: log out and back in once so the 'input' group membership takes effect."
else
  echo "   X11 session detected → xdotool will be used, nothing to set up."
fi

register_gnome_hotkey() {
  command -v gsettings >/dev/null || return 1
  python3 - "$HOME/.local/bin/dictate.sh" <<'PY'
import subprocess, sys, ast
bind_cmd = sys.argv[1]
base = "org.gnome.settings-daemon.plugins.media-keys"
kpath = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/dictate-anywhere/"
cur = subprocess.run(["gsettings", "get", base, "custom-keybindings"],
                     capture_output=True, text=True)
if cur.returncode != 0:
    sys.exit(1)
txt = cur.stdout.strip()
if txt.startswith("@as"):
    txt = txt[3:].strip()
try:
    arr = ast.literal_eval(txt) or []
except Exception:
    arr = []
if isinstance(arr, str):
    arr = [arr]
arr = list(arr)
if kpath not in arr:
    arr.append(kpath)
subprocess.run(["gsettings", "set", base, "custom-keybindings", str(arr)], check=True)
schema = base + ".custom-keybinding:" + kpath
subprocess.run(["gsettings", "set", schema, "name", "dictate-anywhere"], check=True)
subprocess.run(["gsettings", "set", schema, "command", bind_cmd], check=True)
subprocess.run(["gsettings", "set", schema, "binding", "<Primary><Alt>d"], check=True)
print("   Hotkey Ctrl+Alt+D registered.")
PY
}

bold "7/7 Registering the GNOME hotkey Ctrl+Alt+D…"
if register_gnome_hotkey; then
  :
else
  echo "   Could not register the hotkey automatically (non-GNOME desktop?)."
  echo "   Bind a key to:  $HOME/.local/bin/dictate.sh   in your keyboard settings."
fi

bold "Done!"
cat <<'EOF'
  • Press Ctrl+Alt+D, speak, press Ctrl+Alt+D again — the text appears
    in the focused field (or lands on the clipboard: then press Ctrl+V).
  • whisper-server needs ~15 s after login to load the model.
  • Wayland users: log out and back in once (input group), and note
    that terminals paste with Ctrl+Shift+V.
EOF
