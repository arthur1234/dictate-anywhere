# dictate-anywhere

**Системная голосовая диктовка, работающая на 100% локально.** Нажал горячую клавишу, сказал (по-русски, на иврите, по-английски или на любом из ~100 языков Whisper, вперемешку тоже можно), нажал ещё раз, и распознанный текст вставился туда, где стоит курсор: терминал, браузер, WhatsApp, IDE, где угодно.

Без подписок, без облака, звук не покидает компьютер. Только [whisper.cpp](https://github.com/ggml-org/whisper.cpp), постоянно живущий в памяти, горячая клавиша и ~150 строк обвязки.

[English version](README.md) | [גרסה בעברית](README.he.md)

## Зачем

Приложения для диктовки берут $8-15 в месяц за то, что механически является связкой "хоткей + локальная модель + вставка". Если вы не боитесь запустить один скрипт установки, то же самое получается бесплатно, приватнее, и с моделью настолько хорошей, насколько позволяет ваше железо.

- **Любое поле ввода** в любом приложении: текст вставляется туда, где курсор
- **Мультиязычность с автоопределением**: говорите на русском, иврите, английском без переключения чего-либо
- **Быстро**: модель постоянно загружена в локальном `whisper-server`, 6-секундная фраза распознаётся за ~1.5 сек на Apple M-серии
- **Приватно**: аудио уходит на `127.0.0.1` и никуда больше
- **Минимализм**: один файл конфигурации на каждую ОС, стандартные системные утилиты, легко читать и менять

## Как это работает

```
хоткей ──▶ ffmpeg пишет микрофон ──▶ хоткей ──▶ wav ──▶ whisper-server (локально, модель в RAM)
                                                                │
        активное поле ввода ◀── вставка ◀── распознанный текст ◀┘
```

- **macOS**: [Hammerspoon](https://www.hammerspoon.org/) отвечает за хоткей, значок в строке меню и вставку; LaunchAgent держит `whisper-server` запущенным.
- **Linux**: shell-скрипт на кастомном шорткате GNOME; systemd user unit держит `whisper-server`; ввод текста через `xdotool` (X11) или буфер+`ydotool` (Wayland).

## Установка

### macOS

Нужен [Homebrew](https://brew.sh). Настоятельно рекомендуется Apple Silicon (инференс на GPU).

```bash
git clone https://github.com/arthur1234/dictate-anywhere.git
cd dictate-anywhere
./macos/install.sh
```

Затем два разовых разрешения:

1. System Settings → Privacy & Security → **Accessibility** → включить **Hammerspoon** (он вставляет текст за вас)
2. Нажмите `Ctrl+Alt+D` в любом поле, скажите что-нибудь, нажмите ещё раз. macOS спросит доступ к **микрофону** → разрешите

Установщик выбирает `large-v3` (лучшее качество, ~3 GB RAM) на машинах с 16+ GB и `large-v3-turbo` на меньших. Переопределить: `./macos/install.sh --model large-v3-turbo`.

### Linux (Ubuntu / Debian, GNOME)

```bash
git clone https://github.com/arthur1234/dictate-anywhere.git
cd dictate-anywhere
./linux/install.sh
```

Скрипт ставит пакеты, собирает whisper.cpp, скачивает модель (`large-v3-turbo` на CPU, `large-v3` при наличии CUDA toolkit), настраивает systemd-сервис и регистрирует шорткат GNOME `Ctrl+Alt+D`. На Wayland после установки один раз выйдите из системы и войдите снова (членство в группе uinput).

Не GNOME: скрипт установит всё, кроме шортката; привяжите клавишу к `~/.local/bin/dictate.sh` вручную.

### Windows (экспериментально)

Отдельного установщика под Windows пока нет, но ядро кроссплатформенное: whisper.cpp и ffmpeg работают под Windows, а [AutoHotkey](https://www.autohotkey.com/) играет ту же роль, что Hammerspoon на macOS (глобальный хоткей, запись, вставка). Практичный способ настроить это сегодня, путь через AI-агента ниже: скармливаете агенту [PROMPT.md](PROMPT.md), где теперь есть инструкция под Windows. Если у вас заработает, PR с папкой `windows/` очень приветствуется.

### Любая машина, через AI-агента

Если пользуетесь Claude Code (или похожим агентом), просто скажите ему:

> Установи диктовку отсюда: https://github.com/arthur1234/dictate-anywhere - следуй PROMPT.md

Агент адаптирует установку под ваше железо, дистрибутив и окружение. См. [PROMPT.md](PROMPT.md).

## Использование

| Действие | macOS | Linux |
|---|---|---|
| Старт / стоп+вставка | `Ctrl+Alt+D` (или клик по 🎤 в строке меню) | `Ctrl+Alt+D` |
| Отменить запись | `Ctrl+Alt+X` | нажать `Ctrl+Alt+D`, результат стереть |

Распознанный текст также кладётся в буфер обмена: если вставка не сработала, нажмите `Cmd+V` / `Ctrl+V` сами (в линукс-терминалах: `Ctrl+Shift+V`).

## Настройка

- **Хоткей (macOS)**: правьте `HOTKEY_MODS` / `HOTKEY_KEY` в начале `~/.hammerspoon/dictation.lua`, затем перезагрузите Hammerspoon
- **Хоткей (Linux)**: GNOME Settings → Keyboard → Custom Shortcuts
- **Модель**: перезапустите установщик с `--model large-v3 | large-v3-turbo | medium | small`. `large-v3` заметно лучше для иврита и смешанной речи; `turbo` примерно вдвое быстрее и достаточна для английского/русского
- **Порт**: `--port 8766`, если 8765 занят

## Требования

| | Минимум | Комфортно |
|---|---|---|
| macOS | Apple Silicon, 8 GB RAM (модель turbo) | 16+ GB RAM (large-v3) |
| Linux | x86_64, 8 GB RAM, только CPU (turbo) | NVIDIA GPU + CUDA (large-v3) |

Под Windows нативного установщика пока нет; см. [заметку про Windows](#windows-экспериментально) выше про путь через AI-агента.

Файл модели занимает 1.5 GB (turbo) или 2.9 GB (large-v3) на диске и живёт в RAM, пока работает `whisper-server`.

## Если что-то не так

- **"Сервер не отвечает" сразу после входа в систему**: модель грузится ~10-15 сек, попробуйте ещё раз
- **Ничего не вставляется (macOS)**: нет разрешения Accessibility для Hammerspoon, либо перезапустите Hammerspoon после выдачи
- **Запись не идёт (macOS)**: нет разрешения на микрофон для Hammerspoon
- **Ничего не печатается (Linux Wayland)**: вы не перелогинились после установки (группа `input`), или не запущен `ydotoold`: `systemctl --user status ydotoold`. Текст в любом случае в буфере, `Ctrl+V` работает
- **Странный текст из тишины**: Whisper галлюцинирует на пустом аудио ("Субтитры делал..." - классика). Просто не диктуйте тишину :)
- **Статус сервера (Linux)**: `systemctl --user status whisper-server`; логи: `journalctl --user -u whisper-server`
- **Логи сервера (macOS)**: `~/Library/Logs/whisper-server.log`

## Удаление

**macOS**

```bash
launchctl bootout gui/$(id -u)/com.dictate-anywhere.whisper-server
rm ~/Library/LaunchAgents/com.dictate-anywhere.whisper-server.plist
rm ~/.hammerspoon/dictation.lua   # и удалите строку require("dictation") из init.lua
# по желанию: brew uninstall --cask hammerspoon; brew uninstall whisper-cpp; rm -rf ~/Models/whisper
```

**Linux**

```bash
systemctl --user disable --now whisper-server ydotoold
rm ~/.config/systemd/user/whisper-server.service ~/.config/systemd/user/ydotoold.service
rm ~/.local/bin/dictate.sh
# по желанию: rm -rf ~/.local/src/whisper.cpp ~/Models/whisper; удалите шорткат GNOME
```

## Благодарности

Построено на [whisper.cpp](https://github.com/ggml-org/whisper.cpp) Георгия Герганова и контрибьюторов, и [Hammerspoon](https://www.hammerspoon.org/). Автор: [Arthur Tsidkilov](https://github.com/arthur1234).

## Лицензия

[MIT](LICENSE)
