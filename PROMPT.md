# PROMPT.md - installation instructions for AI coding agents

You (the agent) are installing **dictate-anywhere**: system-wide, fully local voice dictation. The user presses a hotkey, speaks, presses it again, and the recognized text is typed/pasted into the focused text field. Recognition runs on a local `whisper-server` (whisper.cpp) that stays resident in memory.

The `macos/` and `linux/` install scripts in this repo handle the standard cases. Your job is to reach the same end state on THIS user's machine, adapting where their setup differs. Prefer running the stock script first; intervene where it fails or does not apply.

## Target end state

1. `whisper-server` from whisper.cpp runs at login, listening on `127.0.0.1:8765`, with a multilingual model loaded (`-l auto -nt`)
2. A global hotkey (default `Ctrl+Alt+D`) toggles: record mic → transcribe via `POST /inference` → paste/type the text into the focused field
3. The text also lands on the clipboard as a fallback
4. Everything is local; no audio leaves the machine

## Steps

1. **Inspect the machine first**: OS and version, CPU/GPU (Apple Silicon? NVIDIA + CUDA toolkit?), RAM, on Linux the session type (`echo $XDG_SESSION_TYPE`) and desktop environment
2. **Pick the model by hardware**, and confirm the choice with the user if in doubt:
   - Apple Silicon or NVIDIA GPU with 16+ GB RAM → `large-v3` (best quality, essential for Hebrew and mixed-language speech)
   - CPU-only or 8 GB RAM → `large-v3-turbo` (or `medium`/`small` on weak hardware)
   - Ask the user which languages they dictate in; if quality on their language disappoints later, `large-v3` is the answer
3. **Run or adapt the platform script** (`macos/install.sh` or `linux/install.sh`). Read it before running so you can explain and fix failures in place
4. **Verify each stage independently** before declaring success:
   - server: `curl -s http://127.0.0.1:8765/inference -F file=@test.wav -F response_format=json` returns `{"text": ...}` (generate `test.wav` with `say` on macOS or any TTS/recording; 16 kHz mono WAV)
   - mic recording: record 2 s, check the file is non-empty and transcribes
   - hotkey: registered and fires the toggle
   - end-to-end: text appears in a focused text field
5. **Walk the user through OS permissions** you cannot grant yourself (macOS: Accessibility + Microphone for Hammerspoon)

## Known pitfalls

- **macOS**: Homebrew prefix differs on Intel (`/usr/local`) vs Apple Silicon (`/opt/homebrew`). Hammerspoon hotkeys work without Accessibility, but pasting (`hs.eventtap`) does NOT: the permission is required, and Hammerspoon may need a restart after granting
- **Linux Wayland (GNOME/Mutter)**: `wtype` does NOT work (no virtual-keyboard protocol). Use clipboard + `ydotool key 29:1 47:1 47:0 29:0` (Ctrl+V). `ydotool` needs `ydotoold` running and write access to `/dev/uinput` (udev rule + `input` group + re-login; the linux script sets this up)
- **Linux X11**: `xdotool type` handles unicode (Cyrillic/Hebrew) fine; prefer it there
- **Terminals** paste with `Ctrl+Shift+V`, not `Ctrl+V`; warn the user
- **ffmpeg stop**: stop recording with SIGTERM (never SIGKILL), so the WAV file is finalized properly
- **whisper hallucinates on silence** (produces "Thank you." etc. from empty audio); a <0.4 s recording is not worth transcribing
- **Segments**: without `-nt`, whisper-server joins segments with newlines; run the server with `-nt` and collapse whitespace in the client
- **Port conflicts**: 8765 may be taken (another whisper-server or dev process); pick another port consistently across server and client then
- **CUDA builds** need `nvcc` (the toolkit), not just `nvidia-smi` (the driver)
- **KDE/Sway/others**: GNOME `gsettings` hotkey registration will not apply; bind `~/.local/bin/dictate.sh` via the DE's own shortcut settings (KDE: System Settings → Shortcuts; Sway: config file)

## Acceptance test

Dictate a short phrase in each language the user cares about into a text editor; the text must appear in the focused field within a few seconds, correctly spelled, in the right language, with sensible punctuation. Then have the USER do the same once, so permissions prompted on first use are granted interactively.
