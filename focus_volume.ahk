#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

+Volume_Up:: {
    result := AudioManager.AppVolume("A", "+1")
    if (result != -1)
        CreateToolTip(result.title " | " result.state)
}

+Volume_Down:: {
    result := AudioManager.AppVolume("A", "-1")
    if (result != -1)
        CreateToolTip(result.title " | " result.state)
}

+Volume_Mute:: {
    result := AudioManager.AppVolume("A", "0")
    if (result != -1) {
        CreateToolTip(result.title " | " result.state)
    }
}

CreateToolTip(msg) {
    ToolTip(msg)
    SetTimer(RemoveToolTip, -1000)
}

RemoveToolTip() {
    ToolTip()
}

class AudioManager {

    static AppVolume(target := "A", level := 0) {
        static winTitle := "", volumeState := ""

        if (target ~= "^[-+]?\d+$") {
            level := target
            target := "A"
        } else if (SubStr(target, -4) = ".exe") {
            target := "ahk_exe " target
        }
        try {
            hw := DetectHiddenWindows(true)
            appName := WinGetProcessName(target)
            DetectHiddenWindows(hw)
        } catch {
            return -1 ; target not found.
        }

        guid := Buffer(16)
        DllCall("ole32\CLSIDFromString", "Str", "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}", "Ptr", guid)
        IMMDeviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}",
            "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
        )
        ComCall(4, IMMDeviceEnumerator, "UInt", 0, "UInt", 1, "Ptr*", &IMMDevice := 0)
        ObjRelease(IMMDeviceEnumerator.Ptr)
        ComCall(3, IMMDevice, "Ptr", guid, "UInt", 23, "Ptr", 0, "Ptr*", &IAudioSessionManager2 := 0)
        ObjRelease(IMMDevice)
        ComCall(5, IAudioSessionManager2, "Ptr*", &IAudioSessionEnumerator := 0) || DllCall("SetLastError", "UInt", 0)
        ObjRelease(IAudioSessionManager2)
        ComCall(3, IAudioSessionEnumerator, "UInt*", &cSessions := 0)

        loop cSessions {

            ComCall(4, IAudioSessionEnumerator, "Int", A_Index - 1, "Ptr*", &IAudioSessionControl := 0)
            IAudioSessionControl2 := ComObjQuery(IAudioSessionControl, "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}")
            ObjRelease(IAudioSessionControl)
            ComCall(14, IAudioSessionControl2, "UInt*", &pid := 0)

            if (pid = 0 || ProcessGetName(pid) != appName) {
                continue
            }

            ISimpleAudioVolume := ComObjQuery(IAudioSessionControl2, "{87CE5498-68D6-44E5-9215-6DA47EF883D8}")
            ComCall(6, ISimpleAudioVolume, "Int*", &wasMuted := 0)

            volumeState := ""

            if (wasMuted || !level) {
                ComCall(5, ISimpleAudioVolume, "Int", !wasMuted, "Ptr", 0)
                volumeState := wasMuted ? "Unmuted" : "Muted"
            }
            if (level) {
                ComCall(4, ISimpleAudioVolume, "Float*", &levelOld := 0)
                if (level ~= "^[+-]") {
                    levelNew := Max(0.0, Min(1.0, levelOld + (level / 100)))
                } else {
                    levelNew := Max(0.0, Min(1.0, level / 100))
                }
                if (levelNew != levelOld) {
                    ComCall(3, ISimpleAudioVolume, "Float", levelNew, "Ptr", 0)
                }
                volumeState := Round(levelNew * 100) "%"
            }
            ObjRelease(ISimpleAudioVolume.Ptr)
            break
        }

        winTitle := StrUpper(SubStr(name := RegExReplace(appName, "\.exe$", ""), 1, 1)) . SubStr(name, 2)

        if (volumeState != "") {
            return { title: winTitle, state: volumeState }
        } else {
            return -1
        }

    }
}
