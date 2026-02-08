#Requires AutoHotkey v2
#SingleInstance Force
Persistent

; Create IAudioSessionManager2's 16-byte CLSID buffer from GUID
DllCall(
    "ole32\CLSIDFromString",
    "Str", AudioManager.IID_IAudioSessionManager2,
    "Ptr", AudioManager.Buffer_IID_IAudioSessionManager2
)

/**
 * Windows audio session control
 * @class AudioManager
 * @property GetAudioSession Retrieves a COM interface pointer to {@link https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nn-audioclient-isimpleaudiovolume|ISimpleAudioVolume} for a target application
 * @property GetVolume Gets volume level for an audio session
 * @property SetVolume Sets volume level for an audio session
 * @property GetMute Gets mute state for an audio session
 * @property SetMute Sets mute state for an audio session
 * @property IMMDevice Retrieves the default audio endpoint device (render / multimedia), See {@link https://learn.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nn-mmdeviceapi-immdevice|IMMDevice interface}
 * @property IAudioSessionManager2 Manage submixes for the audio device (IMMDevice)
 * @property IAudioSessionEnumerator Retrieves an audio session enumerator for a device, See {@link https://learn.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nn-mmdeviceapi-immdeviceenumerator|IMMDeviceEnumerator interface}
 */
class AudioManager {
    static IID_ISimpleAudioVolume := "{87CE5498-68D6-44E5-9215-6DA47EF883D8}"
    static IID_IAudioSessionControl2 := "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}"

    static CLSID_IMMDeviceEnumerator := "{BCDE0395-E52F-467C-8E3D-C4579291692E}"
    static IID_IMMDeviceEnumerator := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
    static IMMDevice_dataFlow := 0
    static IMMDevice_ERole := 1

    static IID_IAudioSessionManager2 := "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}"
    static Buffer_IID_IAudioSessionManager2 := Buffer(16)
    static IAudioSessionManager2_CLSCTX := 1

    /**
     * PID to ISimpleAudioVolume COM pointers
     * {
     * session: ISimpleAudioVolume COM pointer
     * lastSeen: A_TickCount of first use
     * }
     * @returns {Map}
     */
    static sessionCache := Map()

    /**
     * Empties sessionCache
     */
    static InvalidateCache() {
        this.sessionCache.Clear()
    }

    /**
     * Gets mute state for an audio session. ISimpleAudioVolume::GetMute
     * @param {Pointer} appAudioSession ISimpleAudioVolume COM interface pointer
     * @returns {Integer} 0 unmuted, 1 muted.
     * @example 
     * audioSession := AudioManager.GetAudioSession("ahk_exe process.exe")
     * AudioManager.GetMute(AudioSession)
     */
    static GetMute(appAudioSession) {
        ComCall(
            6, ; Get Mute
            appAudioSession,
            "Int*", &muteStatus := 0
        )

        return muteStatus
    }

    /**
     * Sets mute state for an audio session. ISimpleAudioVolume::SetMute
     * @param {Pointer} appAudioSession ISimpleAudioVolume COM interface pointer
     * @param {Integer} muteStatus 0 unmuted, 1 muted
     * @returns {void}
     * @example 
     * audioSession := AudioManager.GetAudioSession("ahk_exe process.exe")
     * AudioManager.SetMute(AudioSession, 1)
     */
    static SetMute(appAudioSession, muteStatus) {
        ComCall(
            5, ; Set Mute
            appAudioSession,
            "Int", muteStatus,
            "Ptr", 0
        )
    }

    /**
     * Gets volume level for an audio session. ISimpleAudioVolume::GetMasterVolume
     * @param {Pointer} appAudioSession ISimpleAudioVolume COM interface pointer
     * @returns {Float} Volume percent in range 0.00 - 1.00
     * @example 
     * audioSession := AudioManager.GetAudioSession("ahk_exe process.exe")
     * AudioManager.GetVolume(AudioSession)
     */
    static GetVolume(appAudioSession) {
        ComCall(
            4, ; Get Volume
            appAudioSession,
            "Float*", &currentVolume := 0
        )

        return currentVolume
    }

    /**
     * Sets volume level for an audio session. ISimpleAudioVolume::SetMasterVolume
     * @param {Pointer} appAudioSession ISimpleAudioVolume COM interface pointer
     * @param {Float} newVolume Volume level in range 0.00 - 1.00
     * @returns {void}
     * @example 
     * audioSession := AudioManager.GetAudioSession("ahk_exe process.exe")
     * AudioManager.SetVolume(AudioSession, 0.32)
     */
    static SetVolume(appAudioSession, newVolume) {
        ComCall(
            3, ; Set Volume
            appAudioSession,
            "Float", newVolume,
            "Ptr", 0
        )
    }

