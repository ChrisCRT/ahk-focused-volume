# Focus Volume (AutoHotkey v2)

Control volume mixer using your volume keys, targeting the currently focused window.

Code based on [AppVol.ahk v2 by anonymous1184](https://gist.github.com/anonymous1184/b251cd8407a379d4965791585887cfce#file-appvol-ahk)

## Focus Volume.ahk
Allows you to use volume keys to control the vocused application
### Features

- Adjust volume for the focused application
- Toggle focus locking to a specific app
- Tray icon shows current app volume state
- Optional on-screen tooltips
- Target a specific app via via `settings.ini`

### Hotkeys

| Key | Action |
|---|---|
| `Volume Up` | Increase volume of focused app by 2% |
| `Volume Down` | Decrease volume of focused app by 2% |
| `Volume Mute` | Mute / unmute focused app |
| `Alt + Volume Mute` | Lock volume control on the current focused app |

Holding shift or control lets you control system volume like normal

## AppVol_droppin.ahk
Drop-in replacement file for existing AppVol.ahk (v2) scripts, fixes a memory leak, adds support for multiple of the same app, and adds documentation for your editor.
### Example usage
replace `#include AppVol.ahk` with `#include AppVol_droppin.ahk` in your existing script
```ahk
#Requires AutoHotkey v2.0
#SingleInstance Force
#Include AppVol_droppin.ahk
Persistent

; Active Window
1::AppVol() ; Toggle Mute
2::AppVol("-2") ; Decrease volume 2%
3::AppVol("+2") ; Increase volume 2%
4::AppVol(  50) ; Set volume to 50%
5::AppVol( 100) ; Set volume to 100%

; By executable name
+1::AppVol("firefox.exe") ; Toggle Mute
+2::AppVol("firefox.exe", "-2") ; Decrease volume 2%
+3::AppVol("firefox.exe", "+2") ; Increase volume 2%
+4::AppVol("firefox.exe",   50) ; Set volume to 50%
+5::AppVol("firefox.exe",  100) ; Set volume to 100%

; By window title
^1::AppVol("Picture-in-Picture") ; Toggle Mute
^2::AppVol("Picture-in-Picture", "-2") ; Decrease volume 2%
^3::AppVol("Picture-in-Picture", "+2") ; Increase volume 2%
^4::AppVol("Picture-in-Picture",   50) ; Set volume to 50%
^5::AppVol("Picture-in-Picture",  100) ; Set volume to 100%
```
