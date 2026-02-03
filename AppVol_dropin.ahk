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

/**
 * @param {string} [target="A"] 
 * Target application
 * - "A" for the active window
 * - An executable name (e.g. "firefox.exe")
 * - A window title or any WinTitle-compatible string
 * - A numeric string (e.g. "+5", "-5", "50"), which is treated as `level`
 * @param {String} [level="0"]
 * Volume
 * - "0" toggles mute
 * - "+n"|"-n" adjusts volume n amount
 * - "n" sets volume to n%
 * @returns {Integer}
 * @example
 * AppVol("+2") ; focused app +2%
 * AppVol() ; mutes focused app
 * AppVol("process.exe", "33") ; process.exe set to 33%
 * AppVol("process.exe") ; mutes process.exe
 */
AppVol(target := "A", level := "0") {
    if (target ~= "^[-+]?\d+$") {
        level := target
        hwnd := WinActive("A")
    } else if (SubStr(target, -4) = ".exe") {
        hwnd := WinExist("ahk_exe " target)
    } else {
        hwnd := WinExist(target)
    }
    if (!hwnd) {
        return -1
    }

    appAudioSession := AudioManager.GetAudioSession(hwnd)
    if (!appAudioSession) {
        return -1
    }

    isMuted := AudioManager.GetMute(appAudioSession)

    if (isMuted or !level) {
        AudioManager.SetMute(appAudioSession, !isMuted)
    }

    if (level) {
        levelOld := AudioManager.GetVolume(appAudioSession)

        if (level ~= "^[-+]") {
            levelNew := Max(0.0, Min(1.0, levelOld + (level / 100)))
        } else {
            levelNew := Integer(level) / 100
        }

        if (levelNew != levelOld) {
            AudioManager.SetVolume(appAudioSession, levelNew)
        }
    }

    return (IsSet(levelOld) ? Round(levelOld * 100) : -1)
}

/**
 * Windows audio session control
 * @class AudioManager
 * @property GetAudioSession Retrieves an {@link https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nn-audioclient-isimpleaudiovolume|ISimpleAudioVolume} interface for a target application
 * @property GetVolume Gets volume level for an audio session
 * @property SetVolume Sets volume level for an audio session
 * @property GetMute Gets mute state for an audio session
 * @property SetMute Sets mute state for an audio session
 * @property IMMDevice Retrieves the default audio endpoint device (render / multimedia), See {@link https://learn.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nn-mmdeviceapi-immdevice|IMMDevice interface}
 * @property IAudioSessionEnumerator Retrieves an audio session enumerator for a device, See {@link https://learn.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nn-mmdeviceapi-immdeviceenumerator|IMMDeviceEnumerator interface}
 */
class AudioManager {
    static IID_ISimpleAudioVolume := "{87CE5498-68D6-44E5-9215-6DA47EF883D8}"
    static IID_IAudioSessionControl2 := "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}"
    static CLSID_IMMDeviceEnumerator := "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
    static IID_IMMDeviceEnumerator := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
    static IID_IAudioSessionManager2 := "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}"

    /**
     * Method positions inside COM vtables
     * @constant
     */
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

    /**
     * PID to ISimpleAudioVolume COM pointers
     * @returns {Map}
     */
    static sessionCache := Map()

    /**
     * Emptys sessionCache
     */
    static InvalidateCache() {
        this.sessionCache.Clear()
    }

    /**
     * Gets mute state for an audio session
     * @param {Pointer} appAudioSession ISimpleAudioVolume COM interface pointer
     * @returns {Integer} 0 unmuted, 1 muted
     * @example 
     * audioSession := AudioManager.GetAudioSession("ahk_exe process.exe")
     * AudioManager.GetMute(AudioSession)
     */
    static GetMute(appAudioSession) {
        ComCall(this.COM.GET_MUTE, appAudioSession, "Int*", &muteStatus := 0)
        return muteStatus
    }

    /**
     * Sets mute state for an audio session
     * @param {Pointer} appAudioSession ISimpleAudioVolume COM interface pointer
     * @param {Integer} muteStatus 0 unmuted, 1 muted
     * @returns {void}
     * @example 
     * audioSession := AudioManager.GetAudioSession("ahk_exe process.exe")
     * AudioManager.SetMute(AudioSession, 1)
     */
    static SetMute(appAudioSession, muteStatus) {
        ComCall(this.COM.SET_MUTE, appAudioSession, "Int", muteStatus, "Ptr", 0)
    }

