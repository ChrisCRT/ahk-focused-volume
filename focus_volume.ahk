#Requires AutoHotkey v2
#SingleInstance Force
Persistent

; # is Win, + is Shift, ^ is Ctrl, ! is Alt
Volume_Up::
!Volume_Up:: {
    AppVolume.Set("+2")
}

Volume_Down::
!Volume_Down:: {
    AppVolume.Set("-2")
}

Volume_Mute:: {
    AppVolume.Set("toggle")
}

!Volume_Mute:: {
    AppVolume.ToggleFocus()
}

SETTINGS := AppVolume.ReadSettings()
STATE := {
    application: SETTINGS.application,
    toggleFocusActive: false
}
AppVolume.init()

/**
 * Manages volume control for applications
 * @class AppVolume
 * @property Set Sets volume or toggles mute for the target app
 * @property Get Get volume for target app
 */
class AppVolume {
    /**
     * Sets volume or toggles mute for the target app
     * @param {String} [level="+2"] "+/-n", "n", or "toggle"
     * @param {String} [target=STATE.application] Window title / HWND / WinTitle-compatible identifier, ('A'|'ahk_exe '|'ahk_class '|'ahk_id '|'ahk_pid '|'ahk_group ')
     * @example AppVolume.Set("100", "A")
     */
    static Set(level := "+2", target := STATE.application) {
        hwnd := Utility.GetAppHWND(target)
        if (!hwnd) {
            return -1
        }

        appAudioSession := AudioManager.GetAudioSession("ahk_id " hwnd)
        if (!appAudioSession) {
            return -1
        }

        currentVolume := AudioManager.GetVolume(appAudioSession)
        volumeStatus := ""

        if (level = "toggle") {
            wasMuted := AudioManager.GetMute(appAudioSession)
            AudioManager.SetMute(appAudioSession, !wasMuted)

            volumeStatus := wasMuted ? String(Round(currentVolume * 100)) "%" : "Muted"
        } else {
            newVolume := (level ~= "^[+-]")
                ? Max(0.0, Min(1.0, currentVolume + (Integer(level) / 100)))
                : Max(0.0, Min(1.0, Integer(level) / 100))
            AudioManager.SetMute(appAudioSession, false)  ; Disable mute
            AudioManager.SetVolume(appAudioSession, newVolume)

            volumeStatus := String(Round(newVolume * 100)) "%"
        }

        appName := Utility.GetAppName("ahk_id " hwnd)

        result := { title: appName, status: volumeStatus }
        this.HandleAudioResult(result)
    }

    /**
     * Get volume for target app
     * @param {String} [target=STATE.application] Window title / HWND / WinTitle-compatible identifier, ('A'|'ahk_exe '|'ahk_class '|'ahk_id '|'ahk_pid '|'ahk_group ')
     * @example AppVolume.Get("A")
     */
    static Get(target := STATE.application) {
        hwnd := Utility.GetAppHWND(target)
        if (!hwnd) {
            return -1
        }

        appAudioSession := AudioManager.GetAudioSession("ahk_id " hwnd)
        if (!appAudioSession) {
            return -1
        }

        currentVolume := AudioManager.GetVolume(appAudioSession)
        return Round(Float(currentVolume) * 100) "%"
    }

    /**
     * Updates tray icon, tray menu and optionally create tooltips
     * @param {Object} [result={ title: "", status: "" }] contains {title: {String}, status: {String}}
     */
    static HandleAudioResult(result := { title: "", status: "" }) {
        titleFormatted := Utility.FormatTitleCase(result.title)

        if (SETTINGS.enable_tooltips) {
            Utility.CreateToolTip(titleFormatted, result.status)
        }

        Tray.UpdateIcon(result.status)
        Tray.UpdateMenu(titleFormatted, result.status)
    }

