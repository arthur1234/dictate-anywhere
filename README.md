# dictate-anywhere

**System-wide voice dictation that runs 100% on your machine.** Press a hotkey, speak in any of 100 languages (mixed Russian / Hebrew / English is the home use case), press again, and the recognized text is typed straight into whatever field your cursor is in: terminal, browser, WhatsApp, IDE, anywhere.

No subscriptions, no cloud, no audio leaving your computer. Just [whisper.cpp](https://github.com/ggml-org/whisper.cpp) kept warm in memory, a hotkey, and ~150 lines of glue.

[Русская версия](README.ru.md) | [גרסה בעברית](README.he.md)

## Why

Dictation apps for this exact job charge $8-15/month for what is, mechanically, a hotkey + a local model + paste. If you are comfortable running one install script, you can have the same thing for free, with better privacy and a model as good as your hardware allows.

- **Any text field** in any app: the text is pasted/typed where your cursor is
- **Multilingual with auto-detect**: speak Russian, Hebrew, English, Arabic (or any of ~100 Whisper languages) without switching anything
- **Live feedback** (macOS): while recording, an on-screen equalizer moves with your voice and flattens to a line in silence, with Stop / Cancel buttons
- **Fast**: the model stays loaded in a local `whisper-server`, so a 6-second phrase transcribes in ~1.5 s on an Apple M-series chip
- **Private**: audio goes to `127.0.0.1` and nowhere else
- **Minimal**: one config file per OS, standard system tools, easy to read and modify

## How it works

```
hotkey ──▶ ffmpeg records the mic ──▶ hotkey again ──▶ wav ──▶ whisper-server (local, model in RAM)
                                                                      │
        focused text field ◀── paste/type ◀── recognized text ◀───────┘
```

- **macOS**: [Hammerspoon](https://www.hammerspoon.org/) handles the hotkey, menu bar icon and pasting; a LaunchAgent keeps `whisper-server` running.
- **Linux**: a shell script bound to a GNOME custom shortcut; a systemd user unit keeps `whisper-server` running; typing via `xdotool` (X11) or clipboard+`ydotool` (Wayland).

## Install

### macOS

Requires [Homebrew](https://brew.sh). Apple Silicon strongly recommended (GPU inference).

```bash
git clone https://github.com/arthur1234/dictate-anywhere.git
cd dictate-anywhere
./macos/install.sh
```

Then two one-time permissions:

1. System Settings → Privacy & Security → **Accessibility** → enable **Hammerspoon** (it pastes the text for you)
2. Press `Ctrl+Alt+D` in any text field, speak, press it again. macOS asks for **Microphone** access → Allow

The installer picks `large-v3` (best quality, ~3 GB RAM) on 16+ GB machines and `large-v3-turbo` on smaller ones. Override: `./macos/install.sh --model large-v3-turbo`.

### Linux (Ubuntu / Debian, GNOME)

```bash
git clone https://github.com/arthur1234/dictate-anywhere.git
cd dictate-anywhere
./linux/install.sh
```

The script installs packages, builds whisper.cpp, downloads a model (`large-v3-turbo` on CPU, `large-v3` if a CUDA toolkit is present), sets up a systemd user service and registers the `Ctrl+Alt+D` GNOME shortcut. On Wayland, log out and back in once afterwards (uinput group membership).

Non-GNOME desktops: the script installs everything except the shortcut; bind a key to `~/.local/bin/dictate.sh` manually.

### Windows (experimental)

There's no dedicated Windows installer yet, but the core is cross-platform: whisper.cpp and ffmpeg both run on Windows, and [AutoHotkey](https://www.autohotkey.com/) fills the same role Hammerspoon does on macOS (global hotkey, record, paste). The practical way to set it up today is the AI-agent route below, pointing an agent at [PROMPT.md](PROMPT.md), which now includes Windows-specific guidance. If you get it working, a `windows/` folder PR is very welcome.

### Any machine, via an AI coding agent

If you use Claude Code (or a similar agent), just tell it:

> Install dictation from https://github.com/arthur1234/dictate-anywhere - follow PROMPT.md

The agent adapts the setup to your exact hardware, distro and desktop environment. See [PROMPT.md](PROMPT.md).

## Usage

| Action | macOS | Linux |
|---|---|---|
| Start / stop+paste | `Ctrl+Alt+D` (or click 🎤 in the menu bar) | `Ctrl+Alt+D` |
| Cancel recording | `Ctrl+Alt+X` | press `Ctrl+Alt+D`, discard the result |

The recognized text is also placed on the clipboard, so if pasting ever fails you can just press `Cmd+V` / `Ctrl+V` yourself (in Linux terminals: `Ctrl+Shift+V`).

## Configuration

- **Hotkey (macOS)**: edit `HOTKEY_MODS` / `HOTKEY_KEY` at the top of `~/.hammerspoon/dictation.lua`, then reload Hammerspoon
- **Hotkey (Linux)**: change the binding in GNOME Settings → Keyboard → Custom Shortcuts
- **Model**: re-run the installer with `--model large-v3 | large-v3-turbo | medium | small`. `large-v3` is noticeably better for Hebrew and mixed-language speech; `turbo` is ~2x faster and fine for English/Russian
- **Port**: `--port 8766` if 8765 is taken

## Requirements

| | Minimum | Comfortable |
|---|---|---|
| macOS | Apple Silicon, 8 GB RAM (turbo model) | 16+ GB RAM (large-v3) |
| Linux | x86_64, 8 GB RAM, CPU-only (turbo) | NVIDIA GPU + CUDA (large-v3) |

Windows has no native installer yet; see the [Windows note](#windows-experimental) above for the AI-agent route.

The model file itself is 1.5 GB (turbo) or 2.9 GB (large-v3) on disk and stays resident in RAM while `whisper-server` runs.

## Troubleshooting

- **"server not responding" right after login**: the model takes ~10-15 s to load; try again
- **Nothing pastes (macOS)**: Accessibility permission for Hammerspoon is missing, or restart Hammerspoon after granting it
- **Recording fails (macOS)**: Microphone permission for Hammerspoon is missing
- **Nothing types (Linux Wayland)**: you haven't re-logged-in after install (`input` group), or your compositor needs `ydotoold` running: `systemctl --user status ydotoold`. The text is still on the clipboard, `Ctrl+V` works meanwhile
- **Weird text from silence**: Whisper hallucinates on empty audio ("Thank you." is a classic). Just don't dictate silence :)
- **Server status (Linux)**: `systemctl --user status whisper-server`; logs: `journalctl --user -u whisper-server`
- **Server logs (macOS)**: `~/Library/Logs/whisper-server.log`

## Uninstall

**macOS**

```bash
launchctl bootout gui/$(id -u)/com.dictate-anywhere.whisper-server
rm ~/Library/LaunchAgents/com.dictate-anywhere.whisper-server.plist
rm ~/.hammerspoon/dictation.lua   # and remove the require("dictation") line from init.lua
# optional: brew uninstall --cask hammerspoon; brew uninstall whisper-cpp; rm -rf ~/Models/whisper
```

**Linux**

```bash
systemctl --user disable --now whisper-server ydotoold
rm ~/.config/systemd/user/whisper-server.service ~/.config/systemd/user/ydotoold.service
rm ~/.local/bin/dictate.sh
# optional: rm -rf ~/.local/src/whisper.cpp ~/Models/whisper; remove the GNOME shortcut
```

## Credits

Built on [whisper.cpp](https://github.com/ggml-org/whisper.cpp) by Georgi Gerganov and contributors, and [Hammerspoon](https://www.hammerspoon.org/). Made by [Arthur Tsidkilov](https://github.com/arthur1234).

## License

[MIT](LICENSE)