    /**
     * Gets volume level for an audio session
     * @param {Pointer} appAudioSession ISimpleAudioVolume COM interface pointer
     * @returns {Float} Volume percent in range 0.0 - 1.0
     * @example 
     * audioSession := AudioManager.GetAudioSession("ahk_exe process.exe")
     * AudioManager.GetVolume(AudioSession)
     */
    static GetVolume(appAudioSession) {
        ComCall(this.COM.GET_VOLUME, appAudioSession, "Float*", &currentVolume := 0)
        return currentVolume
    }

    /**
     * Sets volume level for an audio session
     * @param {Pointer} appAudioSession ISimpleAudioVolume COM interface pointer
     * @param {Float} newVolume Volume percent in range 0.0 - 1.0
     * @returns {void}
     * @example 
     * audioSession := AudioManager.GetAudioSession("ahk_exe process.exe")
     * AudioManager.SetVolume(AudioSession, 0.32)
     */
    static SetVolume(appAudioSession, newVolume) {
        ComCall(this.COM.SET_VOLUME, appAudioSession, "Float", newVolume, "Ptr", 0)
    }

    /**
     * Retrieves the default audio endpoint device (render / multimedia), See {@link https://learn.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nn-mmdeviceapi-immdevice|IMMDevice interface}
     * @param {Buffer} GUID 16-byte buffer that receives a GUID
     * @returns {Pointer} IMMDevice COM interface pointer
     */
    static IMMDevice(GUID) {
        DllCall("ole32\CLSIDFromString", "Str", this.IID_IAudioSessionManager2, "Ptr", GUID)

        IMMDeviceEnumerator := ComObject(this.CLSID_IMMDeviceEnumerator,
            this.IID_IMMDeviceEnumerator
        )
        ComCall(4, IMMDeviceEnumerator, "UInt", 0, "UInt", 1, "Ptr*", &IMMDevice := 0)
        return IMMDevice
    }

    /**
     * Retrieves an audio session enumerator for a device, See {@link https://learn.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nn-mmdeviceapi-immdeviceenumerator|IMMDeviceEnumerator interface}
     * @param {Pointer} IMMDevice IMMDevice COM interface pointer
     * @param {Buffer} GUID GUID for IAudioSessionManager2
     * @returns {Pointer} IAudioSessionEnumerator COM interface pointer
     */
    static IAudioSessionEnumerator(IMMDevice, GUID) {
        ComCall(this.COM.ACTIVATE, IMMDevice, "Ptr", GUID, "UInt", 23, "Ptr", 0, "Ptr*", &IAudioSessionManager2 := 0)
        ObjRelease(IMMDevice)

        ComCall(this.COM.GET_SESSION_ENUMERATOR, IAudioSessionManager2, "Ptr*", &IAudioSessionEnumerator := 0) or
        DllCall("SetLastError", "UInt", 0)
        ObjRelease(IAudioSessionManager2)

        return IAudioSessionEnumerator
    }

    /**
     * Retrieves an {@link https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nn-audioclient-isimpleaudiovolume|ISimpleAudioVolume} interface for a target application
     * @param {String} [target="A"] Window title / HWND / WinTitle-compatible identifier, ('A'|'ahk_exe '|'ahk_class '|'ahk_id '|'ahk_pid '|'ahk_group ')
     * @returns {Pointer|Integer} ISimpleAudioVolume COM pointer or 0 if not found
     * @example 
     * AudioManager.GetAudioSession("ahk_exe process.exe")
     */
    static GetAudioSession(target := "A") {
        appPID := WinGetPID(target)
        if (!appPID) {
            return 0
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
                ISimpleAudioVolume := ComObjQuery(IAudioSessionControl2, this.IID_ISimpleAudioVolume)
                ObjRelease(IAudioSessionEnumerator)

                this.sessionCache[appPID] := ISimpleAudioVolume
                return ISimpleAudioVolume
            }

            if (!fallbackSession) {
                sessionName := ""
                try sessionName := ProcessGetName(sessionPID)

                appName := ""
                try appName := ProcessGetName(appPID)

                if (sessionName = appName) {
                    fallbackSession := ComObjQuery(IAudioSessionControl2, this.IID_ISimpleAudioVolume)
                }
            }
        }
        ObjRelease(IAudioSessionEnumerator)
        this.sessionCache[appPID] := fallbackSession
        return fallbackSession
    }
}