    /**
     * Toggles focus to a different application for volume control
     * @param {String} [target=SETTINGS.focus_application] Window title / HWND / WinTitle-compatible identifier, ('A'|'ahk_exe '|'ahk_class '|'ahk_id '|'ahk_pid '|'ahk_group ')
     */
    static ToggleFocus(target := SETTINGS.focus_application) {
        targetHWND := Utility.GetAppHWND(target)
        stateHWND := Utility.GetAppHWND(STATE.application)

        targetName := Utility.GetAppName("ahk_id " targetHWND)
        if (!targetName or targetName = "explorer.exe") {
            return
        }

        targetStatus := ""

        if (targetHWND = stateHWND and STATE.toggleFocusActive) {
            STATE.application := SETTINGS.application
            STATE.toggleFocusActive := false
            targetStatus := "Unfocused"

        } else {
            STATE.application := "ahk_id " targetHWND
            STATE.toggleFocusActive := true
            targetStatus := "Focused"
        }

        result := { title: targetName, status: targetStatus }
        this.HandleAudioResult(result)
    }

    /**
     * Writes default settings to the settings.ini file
     */
    static DefaultSettings() {
        IniWrite("A", SETTINGS.file, "Preferences", "ApplicationTarget")
        IniWrite("A", SETTINGS.file, "Preferences", "ToggleFocusApplication")
        IniWrite(1, SETTINGS.file, "Preferences", "EnableTooltips")
    }

    /**
     * Reads settings from the settings.ini file
     * @returns {Object}
     */
    static ReadSettings() {
        settingsFile := A_ScriptDir "\settings.ini"
        return {
            file: settingsFile,
            application: IniRead(settingsFile, "Preferences", "ApplicationTarget", "A"),
            focus_application: IniRead(settingsFile, "Preferences", "ToggleFocusApplication", "A"),
            enable_tooltips: !!IniRead(settingsFile, "Preferences", "EnableTooltips", 1),
            debug: false,
        }
    }

    /**
     * Initializes the AppVolume class, sets tray icon/menu, timers.
     */
    static init() {
        DetectHiddenWindows(true)

        if (!FileExist(SETTINGS.file)) {
            this.DefaultSettings()
        }

        Tray.UpdateIcon()
        Tray.UpdateMenu()

        SetTimer(() => Tray.HandleFocusChange(), 5000)
        SetTimer(() => AudioManager.InvalidateCache(), 60000)
    }

    static Restart(*) {
        Reload
    }

    static Exit(*) {
        ExitApp
    }
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

/**
 * Utility functions
 * @class Utility
 * @property GetAppName Gets process name of a target window
 * @property GetAppHWND Gets {@link https://learn.microsoft.com/en-us/windows/apps/develop/ui/retrieve-hwnd|HWND} of a target window
 * @property CreateToolTip Creates a tooltip showing application and volume status for 1 second
 * @property FormatTitleCase Converts To Formatted Title Case
 */
class Utility {
    /**
     * Gets process name of a target window
     * @param {String} target Window title / HWND / WinTitle-compatible identifier, ('A'|'ahk_exe '|'ahk_class '|'ahk_id '|'ahk_pid '|'ahk_group ')
     * @returns {String} Process name or empty string if not found
     */
    static GetAppName(target) {
        try {
            appName := WinGetProcessName(target)
            return appName
        } catch {
            return ""
        }
    }

    /**
     * Gets {@link https://learn.microsoft.com/en-us/windows/apps/develop/ui/retrieve-hwnd|HWND} of a target window
     * @param {String} target Window title / HWND / WinTitle-compatible identifier, ('A'|'ahk_exe '|'ahk_class '|'ahk_id '|'ahk_pid '|'ahk_group ')
     * @returns {Integer} HWND of the window
     */
    static GetAppHWND(target) {
        hwnd := 0

        if (target = "A") {
            hwnd := WinExist("A")
        } else if (InStr(target, ".exe")) {
            hwnd := WinExist("ahk_exe " target)
        } else {
            hwnd := WinExist(target)
        }

        return hwnd
    }

    /**
     * Creates a tooltip showing application and volume status for 1 second
     * @param {String} title Application name
     * @param {String} status Volume status
     */
    static CreateToolTip(title := "", status := "") {
        ToolTip(title " - " status)
        SetTimer(() => ToolTip(), -1000)
    }

