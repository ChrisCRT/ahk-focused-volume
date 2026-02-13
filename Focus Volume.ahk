#Requires AutoHotkey v2
#SingleInstance Force
#Include <Audio>
#Include <SystemThemeAwareToolTip>
Persistent true
KeyHistory false
ListLines false

; # is Win, + is Shift, ^ is Ctrl, ! is Alt
Volume_Up::
!Volume_Up:: {
    FocusVolume.Set("+2")
}

Volume_Down::
!Volume_Down:: {
    FocusVolume.Set("-2")
}

Volume_Mute:: {
    FocusVolume.Set("toggle")
}

!Volume_Mute:: {
    FocusVolume.LockFocus()
}

FocusVolume.init()

/**
 * Manages volume control for applications
 * @class FocusVolume
 * @property Set Sets volume or toggles mute for the target app
 */
class FocusVolume {
    static SETTINGS := FocusVolume.ReadSettings()
    static STATE := {
        application: this.SETTINGS.application,
        LockFocusActive: false
    }
    static Cache := Map()

    /**
     * Sets volume or toggles mute for the target app
     * @param {String} [level="+2"] "+/-n", "n", or "toggle"
     * @param {String} [target=STATE.application] Window title / HWND / WinTitle-compatible identifier, ('A'|'ahk_exe '|'ahk_class '|'ahk_id '|'ahk_pid '|'ahk_group ')
     * @example FocusVolume.Set("100", "A")
     */
    static Set(level := "+2", target := this.STATE.application) {
        hwnd := Utility.GetAppHWND(target)
        if (!hwnd) {
            return -1
        }

        if (this.Cache.Has(hwnd) and (A_TickCount - this.Cache[hwnd].created < 30000)) {
            cached := this.Cache[hwnd]
            appAudioSession := cached.session
            appName := cached.name
        } else {
            appAudioSession := this.GetAudioSession("ahk_id " hwnd)
            if (!appAudioSession) {
                this.HandleAudioResult("", "No Audio")
                return -1
            }

            appName := Utility.GetAppName("ahk_id " hwnd)
        }

        currentVolume := appAudioSession.GetMasterVolume()
        volumeStatus := ""

        if (level = "toggle") {
            wasMuted := appAudioSession.GetMute()
            appAudioSession.SetMute(!wasMuted)

            volumeStatus := wasMuted ? Round(currentVolume * 100) "%" : "Muted"
        } else {
            newVolume := (level ~= "^[+-]")
                ? Max(0.0, Min(1.0, currentVolume + (Integer(level) / 100)))
                : Max(0.0, Min(1.0, Integer(level) / 100))

            appAudioSession.SetMute(false)  ; Disable mute
            appAudioSession.SetMasterVolume(newVolume)

            volumeStatus := Round(newVolume * 100) "%"
        }

        this.Cache[hwnd] := {
            session: appAudioSession,
            name: appName,
            created: A_TickCount
        }

        this.HandleAudioResult(appName, volumeStatus)
    }

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

    /**
     * Updates tray icon, tray menu and optionally create tooltips
     * @param {String} [title=""] target of the result
     * @param {String} [status=""] status of the result
     */
    static HandleAudioResult(title := "", status := "") {
        if (this.SETTINGS.enable_tooltips) {
            Utility.CreateToolTip(title, status)
        }

        Tray.UpdateIcon(status)
        Tray.UpdateMenu(title, status)
    }

    /**
     * Toggles focus to a different application for volume control
     * @param {String} [target=SETTINGS.focus_application] Window title / HWND / WinTitle-compatible identifier, ('A'|'ahk_exe '|'ahk_class '|'ahk_id '|'ahk_pid '|'ahk_group ')
     */
    static LockFocus(target := this.SETTINGS.focus_application) {
        targetHWND := Utility.GetAppHWND(target)
        stateHWND := Utility.GetAppHWND(this.STATE.application)

        processName := WinGetProcessName("ahk_id " targetHWND)
        if (!processName or processName = "explorer.exe") {
            return -1
        }

        targetStatus := ""

        if (targetHWND = stateHWND and this.STATE.LockFocusActive) {
            this.STATE.application := this.SETTINGS.application
            this.STATE.LockFocusActive := false
            targetStatus := "Unfocused"

        } else {
            this.STATE.application := "ahk_id " targetHWND
            this.STATE.LockFocusActive := true
            targetStatus := "Focused"
        }

        this.HandleAudioResult(
            Utility.GetAppName("ahk_id " targetHWND),
            targetStatus
        )
    }

