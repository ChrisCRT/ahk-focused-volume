# Focus Volume (AutoHotkey v2)

Control volume mixer using your volume keys, targeting the currently focused window.

Code based on [AppVol.ahk v2 by anonymous1184](https://gist.github.com/anonymous1184/b251cd8407a379d4965791585887cfce#file-appvol-ahk)

## Features

- Adjust volume for the focused application
- Toggle focus locking to a specific app
- Tray icon shows current app volume state
- Optional on-screen tooltips
- Target a specific app via via `settings.ini`

## Hotkeys

| Key | Action |
|---|---|
| `Volume Up` | Increase volume of focused app by 2% |
| `Volume Down` | Decrease volume of focused app by 2% |
| `Volume Mute` | Mute / unmute focused app |
| `Alt + Volume Mute` | Toggle focus lock on the current app |

Holding shift or control lets you control system volume like normal

## Requirements

- Windows 10 / 11, older versions may work
- AutoHotkey v2

## Installation

1. Install [AutoHotkey](https://www.autohotkey.com/) v2
2. Clone or download this repository
3. Run focus_volume.ahk