    /**
     * Converts To Formatted Title Case
     * @param {String} title window title
     * @returns {String} Formatted Title
     */
    static FormatTitleCase(title) {
        title := RegExReplace(title, "\.exe$", "")
        return StrUpper(SubStr(title, 1, 1)) . SubStr(title, 2)
    }
}

class Tray {
    /**
     * Updates tray icon based on volume status
     * @param {String} status "Muted" or volume percentage string
     */
    static UpdateIcon(status := "") {
        trayIcon := A_WinDir . "\System32\SndVolSSO.dll"
        trayIconMap := {
            muted: 2,
            empty: 8,
            low: 9,
            high: 10,
            full: 11
        }
        trayIconIndex := trayIconMap.full

        if (status = "Muted") {
            trayIconIndex := trayIconMap.muted
        } else if (SubStr(status, -1) = "%") {
            volume := Integer(StrReplace(status, "%", ""))

            trayIconIndex := volume = 0 ? trayIconMap.empty
                : volume < 50 ? trayIconMap.low
                    : volume < 100 ? trayIconMap.high
                        : trayIconMap.full
        }

        TraySetIcon(trayIcon, trayIconIndex)
    }

    /**
     * Updates tray menu / right click menu
     * @param {String} title Application name
     * @param {String} status Volume status
     */
    static UpdateMenu(title := "", status := "") {
        A_TrayMenu.Delete()

        if (title != "") {
            A_TrayMenu.Add("Last Change: " title " - " status, this.DoNothing)
            A_TrayMenu.Add()
        }

        if (STATE.toggleFocusActive) {
            A_TrayMenu.Add("Focus: " title, this.ToggleFocusMenuItem)
            A_TrayMenu.Add()
        }

        A_TrayMenu.Add("Open &Settings", this.OpenSettings)

        A_TrayMenu.Add("Show &Tooltips", this.ToggleTooltips)
        if (SETTINGS.enable_tooltips) {
            A_TrayMenu.Check("Show &Tooltips")
        }

        A_TrayMenu.Add()
        A_TrayMenu.Add("&Volume Mixer", this.OpenVolumeMixer)
        A_TrayMenu.Add()

        if (SETTINGS.debug) {
            A_TrayMenu.Add("&Reload", AppVolume.Restart)
        }

        A_TrayMenu.Add("E&xit", AppVolume.Exit)
    }

    /**
     * Checks currently focused application's volume and updates tray icon
     */
    static HandleFocusChange() {
        target := STATE.application
        hwnd := Utility.GetAppHWND(target)
        if (!hwnd) {
            return
        }

        appName := Utility.GetAppName("ahk_id " hwnd)
        if (!appName or appName = "explorer.exe") {
            return
        }

        appAudioSession := AudioManager.GetAudioSession("ahk_id " hwnd)
        if (!appAudioSession) {
            return
        }

        volume := AudioManager.GetVolume(appAudioSession)
        muted := AudioManager.GetMute(appAudioSession)

        status := muted ? "Muted" : Round(volume * 100) "%"

        this.UpdateIcon(status)
    }

    static ToggleFocusMenuItem(*) {
        AppVolume.ToggleFocus(STATE.application)
        Tray.UpdateMenu()
    }

    static ToggleTooltips(*) {
        SETTINGS.enable_tooltips := !SETTINGS.enable_tooltips

        if (SETTINGS.enable_tooltips) {
            A_TrayMenu.Check("Show &Tooltips")
        } else {
            A_TrayMenu.Uncheck("Show &Tooltips")
        }

        IniWrite(SETTINGS.enable_tooltips ? 1 : 0, SETTINGS.file, "Preferences", "EnableTooltips")

        if (!SETTINGS.enable_tooltips) {
            ToolTip()
        }
    }

    static OpenSettings(*) {
        if (!FileExist(SETTINGS.file)) {
            AppVolume.DefaultSettings()
        }
        Run(SETTINGS.file)
    }

    static OpenVolumeMixer(*) {
        Run("ms-settings:apps-volume")
    }

    static DoNothing(*) {
    }
}