    /**
     * Writes default settings to the settings.ini file
     */
    static DefaultSettings() {
        IniWrite("A", this.SETTINGS.file, "Preferences", "ApplicationTarget")
        IniWrite("A", this.SETTINGS.file, "Preferences", "LockFocusApplication")
        IniWrite(1, this.SETTINGS.file, "Preferences", "EnableTooltips")
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
            focus_application: IniRead(settingsFile, "Preferences", "LockFocusApplication", "A"),
            enable_tooltips: !!IniRead(settingsFile, "Preferences", "EnableTooltips", 1),
            debug: false,
        }
    }

    /**
     * Initializes the FocusVolume class, sets tray icon/menu, timers.
     */
    static init() {
        DetectHiddenWindows(true)

        if (!FileExist(this.SETTINGS.file)) {
            this.DefaultSettings()
        }

        Tray.UpdateIcon()
        Tray.UpdateMenu()

        SetTimer(() => Tray.HandleFocusChange(), 5000)
    }

    static Restart(*) {
        Reload
    }

    static Exit(*) {
        ExitApp
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
        appName := ""
        try {
            title := WinGetTitle(target)
            titleParts := StrSplit(title, " - ")
            appName := titleParts[titleParts.Length]
        }

        return appName
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
        ToolTip(
            (title ? title : "")
            (title and status ? " - " : "")
            (status ? status : "")
        )

        SetTimer(() => ToolTip(), -1000)
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

        if ((title != "" or status != "") and status != "No Audio") {
            A_TrayMenu.Add(
                "Last Change: "
                (title ? title : "")
                (title and status ? " - " : "")
                (status ? status : ""),
                this.DoNothing
            )
            A_TrayMenu.Add()
        }

        if (FocusVolume.STATE.LockFocusActive and title != "") {
            A_TrayMenu.Add("Focus: " title, this.UnLockFocusMenu)
            A_TrayMenu.Add()
        }

        A_TrayMenu.Add("Open &Settings", this.OpenSettings)

        A_TrayMenu.Add("Show &Tooltips", this.ToggleTooltips)
        if (FocusVolume.SETTINGS.enable_tooltips) {
            A_TrayMenu.Check("Show &Tooltips")
        }

        A_TrayMenu.Add()
        A_TrayMenu.Add("&Volume Mixer", this.OpenVolumeMixer)
        A_TrayMenu.Add()

        if (FocusVolume.SETTINGS.debug) {
            A_TrayMenu.Add("&Reload", FocusVolume.Restart)
        }

        A_TrayMenu.Add("E&xit", FocusVolume.Exit)
    }

    /**
     * Checks currently focused application's volume and updates tray icon
     */
    static HandleFocusChange() {
        target := FocusVolume.STATE.application
        hwnd := Utility.GetAppHWND(target)
        if (!hwnd) {
            return -1
        }

        processName := WinGetProcessName("ahk_id " hwnd)
        if (!processName or processName = "explorer.exe") {
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

        volume := appAudioSession.GetMasterVolume()
        muted := appAudioSession.GetMute()

        status := muted ? "Muted" : Round(volume * 100) "%"

        this.UpdateIcon(status)
    }

    static UnLockFocusMenu(*) {
        FocusVolume.LockFocus(FocusVolume.STATE.application)
        Tray.UpdateMenu()
    }

    static ToggleTooltips(*) {
        FocusVolume.SETTINGS.enable_tooltips := !FocusVolume.SETTINGS.enable_tooltips

        tooltips := FocusVolume.SETTINGS.enable_tooltips
        if (tooltips) {
            A_TrayMenu.Check("Show &Tooltips")
        } else {
            A_TrayMenu.Uncheck("Show &Tooltips")
            ToolTip()
        }

        IniWrite(tooltips ? 1 : 0,
            FocusVolume.SETTINGS.file,
            "Preferences", "EnableTooltips"
        )
    }

    static OpenSettings(*) {
        if (!FileExist(FocusVolume.SETTINGS.file)) {
            FocusVolume.DefaultSettings()
        }
        Run(FocusVolume.SETTINGS.file)
    }

    static OpenVolumeMixer(*) {
        Run("ms-settings:apps-volume")
    }

    static DoNothing(*) {
    }
}