    /**
     * Retrieves the default audio endpoint device (eRender / eMultimedia), 
     * See {@link https://learn.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nf-mmdeviceapi-immdeviceenumerator-getdefaultaudioendpoint|IMMDeviceEnumerator::GetDefaultAudioEndpoint method} (mmdeviceapi.h)
     * @param {Integer} [dataFlow=0] 
     * eRender: 0; produces sound. eCapture: 1; captures sound.
     * @param {Integer} [ERole=1]
     * eConsole: 0; system sounds. eMultimedia: 1; music, movies, narration, most software. eCommunications: 2, voice coms.
     * @returns {Pointer} IMMDevice COM interface pointer
     */
    static IMMDevice(dataFlow := this.IMMDevice_dataFlow, ERole := this.IMMDevice_ERole) {
        IMMDeviceEnumerator := ComObject(this.CLSID_IMMDeviceEnumerator,
            this.IID_IMMDeviceEnumerator
        )

        ComCall(
            4, ; Get default audio endpoint
            IMMDeviceEnumerator,
            "UInt", dataFlow,
            "UInt", ERole,
            "Ptr*", &IMMDevice := 0
        )

        return IMMDevice
    }

    /**
     * Creates IAudioSessionManager2 for the default device from IMMDevice, 
     * @returns {Pointer}
     */
    static IAudioSessionManager2(IMMDevice := this.IMMDevice()) {
        ComCall(
            3, ; Activate IMMDevice
            IMMDevice,
            "Ptr", this.Buffer_IID_IAudioSessionManager2,
            "UInt", this.IAudioSessionManager2_CLSCTX,
            "Ptr", 0, ; pActivationParams
            "Ptr*", &IAudioSessionManager2 := 0
        )
        ObjRelease(IMMDevice)

        if (IAudioSessionManager2 = 0) {
            return 0
        }

        return IAudioSessionManager2
    }

    /**
     * Retrieves an audio session enumerator for a device, See {@link https://learn.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nn-mmdeviceapi-immdeviceenumerator|IMMDeviceEnumerator interface}
     * @returns {Pointer} IAudioSessionEnumerator COM interface pointer
     */
    static IAudioSessionEnumerator() {
        IAudioSessionManager2 := this.IAudioSessionManager2()
        if (IAudioSessionManager2 = 0) {
            return 0
        }

        ComCall(
            5, ; Get Session Enumerator
            IAudioSessionManager2,
            "Ptr*", &IAudioSessionEnumerator := 0
        )
        ObjRelease(IAudioSessionManager2)

        return IAudioSessionEnumerator
    }

    /**
     * Retrieves a COM interface pointer to {@link https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nn-audioclient-isimpleaudiovolume|ISimpleAudioVolume} for a target application
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
            cached := this.sessionCache.Get(appPID)

            if (A_TickCount - cached.lastSeen < 30000) {
                return cached.session
            }

            try {
                this.GetVolume(cached.session)
                cached.lastSeen := A_TickCount
                return cached.session
            } catch {
                this.sessionCache.Delete(appPID)
            }

        }

        IAudioSessionEnumerator := this.IAudioSessionEnumerator()

        ComCall(
            3, ; Get Session Count
            IAudioSessionEnumerator,
            "UInt*", &cSessions := 0
        )

        fallbackSession := 0
        try appName := ProcessGetName(appPID)

        loop cSessions {
            ComCall(
                4, ; Get Session
                IAudioSessionEnumerator,
                "Int", A_Index - 1, ; Current session
                "Ptr*", &IAudioSessionControl := 0
            )
            if (!IAudioSessionControl) {
                continue
            }

            IAudioSessionControl2 := ComObjQuery(IAudioSessionControl, this.IID_IAudioSessionControl2)
            ObjRelease(IAudioSessionControl)
            if (!IAudioSessionControl2) {
                continue
            }

            ComCall(
                14, ; Get PID
                IAudioSessionControl2,
                "UInt*", &sessionPID := 0
            )
            if (!sessionPID) {
                continue
            }

            if (sessionPID = appPID) {
                ISimpleAudioVolume := ComObjQuery(IAudioSessionControl2, this.IID_ISimpleAudioVolume)
                ObjRelease(IAudioSessionEnumerator)

                this.sessionCache.Set(
                    appPID, {
                        session: ISimpleAudioVolume,
                        lastSeen: A_TickCount
                    }
                )

                return ISimpleAudioVolume
            }

            if (!fallbackSession) {
                try sessionName := ProcessGetName(sessionPID)

                if (sessionName = appName) {
                    fallbackSession := ComObjQuery(IAudioSessionControl2, this.IID_ISimpleAudioVolume)
                }
            }

        }
        ObjRelease(IAudioSessionEnumerator)

        if (fallbackSession != 0) {
            this.sessionCache.Set(
                appPID, {
                    session: fallbackSession,
                    lastSeen: A_TickCount
                }
            )
        }
        return fallbackSession
    }
}
