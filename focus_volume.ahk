#Requires AutoHotkey v2
#SingleInstance Force
#Include AudioManager.ahk
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
            this.HandleAudioResult("", "No App Audio Found")
            return -1
        }

        currentVolume := AudioManager.GetVolume(appAudioSession)
        volumeStatus := ""

        if (level = "toggle") {
            wasMuted := AudioManager.GetMute(appAudioSession)
            AudioManager.SetMute(appAudioSession, !wasMuted)

            volumeStatus := wasMuted ? Round(currentVolume * 100) "%" : "Muted"
        } else {
            newVolume := (level ~= "^[+-]")
                ? Max(0.0, Min(1.0, currentVolume + (Integer(level) / 100)))
                : Max(0.0, Min(1.0, Integer(level) / 100))

            AudioManager.SetMute(appAudioSession, false)  ; Disable mute
            AudioManager.SetVolume(appAudioSession, newVolume)

            volumeStatus := Round(newVolume * 100) "%"
        }

        appName := Utility.GetAppName("ahk_id " hwnd)

        this.HandleAudioResult(appName, volumeStatus)
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
        return Round(currentVolume * 100) "%"
    }

    /**
     * Updates tray icon, tray menu and optionally create tooltips
     * @param {String} [title=""] target of the result
     * @param {String} [status=""] status of the result
     */
    static HandleAudioResult(title := "", status := "") {
        titleFormatted := Utility.FormatTitleCase(title)

        if (SETTINGS.enable_tooltips) {
            Utility.CreateToolTip(titleFormatted, status)
        }

        Tray.UpdateIcon(status)
        Tray.UpdateMenu(titleFormatted, status)
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

        this.HandleAudioResult(targetName, targetStatus)
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

        AudioManager.IMMDevice_ERole := 2 ; voice coms priority over media, for apps like discord

        if (!FileExist(SETTINGS.file)) {
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
        ToolTip(
            (title ? title : "")
            (title and status ? " - " : "")
            (status ? status : "")
        )

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

        if (title != "" or status != "") {
            A_TrayMenu.Add(
                "Last Change: "
                (title ? title : "")
                (title and status ? " - " : "")
                (status ? status : ""),
                this.DoNothing
            )
            A_TrayMenu.Add()
        }

        if (STATE.toggleFocusActive and title != "") {
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
            return -1
        }

        appName := Utility.GetAppName("ahk_id " hwnd)
        if (!appName or appName = "explorer.exe") {
            return -1
        }

        appAudioSession := AudioManager.GetAudioSession("ahk_id " hwnd)
        if (!appAudioSession) {
            return -1
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
