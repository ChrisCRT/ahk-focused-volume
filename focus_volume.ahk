#Requires AutoHotkey v2
#SingleInstance Force
Persistent

SETTINGS := App.ReadSettings()

STATE := {
    application: SETTINGS.application,
    toggleFocusActive: false,
}

; # is Win, + is Shift, ^ is Ctrl, ! is Alt
Volume_Up::
!Volume_Up:: {
    App.Volume("+2")
}

Volume_Down::
!Volume_Down:: {
    App.Volume("-2")
}

Volume_Mute:: {
    App.Volume("toggle")
}

!Volume_Mute:: {
    App.ToggleFocus()
}

App.init()

class App {
    static init() {
        DetectHiddenWindows(true)

        if (!FileExist(SETTINGS.file)) {
            this.DefaultSettings()
        }

        Tray.UpdateIcon()
        Tray.UpdateMenu()

        SetTimer(() => this.HandleFocusChange(), 5000)
        SetTimer(() => AudioManager.InvalidateCache(), 60000)
    }

    static Volume(level := "+2", target := STATE.application) {
        ; Returns object with title (String, window title) and state (String, can be "Muted" or current volume percent)
        volumeState := ""

        appName := Utility.GetAppName(target)
        if (!appName) {
            return -1
        }

        appAudioSession := AudioManager.GetAudioSession(appName)
        if (!appAudioSession) {
            return -1
        }

        currentVolume := AudioManager.GetAppVolume(appAudioSession)

        if (level = "toggle") {
            wasMuted := AudioManager.GetAppState(appAudioSession)
            AudioManager.SetAppState(appAudioSession, !wasMuted)
            volumeState := wasMuted ? Round(currentVolume * 100) "%" : "Muted"
        } else {
            newVolume := (level ~= "^[+-]")
                ? Max(0.0, Min(1.0, currentVolume + (Integer(level) / 100)))
                : Max(0.0, Min(1.0, Integer(level) / 100))
            AudioManager.SetAppState(appAudioSession, false)  ; Disable mute
            AudioManager.SetAppVolume(appAudioSession, newVolume)
            volumeState := Round(newVolume * 100) "%"
        }

        result := { title: appName, state: volumeState }
        this.HandleAudioResult(result)
    }

    static HandleAudioResult(result := { title: "", state: "" }) {
        titleFormatted := Utility.FormatTitleCase(result.title)

        if (SETTINGS.enable_tooltips) {
            Utility.CreateToolTip(titleFormatted " - " result.state)
        }

        Tray.UpdateIcon(result.state)
        Tray.UpdateMenu(titleFormatted " - " result.state)
    }

    static HandleFocusChange() {
        appName := Utility.GetAppName(SETTINGS.application)
        if (!appName || appName = "explorer.exe") {
            return
        }

        session := AudioManager.GetAudioSession(appName)
        if (!session) {
            return
        }

        volume := AudioManager.GetAppVolume(session)
        muted := AudioManager.GetAppState(session)

        state := muted ? "Muted" : Round(volume * 100) "%"

        Tray.UpdateIcon(state)
    }

    static ToggleFocus(target := SETTINGS.focus_application) {
        focused := Utility.GetAppName(target)
        focusState := ""

        if (focused = STATE.application) {
            STATE.application := IniRead(SETTINGS.file, "Preferences", "ApplicationTarget", 1)
            STATE.toggleFocusActive := false
            focusState := "Unfocused"

        } else {
            STATE.application := focused
            STATE.toggleFocusActive := true
            focusState := "Focused"
        }

        winTitle := Utility.FormatTitleCase(focused)

        result := { title: winTitle, state: focusState }
        this.HandleAudioResult(result)
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
            this.DefaultSettings()
        }
        Run(SETTINGS.file)
    }

    static DefaultSettings() {
        IniWrite("A", SETTINGS.file, "Preferences", "ApplicationTarget")
        IniWrite("A", SETTINGS.file, "Preferences", "ToggleFocusApplication")
        IniWrite(1, SETTINGS.file, "Preferences", "EnableTooltips")
    }

    static ReadSettings() {
        settingsFile := A_ScriptDir "\settings.ini"
        return {
            file: settingsFile,
            application: IniRead(settingsFile, "Preferences", "ApplicationTarget", 1),
            focus_application: IniRead(settingsFile, "Preferences", "ToggleFocusApplication", 1),
            enable_tooltips: !!IniRead(settingsFile, "Preferences", "EnableTooltips", 1),
            debug: true,
        }
    }

    static OpenVolumeMixer(*) {
        Run("ms-settings:apps-volume")
    }

    static Exit(*) {
        ExitApp
    }

    static Restart(*) {
        Reload
    }

    static DoNothing(*) {
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

    static InvalidateCache() {
        this.sessionCache.Clear()
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
}

class Utility {
    static GetAppName(target) {
        if (SubStr(target, -4) = ".exe") {
            target := "ahk_exe " target
        }

        try {
            appName := WinGetProcessName(target)
            return appName
        } catch {
            return ""
        }
    }

    static CreateToolTip(msg) {
        ToolTip(msg)
        SetTimer(() => ToolTip(), -1000)
    }

    static FormatTitleCase(title) {
        title := RegExReplace(title, "\.exe$", "")
        return StrUpper(SubStr(title, 1, 1)) . SubStr(title, 2)
    }
}

class Tray {
    static UpdateIcon(state := "") {
        trayIcon := A_WinDir . "\System32\SndVolSSO.dll"
        trayIconMap := {
            muted: 2,
            empty: 8,
            low: 9,
            high: 10,
            full: 11
        }
        trayIconIndex := trayIconMap.full

        if (state = "Muted") {
            trayIconIndex := trayIconMap.muted
        } else if (SubStr(state, -1) = "%") {
            volume := Integer(StrReplace(state, "%"))

            trayIconIndex := volume = 0 ? trayIconMap.empty
                : volume < 50 ? trayIconMap.low
                    : volume < 100 ? trayIconMap.high
                        : trayIconMap.full
        }

        TraySetIcon(trayIcon, trayIconIndex)
    }

    static UpdateMenu(msg := "") {
        A_TrayMenu.Delete()

        if (msg != "") {
            A_TrayMenu.Add("Last Change: " msg, App.DoNothing)
            A_TrayMenu.Add()
        }

        if (STATE.toggleFocusActive) {
            A_TrayMenu.Add("Focus: " Utility.FormatTitleCase(STATE.application), App.DoNothing)
            A_TrayMenu.Add()
        }

        A_TrayMenu.Add("Open &Settings", App.OpenSettings)

        A_TrayMenu.Add("Show &Tooltips", App.ToggleTooltips)
        if (SETTINGS.enable_tooltips) {
            A_TrayMenu.Check("Show &Tooltips")
        }

        A_TrayMenu.Add()
        A_TrayMenu.Add("&Volume Mixer", App.OpenVolumeMixer)
        A_TrayMenu.Add()

        if (SETTINGS.debug) {
            A_TrayMenu.Add("&Reload", App.Restart)
        }

        A_TrayMenu.Add("E&xit", App.Exit)
    }
}
