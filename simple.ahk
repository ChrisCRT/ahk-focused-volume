#Requires AutoHotkey v2
#SingleInstance Force
Persistent

; A simple version of Focus Volume.ahk without tooltips or the tray menu

Volume_Up:: {
    AppVol.Up()
}

Volume_Down:: {
    AppVol.Down()
}

Volume_Mute:: {
    AppVol.Mute()
}

DetectHiddenWindows(true)

class AppVol {
    static Up(step := 0.02) {
        appName := WinGetProcessName("A")
        appAudioSession := AudioManager.GetAudioSession(appName)

        currentVolume := AudioManager.GetAppVolume(appAudioSession)
        newVolume := Max(0.0, Min(1.0, currentVolume + step))

        AudioManager.SetAppState(appAudioSession, false)
        AudioManager.SetAppVolume(appAudioSession, newVolume)
    }

    static Down(step := -0.02) {
        appName := WinGetProcessName("A")
        appAudioSession := AudioManager.GetAudioSession(appName)

        currentVolume := AudioManager.GetAppVolume(appAudioSession)
        newVolume := Max(0.0, Min(1.0, currentVolume + step))

        AudioManager.SetAppState(appAudioSession, false)
        AudioManager.SetAppVolume(appAudioSession, newVolume)
    }

    static Mute() {
        appName := WinGetProcessName("A")
        appAudioSession := AudioManager.GetAudioSession(appName)

        wasMuted := AudioManager.GetAppState(appAudioSession)

        AudioManager.SetAppState(appAudioSession, !wasMuted)
    }
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

    static GetAudioSession(appName := "") {
        if (this.sessionCache.Has(appName)) {
            return this.sessionCache[appName]
        }

        GUID := Buffer(16)
        IMMDevice := this.IMMDevice(GUID)
        IAudioSessionEnumerator := this.IAudioSessionEnumerator(IMMDevice, GUID)

        ComCall(this.COM.GET_SESSION_COUNT, IAudioSessionEnumerator, "UInt*", &cSessions := 0)

        loop cSessions {
            ComCall(this.COM.GET_SESSION, IAudioSessionEnumerator, "Int", A_Index - 1, "Ptr*", &IAudioSessionControl :=
                0)
            IAudioSessionControl2 := ComObjQuery(IAudioSessionControl, this.IID_IAudioSessionControl2)
            ObjRelease(IAudioSessionControl)
            ComCall(this.COM.GET_PID, IAudioSessionControl2, "UInt*", &pid := 0)

            if (pid != 0 && ProcessGetName(pid) == appName) {
                ISimpleAudioVolume := ComObjQuery(IAudioSessionControl2, this.IID_ISimpleAudioVolume)
                ObjRelease(IAudioSessionEnumerator)

                this.sessionCache[appName] := ISimpleAudioVolume
                return ISimpleAudioVolume
            }
        }
        ObjRelease(IAudioSessionEnumerator)
        return ""
    }

    static GetAppState(appAudioSession) {
        ComCall(this.COM.GET_MUTE, appAudioSession, "Int*", &state := 0)
        return state
    }

    static SetAppState(appAudioSession, state) {
        ComCall(this.COM.SET_MUTE, appAudioSession, "Int", state, "Ptr", 0)
    }

    static GetAppVolume(appAudioSession) {
        ComCall(this.COM.GET_VOLUME, appAudioSession, "Float*", &currentVolume := 0)
        return currentVolume
    }

    static SetAppVolume(appAudioSession, newVolume) {
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

        ComCall(this.COM.GET_SESSION_ENUMERATOR, IAudioSessionManager2, "Ptr*", &IAudioSessionEnumerator := 0) ||
        DllCall("SetLastError", "UInt", 0)
        ObjRelease(IAudioSessionManager2)

        return IAudioSessionEnumerator
    }
}
