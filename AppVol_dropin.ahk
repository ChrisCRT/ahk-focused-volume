#Requires AutoHotkey v2
#SingleInstance Force
Persistent
DetectHiddenWindows(true)

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
AppVol(target := "A", level := 0) {
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

    if (FocusVolume.Cache.Has(hwnd) and (A_TickCount - FocusVolume.Cache[hwnd].created < 30000)) {
        cached := FocusVolume.Cache[hwnd]
        appAudioSession := cached.session
    } else {
        appAudioSession := FocusVolume.GetAudioSession("ahk_id " hwnd)
        if (!appAudioSession) {
            return -1
        }
    }

    isMuted := appAudioSession.GetMute()
    if (isMuted or !level) {
        appAudioSession.SetMute(!isMuted)
    }

    if (level) {
        levelOld := appAudioSession.GetMasterVolume()

        if (level ~= "^[-+]") {
            levelNew := Max(0.0, Min(1.0, levelOld + (level / 100)))
        } else {
            levelNew := Max(0.0, Min(1.0, Integer(level) / 100))
        }

        if (levelNew != levelOld) {
            appAudioSession.SetMasterVolume(levelNew)
        }
    }

    FocusVolume.Cache[hwnd] := {
        session: appAudioSession,
        created: A_TickCount
    }

    return (IsSet(levelOld) ? Round(levelOld * 100) : -1)
}

class FocusVolume {
    static Cache := Map()

    /**
     * Retrieves a COM interface pointer to {@link https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nn-audioclient-isimpleaudiovolume|ISimpleAudioVolume} for a target application
     * @param {String} [target="A"] Window title / HWND / WinTitle-compatible identifier, ('A'|'ahk_exe '|'ahk_class '|'ahk_id '|'ahk_pid '|'ahk_group ')
     * @returns {Pointer|Integer} ISimpleAudioVolume COM pointer or 0 if not found
     * @example 
     * AudioManager.GetAudioSession("ahk_exe process.exe")
     */
    static GetAudioSession(target) {
        sessionEnumerator := IMMDeviceEnumerator().GetDefaultAudioEndpoint().Activate(IAudioSessionManager2).GetSessionEnumerator()
        pid := WinGetPID(target)
        processName := ProcessGetName(pid)
        failover := 0

        loop sessionEnumerator.GetCount() {
            sessionControl := sessionEnumerator.GetSession(A_Index - 1).QueryInterface(IAudioSessionControl2)
            if (sessionControl.GetProcessId() = pid) {
                return sessionControl.QueryInterface(ISimpleAudioVolume)
            }

            if (!failover) {
                try sessionName := ProcessGetName(sessionControl.GetProcessId())
                if (IsSet(sessionName) and sessionName = processName) {
                    failover := sessionControl.QueryInterface(ISimpleAudioVolume)
                }
            }

        }

        return failover
    }
}

;from Audio.ahk, doesnt include the full script
#DllLoad ole32.dll
/**
 * @see https://docs.microsoft.com/en-us/windows/win32/api/unknwn/nn-unknwn-iunknown
 * @class IAudioBase
 * @property {String} IID Static GUID for "IUnknown"
 */
class IAudioBase {
    static IID := "{00000000-0000-0000-C000-000000000046}"
    Ptr := 0
    __New(ptr) {
        if IsObject(ptr)
            this.Ptr := ComObjValue(ptr), this.AddRef()
        else this.Ptr := ptr
    }
    __Delete() => this.Release()

    /**
     * @description {@link https://learn.microsoft.com/en-us/windows/win32/api/unknwn/nf-unknwn-iunknown-addref|AddRef()}<br>
     * Increments the reference count for an interface pointer to a COM object.
     * @returns {Integer} Returns the new reference count. This value is intended to be used only for test purposes.
     */
    AddRef() => ObjAddRef(this.Ptr)

    /**
     * @description {@link https://learn.microsoft.com/en-us/windows/win32/api/unknwn/nf-unknwn-iunknown-release|Release()}<br>
     * Decrements the reference count for an interface on a COM object.
     * @returns {Integer} Returns the new reference count. This value is intended to be used only for test purposes.
     */
    Release() => (this.Ptr ? ObjRelease(this.Ptr) : 0)

    /**
     * @description {@link https://learn.microsoft.com/en-us/windows/win32/api/unknwn/nf-unknwn-iunknown-queryinterface(refiid_void)|QueryInterface()}<br>
     * Queries a COM object for a pointer to one of its interface; identifying the interface by a reference to its interface identifier (IID). 
     * If the COM object implements the interface, then it returns a pointer to that interface after calling IUnknown::AddRef on it.
     * @param {GUID|Function} riid
     * @returns {Integer|IAudioBase} 
     */
    QueryInterface(riid) => (HasBase(riid, IAudioBase) ? riid(ComObjQuery(this, riid.IID)) : ComObjQuery(this, riid))

