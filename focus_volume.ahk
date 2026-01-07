#Requires AutoHotkey v2
#SingleInstance Force
Persistent

application := "A" ; "A" for focused window or "example.exe" to target a specific app

; # is Win, + is Shift, ^ is Ctrl, ! is Alt
Volume_Up:: {
    result := AudioManager.AppVolume(application, "+2")
    if (result != -1) {
        Utility.CreateToolTip(result.title " | " result.state)
        Utility.UpdateTrayIcon(result.state)
    }
}

Volume_Down:: {
    result := AudioManager.AppVolume(application, "-2")
    if (result != -1) {
        Utility.CreateToolTip(result.title " | " result.state)
        Utility.UpdateTrayIcon(result.state)
    }
}

Volume_Mute:: {
    result := AudioManager.AppVolume(application, "toggle")
    if (result != -1) {
        Utility.CreateToolTip(result.title " | " result.state)
        Utility.UpdateTrayIcon(result.state)
    }
}

class AudioManager {

    ; Returns object with title (String, window title) and state (String, can be "Muted" or current volume percent)
    static AppVolume(target := "A", level := "+1") {
        winTitle := ""
        volumeState := ""

        appName := this.GetAppName(target)
        if (!appName) {
            return -1
        }

        appAudioSession := this.GetAudioSession(appName)
        if (!appAudioSession) {
            return -1
        }

        levelOld := this.GetAppVolume(appAudioSession)

        if (level = "toggle") {
            wasMuted := this.GetAppState(appAudioSession)
            this.SetAppState(appAudioSession, !wasMuted)
            volumeState := wasMuted ? Round(levelOld * 100) "%" : "Muted"
        } else {
            levelNew := (level ~= "^[+-]")
                ? Max(0.0, Min(1.0, levelOld + (Integer(level) / 100)))
                : Max(0.0, Min(1.0, Integer(level) / 100))
            this.SetAppState(appAudioSession, false)  ; Disable mute
            this.SetAppVolume(appAudioSession, levelNew)
            volumeState := Round(levelNew * 100) "%"
        }

        winTitle := StrUpper(SubStr(name := RegExReplace(appName, "\.exe$", ""), 1, 1)) . SubStr(name, 2)

        return { title: winTitle, state: volumeState }
    }

    static GetAppName(target) {
        if (SubStr(target, -4) = ".exe") {
            target := "ahk_exe " target
        }

        try {
            hw := DetectHiddenWindows(true)
            appName := WinGetProcessName(target)
            DetectHiddenWindows(hw)
            return appName
        } catch {
            return ""
        }
    }

    static GetAppState(appAudioSession) {
        ; If the app is currently muted, returns 0 for unmuted,  1 for muted
        ComCall(6, appAudioSession, "Int*", &state := 0)
        return state
    }

    static SetAppState(appAudioSession, state) {
        ; set to 0 for unmuted,  1 for muted
        ComCall(5, appAudioSession, "Int", state, "Ptr", 0)
    }

    static GetAppVolume(appAudioSession) {
        ; returns float between 0 and 1
        ComCall(4, appAudioSession, "Float*", &levelOld := 0)
        return levelOld
    }

    static SetAppVolume(appAudioSession, levelNew) {
        ; set to float between 0 and 1
        ComCall(3, appAudioSession, "Float", levelNew, "Ptr", 0)
    }

    static GetAudioSession(appName := "A") {
        GUID := Buffer(16)
        DllCall("ole32\CLSIDFromString", "Str", "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}", "Ptr", GUID)

        IMMDeviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}",
            "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
        )
        ComCall(4, IMMDeviceEnumerator, "UInt", 0, "UInt", 1, "Ptr*", &IMMDevice := 0)

        ComCall(3, IMMDevice, "Ptr", GUID, "UInt", 23, "Ptr", 0, "Ptr*", &IAudioSessionManager2 := 0)
        ObjRelease(IMMDevice)

        ComCall(5, IAudioSessionManager2, "Ptr*", &IAudioSessionEnumerator := 0) || DllCall("SetLastError", "UInt",
            0)
        ObjRelease(IAudioSessionManager2)

        ComCall(3, IAudioSessionEnumerator, "UInt*", &cSessions := 0)
        ; loops through sessions by the target app name to find one with audio, for apps like Chrome which create multiple windows
        loop cSessions {
            ComCall(4, IAudioSessionEnumerator, "Int", A_Index - 1, "Ptr*", &IAudioSessionControl := 0)
            IAudioSessionControl2 := ComObjQuery(IAudioSessionControl, "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}")
            ObjRelease(IAudioSessionControl)

            ComCall(14, IAudioSessionControl2, "UInt*", &pid := 0)

            if (pid != 0 && ProcessGetName(pid) == appName) {
                ISimpleAudioVolume := ComObjQuery(IAudioSessionControl2, "{87CE5498-68D6-44E5-9215-6DA47EF883D8}")

                ObjRelease(IAudioSessionEnumerator)
                return ISimpleAudioVolume
            }
        }
        return ""
    }
}

trayIcon := A_WinDir . "\System32\SndVolSSO.dll"
TraySetIcon(trayIcon, 11)

class Utility {
    static CreateToolTip(msg) {
        ToolTip(msg)
        SetTimer(() => ToolTip(), -1000)
    }

    static UpdateTrayIcon(volume) {
        if (volume = "Muted") {
            TraySetIcon(trayIcon, 2)
        } else {
            volumeLevel := Integer(StrReplace(volume, "%"))
            if (volumeLevel = 0) {
                TraySetIcon(trayIcon, 8)
            } else if (volumeLevel <= 35) {
                TraySetIcon(trayIcon, 9)
            }
            else if (volumeLevel <= 75) {
                TraySetIcon(trayIcon, 10)
            } else {
                TraySetIcon(trayIcon, 11)
            }
        }
    }
}
