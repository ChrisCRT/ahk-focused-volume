#Requires AutoHotkey v2
#SingleInstance Force
Persistent
DetectHiddenWindows(true)
SetTimer(() => AudioManager.InvalidateCache(), 60000)
/*
Drop-in replacement for AppVol by anonymous1184
Fixes a memory leak, adds support for multiple app instances
Example usage:
    1:: AppVol() ; Toggle Mute
    2:: AppVol("-2") ; Decrease volume 2%
    3:: AppVol("+2") ; Increase volume 2%
    4:: AppVol("50") ; Set volume to 50%
    5:: AppVol("100") ; Set volume to 100%
By executable name:
    +1::AppVol("firefox.exe") ; Toggle Mute
    +2::AppVol("firefox.exe", "-2") ; Decrease volume 2%
    +3::AppVol("firefox.exe", "+2") ; Increase volume 2%
    +4::AppVol("firefox.exe", "50") ; Set volume to 50%
    +5::AppVol("firefox.exe", "100") ; Set volume to 100%
By window title
    ^1::AppVol("Picture-in-Picture") ; Toggle Mute
    ^2::AppVol("Picture-in-Picture", "-2") ; Decrease volume 2%
    ^3::AppVol("Picture-in-Picture", "+2") ; Increase volume 2%
    ^4::AppVol("Picture-in-Picture", "50") ; Set volume to 50%
    ^5::AppVol("Picture-in-Picture", "100") ; Set volume to 100%
*/

AppVol(target := "A", level := 0) {
    if (target ~= "^[-+]?\d+$") {
        level := target
        hwnd := WinActive("A")
    } else if (SubStr(target, -4) = ".exe") {
        hwnd := WinActive("ahk_exe " target)
        || WinExist("ahk_exe " target)
    } else {
        hwnd := WinActive("A")
    }
    if (!hwnd) {
        return -1
    }

    appName := WinGetProcessName("ahk_id " hwnd)
    appTitle := WinGetTitle("ahk_id " hwnd)

    appAudioSession := AudioManager.GetAudioSession(hwnd, appName, appTitle)
    if (!appAudioSession) {
        return -1
    }
    isMuted := AudioManager.GetMute(appAudioSession)

    if (isMuted || !level) {
        AudioManager.SetMute(appAudioSession, !isMuted)
    }

    if (level) {
        levelOld := AudioManager.GetVolume(appAudioSession)

        if (level ~= "^[-+]") {
            levelNew := Max(0.0, Min(1.0, levelOld + (level / 100)))
        } else {
            levelNew := level / 100
        }

        if (levelNew != levelOld) {
            AudioManager.SetVolume(appAudioSession, levelNew)
        }
    }

    return (IsSet(levelOld) ? Round(levelOld * 100) : -1)
}

class AudioManager {
    static IID_ISimpleAudioVolume := "{87CE5498-68D6-44E5-9215-6DA47EF883D8}"
    static IID_IAudioSessionControl2 := "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}"
    static CLSID_IMMDeviceEnumerator := "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
    static IID_IMMDeviceEnumerator := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
    static IID_IAudioSessionManager2 := "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}"

    static COM := {
        GET_MUTE: 6,
        SET_MUTE: 5,
        GET_VOLUME: 4,
        SET_VOLUME: 3,
        ACTIVATE: 3,
        GET_SESSION_ENUMERATOR: 5,
        GET_SESSION_COUNT: 3,
        GET_SESSION: 4,
        GET_PID: 14,
    }

    static sessionCache := Map()
    static InvalidateCache() {
        this.sessionCache.Clear()
    }

    static GetMute(appAudioSession) {
        ComCall(this.COM.GET_MUTE, appAudioSession, "Int*", &muteStatus := 0)
        return muteStatus
    }

    static SetMute(appAudioSession, muteStatus) {
        ComCall(this.COM.SET_MUTE, appAudioSession, "Int", muteStatus, "Ptr", 0)
    }

    static GetVolume(appAudioSession) {
        ComCall(this.COM.GET_VOLUME, appAudioSession, "Float*", &currentVolume := 0)
        return currentVolume
    }

    static SetVolume(appAudioSession, newVolume) {
        ComCall(this.COM.SET_VOLUME, appAudioSession, "Float", newVolume, "Ptr", 0)
    }

    static IMMDevice(GUID) {
        DllCall("ole32\CLSIDFromString", "Str", this.IID_IAudioSessionManager2, "Ptr", GUID)

        IMMDeviceEnumerator := ComObject(this.CLSID_IMMDeviceEnumerator,
            this.IID_IMMDeviceEnumerator
        )
        ComCall(4, IMMDeviceEnumerator, "UInt", 0, "UInt", 1, "Ptr*", &IMMDevice := 0)
        return IMMDevice
    }

    static IAudioSessionEnumerator(IMMDevice, GUID) {
        ComCall(this.COM.ACTIVATE, IMMDevice, "Ptr", GUID, "UInt", 23, "Ptr", 0, "Ptr*", &IAudioSessionManager2 := 0)
        ObjRelease(IMMDevice)

        ComCall(this.COM.GET_SESSION_ENUMERATOR, IAudioSessionManager2, "Ptr*", &IAudioSessionEnumerator := 0) or
        DllCall("SetLastError", "UInt", 0)
        ObjRelease(IAudioSessionManager2)

        return IAudioSessionEnumerator
    }

    static GetAudioSession(hwnd := "", appName := "", appTitle := "") {
        appPID := WinGetPID(hwnd)
        if (!appPID) {
            return ""
        }

        if (this.sessionCache.Has(appPID)) {
            return this.sessionCache[appPID]
        }

        GUID := Buffer(16)
        IMMDevice := this.IMMDevice(GUID)
        IAudioSessionEnumerator := this.IAudioSessionEnumerator(IMMDevice, GUID)

        ComCall(this.COM.GET_SESSION_COUNT, IAudioSessionEnumerator, "UInt*", &cSessions := 0)
        fallbackSession := 0

        loop cSessions {
            ComCall(this.COM.GET_SESSION, IAudioSessionEnumerator, "Int", A_Index - 1, "Ptr*",
                &IAudioSessionControl := 0)
            IAudioSessionControl2 := ComObjQuery(IAudioSessionControl, this.IID_IAudioSessionControl2)
            ObjRelease(IAudioSessionControl)

            ComCall(this.COM.GET_PID, IAudioSessionControl2, "UInt*", &sessionPID := 0)
            if (!sessionPID) {
                continue
            }

            if (sessionPID != 0 and sessionPID = appPID) {
                sessionTitle := ""
                try sessionTitle := WinGetTitle("ahk_pid " sessionPID)

                if (sessionTitle = appTitle) {
                    ISimpleAudioVolume := ComObjQuery(IAudioSessionControl2, this.IID_ISimpleAudioVolume)
                    ObjRelease(IAudioSessionEnumerator)

                    this.sessionCache[appPID] := ISimpleAudioVolume
                    return ISimpleAudioVolume
                }
            }

            if (!fallbackSession) {
                processName := ""
                try processName := ProcessGetName(sessionPID)

                if (processName = appName) {
                    fallbackSession := ComObjQuery(IAudioSessionControl2, this.IID_ISimpleAudioVolume)
                }
            }
        }
        ObjRelease(IAudioSessionEnumerator)
        this.sessionCache[appPID] := fallbackSession
        return fallbackSession
    }
}