    _events {
        set {
            this.DefineProp("_events", { value: Value }).DefineProp("__Delete", { value: __del })
            __del(this) {
                for k, v in this._events.DefineProp("Delete", { call: (*) => 0 })
                    v(this, k)
                this.Release()
            }
        }
    }

    static STR(ptr) {
        if ptr {
            s := StrGet(ptr), DllCall("ole32\CoTaskMemFree", "ptr", ptr)
            return s
        }
    }
}

;; audioclient.h header

/**
 * @see https://docs.microsoft.com/en-us/windows/win32/api/audioclient/nn-audioclient-isimpleaudiovolume
 * @class ISimpleAudioVolume
 * @extends IAudioBase
 * @property {String} IID GUID for "ISimpleAudioVolume"
 */
class ISimpleAudioVolume extends IAudioBase {
    static IID := "{87CE5498-68D6-44E5-9215-6DA47EF883D8}"

    /**
     * @description {@link https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-isimpleaudiovolume-setmastervolume|SetMasterVolume()}<br>
     * Sets the master volume level for the audio session.
     * @param {Float} fLevel The new master volume level. Valid volume levels are in the range 0.0 to 1.0.
     * @param {Integer} [EventContext=0] Pointer to the event-context GUID.
     */
    SetMasterVolume(fLevel, EventContext := 0) => ComCall(3, this, "Float", fLevel, "Ptr", EventContext)

    /**
     * @description {@link https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-isimpleaudiovolume-getmastervolume|GetMasterVolume()}<br>
     * Retrieves the client volume level for the audio session.
     * @returns {Float}
     */
    GetMasterVolume() => (ComCall(4, this, "Float*", &fLevel := 0), fLevel)

    /**
     * @description {@link https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-isimpleaudiovolume-setmute|SetMute()}<br>
     * Sets the muting state for the audio session.
     * @param {Integer} bMute The new muting state. 1 enables muting. 0 disables muting.
     * @param {Integer} [EventContext=0] Pointer to the event-context GUID.
     */
    SetMute(bMute, EventContext := 0) => ComCall(5, this, "Int", bMute, "Ptr", EventContext)

    /**
     * @description {@link https://learn.microsoft.com/en-us/windows/win32/api/audioclient/nf-audioclient-isimpleaudiovolume-getmute|GetMute()}<br>
     * Retrieves the current muting state for the audio session.
     * @returns {Integer} Current mute state. 0 unmuted. 1 muted.
     */
    GetMute() => (ComCall(6, this, "Int*", &bMute := 0), bMute)
}

;; mmdeviceapi.h header

/**
 * @see https://docs.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nn-mmdeviceapi-immdevice
 * @class IMMDevice
 * @extends IAudioBase
 * @property {String} IID GUID for "IMMDevice"
 */
class IMMDevice extends IAudioBase {
    static IID := "{D666063F-1587-4E43-81F1-B948E807363F}"

    /**
     * @description {@link https://learn.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nf-mmdeviceapi-immdevice-activate|Activate()}<br>
     * Creates a COM object with the specified interface.
     * @param iidorclass 
     * @param dwClsCtx 
     * @param pActivationParams 
     */
    Activate(iidorclass, dwClsCtx := 23, pActivationParams := 0) {
        DllCall("ole32\CLSIDFromString", "Str", HasBase(iidorclass, IAudioBase) ? iidorclass.IID : iidorclass, "Ptr",
        pCLSID := Buffer(16))
        ComCall(3, this, "Ptr", pCLSID, "UInt", dwClsCtx, "Ptr", pActivationParams, "Ptr*", &pInterface := 0)
        return HasBase(iidorclass, IAudioBase) ? iidorclass(pInterface) : ComValue(0xd, pInterface)
    }
}

/**
 * @see https://docs.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nn-mmdeviceapi-immdevicecollection
 * @class IMMDeviceCollection
 * @extends IAudioBase
 * @property {String} IID GUID for "IMMDeviceCollection"
 */
class IMMDeviceCollection extends IAudioBase {
    static IID := "{0BD7A1BE-7A1A-44DB-8397-CC5392387B5E}"
    GetCount() => (ComCall(3, this, "UInt*", &cDevices := 0), cDevices)
    Item(nDevice) => (ComCall(4, this, "UInt", nDevice, "Ptr*", &pDevice := 0), IMMDevice(pDevice))
    __Enum(n) {
        if n == 1
            return (n := this.GetCount(), i := 0, (&v) => i < n ? (v := this.Item(i++), true) : false)
        return (n := this.GetCount(), i := 0, (&k, &v, *) => i < n ? (v := this.Item(k := i++), true) : false)
    }
}

