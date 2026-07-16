# dictate-anywhere

**הכתבה קולית מערכתית שרצה 100% מקומית על המחשב שלכם.** לוחצים על קיצור מקלדת, מדברים (בעברית, ברוסית, באנגלית או בכל אחת מ-100 שפות של Whisper, גם בערבוב), לוחצים שוב, והטקסט המזוהה מודבק היישר לשדה שבו נמצא הסמן: טרמינל, דפדפן, וואטסאפ, IDE, בכל מקום.

בלי מנויים, בלי ענן, הקול לא עוזב את המחשב. רק [whisper.cpp](https://github.com/ggml-org/whisper.cpp) שנשאר טעון בזיכרון, קיצור מקלדת ו-150 שורות של חיבור.

[English version](README.md) | [Русская версия](README.ru.md)

## למה

אפליקציות הכתבה גובות 8-15 דולר בחודש על מה שמכנית הוא "קיצור מקלדת + מודל מקומי + הדבקה". אם אתם מוכנים להריץ סקריפט התקנה אחד, מקבלים את אותו הדבר בחינם, עם פרטיות טובה יותר ועם מודל טוב ככל שהחומרה מאפשרת.

- **כל שדה טקסט** בכל אפליקציה: הטקסט מודבק היכן שנמצא הסמן
- **רב-לשוני עם זיהוי אוטומטי**: דברו עברית, רוסית, אנגלית בלי להחליף כלום
- **מהיר**: המודל נשאר טעון ב-`whisper-server` מקומי, משפט של 6 שניות מזוהה תוך כ-1.5 שניות על שבב Apple M
- **פרטי**: האודיו נשלח ל-`127.0.0.1` ולשום מקום אחר
- **מינימליסטי**: קובץ הגדרות אחד לכל מערכת הפעלה, כלים סטנדרטיים, קל לקרוא ולשנות

## התקנה

### macOS

דרוש [Homebrew](https://brew.sh). מומלץ מאוד Apple Silicon.

```bash
git clone https://github.com/arthur1234/dictate-anywhere.git
cd dictate-anywhere
./macos/install.sh
```

אחר כך שתי הרשאות חד-פעמיות:

1. System Settings → Privacy & Security → **Accessibility** → להפעיל את **Hammerspoon** (הוא מדביק את הטקסט בשבילכם)
2. ללחוץ `Ctrl+Alt+D` בשדה טקסט כלשהו, לדבר, ללחוץ שוב. macOS יבקש גישה ל**מיקרופון** → לאשר

ההתקנה בוחרת `large-v3` (האיכות הטובה ביותר, חשוב במיוחד לעברית) במחשבים עם 16+ GB RAM, ו-`large-v3-turbo` בקטנים יותר.

### Linux (Ubuntu / Debian, GNOME)

```bash
git clone https://github.com/arthur1234/dictate-anywhere.git
cd dictate-anywhere
./linux/install.sh
```

בסביבת Wayland יש להתנתק ולהתחבר מחדש פעם אחת אחרי ההתקנה.

### בכל מחשב, דרך סוכן AI

אם אתם משתמשים ב-Claude Code (או סוכן דומה), פשוט תגידו לו:

> Install dictation from https://github.com/arthur1234/dictate-anywhere - follow PROMPT.md

הסוכן יתאים את ההתקנה לחומרה ולמערכת שלכם. ראו [PROMPT.md](PROMPT.md).

## שימוש

| פעולה | macOS | Linux |
|---|---|---|
| התחלה / עצירה+הדבקה | `Ctrl+Alt+D` (או קליק על 🎤 בשורת התפריטים) | `Ctrl+Alt+D` |
| ביטול הקלטה | `Ctrl+Alt+X` | ללחוץ `Ctrl+Alt+D` ולמחוק את התוצאה |

הטקסט המזוהה נשמר גם בלוח ההעתקה: אם ההדבקה לא עבדה, אפשר פשוט ללחוץ `Cmd+V` / `Ctrl+V` (בטרמינלים של לינוקס: `Ctrl+Shift+V`).

## הגדרות

- **קיצור מקלדת (macOS)**: לערוך את `HOTKEY_MODS` / `HOTKEY_KEY` בראש הקובץ `~/.hammerspoon/dictation.lua`
- **קיצור מקלדת (Linux)**: GNOME Settings → Keyboard → Custom Shortcuts
- **מודל**: להריץ שוב את ההתקנה עם `--model large-v3 | large-v3-turbo | medium | small`. המודל `large-v3` טוב משמעותית לעברית ולדיבור מעורב; `turbo` מהיר בערך פי 2 ומספיק לאנגלית/רוסית
- **פורט**: `--port 8766` אם 8765 תפוס

## דרישות

| | מינימום | נוח |
|---|---|---|
| macOS | Apple Silicon, 8 GB RAM (מודל turbo) | 16+ GB RAM (large-v3) |
| Linux | x86_64, 8 GB RAM, CPU בלבד (turbo) | NVIDIA GPU + CUDA (large-v3) |

## פתרון בעיות

- **"השרת לא מגיב" מיד אחרי הכניסה למערכת**: המודל נטען כ-10-15 שניות, נסו שוב
- **שום דבר לא מודבק (macOS)**: חסרה הרשאת Accessibility ל-Hammerspoon, או שצריך להפעיל אותו מחדש אחרי מתן ההרשאה
- **ההקלטה לא עובדת (macOS)**: חסרה הרשאת מיקרופון ל-Hammerspoon
- **שום דבר לא מוקלד (Linux Wayland)**: לא התנתקתם והתחברתם מחדש אחרי ההתקנה, או ש-`ydotoold` לא רץ. הטקסט בכל מקרה בלוח ההעתקה, `Ctrl+V` עובד
- **לוגים של השרת (macOS)**: `~/Library/Logs/whisper-server.log`
- **סטטוס השרת (Linux)**: `systemctl --user status whisper-server`

## הסרה

ראו את הפקודות המלאות ב-[README באנגלית](README.md#uninstall).

## קרדיטים

בנוי על [whisper.cpp](https://github.com/ggml-org/whisper.cpp) ועל [Hammerspoon](https://www.hammerspoon.org/). נוצר על ידי [ארתור צידקילוב](https://github.com/arthur1234).

## רישיון

[MIT](LICENSE)
