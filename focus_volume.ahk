#Requires AutoHotkey v2
#SingleInstance Force
Persistent

application := "A" ; "A" for focused window or "example.exe" to target a specific app

+Volume_Up:: {
    result := AudioManager.AppVolume(application, "+2")
    if (result != -1) {
        AudioManager.CreateToolTip(result.title " | " result.state)
    }

}

+Volume_Down:: {
    result := AudioManager.AppVolume(application, "-2")
    if (result != -1) {
        AudioManager.CreateToolTip(result.title " | " result.state)
    }

}

+Volume_Mute:: {
    result := AudioManager.AppVolume(application, "mute")
    if (result != -1) {
        AudioManager.CreateToolTip(result.title " | " result.state)
    }

}

class AudioManager {
    static AppVolume(target := "A", level := 0) {
        static winTitle := "", volumeState := ""

        if (SubStr(target, -4) = ".exe") {
            target := "ahk_exe " target
        }

        try {
            hw := DetectHiddenWindows(true)
            appName := WinGetProcessName(target)
            DetectHiddenWindows(hw)
        } catch {
            return -1 ; target not found.
        }

        GUID := Buffer(16)
        DllCall("ole32\CLSIDFromString", "Str", "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}", "Ptr", GUID)

        IMMDeviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}",
            "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
        )
        ComCall(4, IMMDeviceEnumerator, "UInt", 0, "UInt", 1, "Ptr*", &IMMDevice := 0)

        ComCall(3, IMMDevice, "Ptr", GUID, "UInt", 23, "Ptr", 0, "Ptr*", &IAudioSessionManager2 := 0)
        ObjRelease(IMMDevice)

        ComCall(5, IAudioSessionManager2, "Ptr*", &IAudioSessionEnumerator := 0) || DllCall("SetLastError", "UInt", 0)
        ObjRelease(IAudioSessionManager2)

        ComCall(3, IAudioSessionEnumerator, "UInt*", &cSessions := 0)

        loop cSessions {
            ComCall(4, IAudioSessionEnumerator, "Int", A_Index - 1, "Ptr*", &IAudioSessionControl := 0)
            IAudioSessionControl2 := ComObjQuery(IAudioSessionControl, "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}")
            ObjRelease(IAudioSessionControl)

            ComCall(14, IAudioSessionControl2, "UInt*", &pid := 0)

            if (pid != 0 && ProcessGetName(pid) == appName) {
                ISimpleAudioVolume := ComObjQuery(IAudioSessionControl2, "{87CE5498-68D6-44E5-9215-6DA47EF883D8}")

                if (level = "mute") {
                    ComCall(6, ISimpleAudioVolume, "Int*", &wasMuted := 0)
                    ComCall(5, ISimpleAudioVolume, "Int", !wasMuted, "Ptr", 0)
                    volumeState := wasMuted ? "Unmuted" : "Muted"
                } else if (level) {
                    ComCall(4, ISimpleAudioVolume, "Float*", &levelOld := 0)

                    levelNew := (level ~= "^[+-]")
                        ? Max(0.0, Min(1.0, levelOld + (Integer(level) / 100)))
                        : Max(0.0, Min(1.0, Integer(level) / 100))

                    if (levelNew != levelOld) {
                        ComCall(5, ISimpleAudioVolume, "Int", 0, "Ptr", 0)
                        ComCall(3, ISimpleAudioVolume, "Float", levelNew, "Ptr", 0)
                    }

                    volumeState := Round(levelNew * 100) "%"
                }

                break
            }
        }

        ObjRelease(IAudioSessionEnumerator)

        if (volumeState != "") {
            winTitle := StrUpper(SubStr(name := RegExReplace(appName, "\.exe$", ""), 1, 1)) . SubStr(name, 2)
            return { title: winTitle, state: volumeState }
        }
        return -1
    }

    static CreateToolTip(msg) {
        ToolTip(msg)
        SetTimer(() => ToolTip(), -1000)
    }
}