/**
 * @see https://docs.microsoft.com/en-us/windows/win32/api/mmdeviceapi/nn-mmdeviceapi-immdeviceenumerator
 * @class IMMDeviceEnumerator
 * @extends IAudioBase
 * @property {String} IID GUID for "IMMDeviceEnumerator"
 */
class IMMDeviceEnumerator extends IAudioBase {
    static IID := "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
    _events := Map()
    __New() {
        obj := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}", IMMDeviceEnumerator.IID)
        this.Ptr := ComObjValue(obj), this.AddRef()
    }

    /**
     * EDataFlow: eRender 0, eCapture 1, eAll 2, EDataFlow_enum_count 3
     * ERole: eConsole 0, eMultimedia 1, eCommunications 2, ERole_enum_count 3
     * StateMask: DEVICE_STATE_ACTIVE 1, DEVICE_STATE_DISABLED 2, DEVICE_STATE_NOTPRESENT 4, DEVICE_STATE_UNPLUGGED 8, DEVICE_STATEMASK_ALL 0xf
     * EndpointFormFactor: RemoteNetworkDevice 0, Speakers 1, LineLevel 2, Headphones 3, Microphone 4, Headset 5, Handset 6, UnknownDigitalPassthrough 7, SPDIF 8, DigitalAudioDisplayDevice 9, UnknownFormFactor 10, EndpointFormFactor_enum_count 11
     */
    GetDefaultAudioEndpoint(dataFlow := 0, role := 0) => (ComCall(4, this, "Int", dataFlow, "UInt", role, "Ptr*", &
        pEndpoint := 0), IMMDevice(pEndpoint))
}

;; audiopolicy.h header

/**
 * @see https://docs.microsoft.com/en-us/windows/win32/api/audiopolicy/nn-audiopolicy-iaudiosessioncontrol
 * @class IAudioSessionControl
 * @extends IAudioBase
 * @property {String} IID GUID for "IAudioSessionControl"
 */
class IAudioSessionControl extends IAudioBase {
    static IID := "{F4B1A599-7266-4319-A8CA-E70ACB11E8CD}"
    _events := Map()
}

/**
 * @see https://docs.microsoft.com/en-us/windows/win32/api/audiopolicy/nn-audiopolicy-iaudiosessioncontrol2
 * @class IAudioSessionControl2
 * @extends IAudioSessionControl
 * @property {String} IID GUID for "IAudioSessionControl2"
 */
class IAudioSessionControl2 extends IAudioSessionControl {
    static IID := "{bfb7ff88-7239-4fc9-8fa2-07c950be9c6d}"
    GetProcessId() => (ComCall(14, this, "UInt*", &RetVal := 0), RetVal)
}

/**
 * @see https://docs.microsoft.com/en-us/windows/win32/api/audiopolicy/nn-audiopolicy-iaudiosessionenumerator
 * @class IAudioSessionEnumerator
 * @extends IAudioBase
 * @property {String} IID GUID for "IAudioSessionEnumerator"
 */
class IAudioSessionEnumerator extends IAudioBase {
    static IID := "{E2F5BB11-0570-40CA-ACDD-3AA01277DEE8}"
    GetCount() => (ComCall(3, this, "Int*", &SessionCount := 0), SessionCount)
    GetSession(SessionCount) => (ComCall(4, this, "Int", SessionCount, "Ptr*", &Session := 0), IAudioSessionControl(
        Session))
    __Enum(n) {
        if n == 1
            return (n := this.GetCount(), i := 0, (&v) => i < n ? (v := this.GetSession(i++), true) : false)
        return (n := this.GetCount(), i := 0, (&k, &v, *) => i < n ? (v := this.GetSession(k := i++), true) : false)
    }
}

/**
 * @see https://docs.microsoft.com/en-us/windows/win32/api/audiopolicy/nn-audiopolicy-iaudiosessionmanager2
 * @class IAudioSessionManager2
 * @extends IAudioBase
 * @property {String} IID GUID for "IAudioSessionManager2"
 */
class IAudioSessionManager2 extends IAudioBase {
    static IID := "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}"
    _events := Map()
    GetSessionEnumerator() => (ComCall(5, this, "Ptr*", &SessionEnum := 0), IAudioSessionEnumerator(SessionEnum))
}
