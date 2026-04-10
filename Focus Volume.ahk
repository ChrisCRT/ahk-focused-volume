#Requires AutoHotkey v2+
#SingleInstance Force
#Include <Audio>
#Include <SystemThemeAwareToolTip>
#Include <ShinsOverlayClass>
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
Volume_Mute::
+Volume_Mute:: {
    FocusVolume.Set("toggle")
}

; --- shifted

+Volume_Up:: {
    FocusVolume.Set("+10")
}
+Volume_Down:: {
    FocusVolume.Set("-10")
}

; --- regular volume
#Volume_Up::
^Volume_Up:: {
    SoundSetVolume("+2")
}
#Volume_Down::
^Volume_Down:: {
    SoundSetVolume("-2")
}
#Volume_Mute::
^Volume_Mute:: {
    SoundSetMute(-1)
}
#+Volume_Up::
^+Volume_Up:: {
    SoundSetVolume("+10")
}
#+Volume_Down::
^+Volume_Down:: {
    SoundSetVolume("-10")
}

; --- lock focus
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
    static CACHE := Map()
    static AUDIO_DEVICE := 0
    static SESSION_MANAGER := 0

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

        appAudio := this.GetCachedAudioSession("ahk_id " hwnd)
        if (!appAudio) {
            return -1
        }

        currentVolume := appAudio.session.GetMasterVolume()
        volumeStatus := ""

        if (level = "toggle" or level = "mute") {
            isMuted := appAudio.session.GetMute()
            appAudio.session.SetMute(!isMuted)

            volumeStatus := isMuted ? Round(currentVolume * 100) "%" : "Muted"
        } else {
            appAudio.session.SetMute(false)  ; Disable mute
            newVolume := (level ~= "^[+-]")
                ? Max(0.0, Min(1.0, currentVolume + (Integer(level) / 100)))
                : Max(0.0, Min(1.0, Integer(level) / 100))
            appAudio.session.SetMasterVolume(newVolume)

            volumeStatus := Round(newVolume * 100) "%"
        }

        this.HandleAudioResult(appAudio.name, volumeStatus, hwnd)
    }

    static GetCachedAudioSession(target) {
        appAudio := 0
        if (this.CACHE.Has(target) and (A_TickCount - this.CACHE[target].created) < this.CACHE[target].maxage) {
            appAudio := this.CACHE[target]
        } else {
            appAudio := this.GetAudioSession(target)
            if (!appAudio) {
                return -1
            }
            this.CACHE[target] := appAudio
        }
        return appAudio
    }

    static GetAudioSession(target) {
        pid := WinGetPID(target)
        processName := ProcessGetName(pid)

        if (!this.AUDIO_DEVICE) {
            this.AUDIO_DEVICE := IMMDeviceEnumerator().GetDefaultAudioEndpoint()
            this.SESSION_MANAGER := this.AUDIO_DEVICE.Activate(IAudioSessionManager2)
        }
        sessionEnumerator := this.SESSION_MANAGER.GetSessionEnumerator()

        match := {
            index: 0,
            session: 0
        }
        failover := 0

        loop sessionEnumerator.GetCount() {
            sessionIndex := (A_Index - 1)
            session := sessionEnumerator.GetSession(sessionIndex)
            sessionControl2 := session.QueryInterface(IAudioSessionControl2)

            ; DEVICE_STATE_DISABLED
            if (sessionControl2.GetState() = 2) {
                continue
            }

            ; Exact match
            sessionPID := sessionControl2.GetProcessId()
            if (sessionPID = pid) {
                match.index := sessionIndex
                match.session := sessionControl2
                break
            }

            ; Vague match
            if (!failover) {
                try sessionProcessName := ProcessGetName(sessionPID)
                if (IsSet(sessionProcessName) and sessionProcessName = processName) {
                    failover := 1
                    match.index := sessionIndex
                    match.session := sessionControl2
                }
            }
        }

        return match.session ? {
            index: match.index,
            session: match.session.QueryInterface(ISimpleAudioVolume),
            name: Utility.GetAppName(target),
            created: A_TickCount,
            maxage: 30000
        } : 0
    }

    /**
     * Updates tray icon, tray menu and optionally create tooltips
     * @param {String} [title=""] target of the result
     * @param {String} [status=""] status of the result
     */
    static HandleAudioResult(title := "", status := "", hwnd := 0) {
        if (this.SETTINGS.enable_tooltips) {
            Graphics.CreateToolTip(title, status)
        }

        if (this.SETTINGS.enable_overlay) {
            Graphics.CreateOverlay(title, status, hwnd)
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

        sessionHWND := StrReplace(this.STATE.application, "ahk_id ", "")
        targetName := ""
        appAudio := this.GetCachedAudioSession("ahk_id " sessionHWND)
        if (!appAudio) {
            return -1
        }
        targetName := appAudio.name

        this.HandleAudioResult(
            targetName,
            targetStatus,
            targetHWND
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
            enable_overlay: !!IniRead(settingsFile, "Preferences", "EnableOverlay", 0),
            debug: true,
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

        ; SetTimer(() => Tray.HandleFocusChange(), 5000)
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
        } else {
            hwnd := WinExist(InStr(target, ".exe") ? "ahk_exe " target : target)
        }

        return hwnd
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

        if ((title != "" or status != "")) {
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

        A_TrayMenu.Add("Show &Overlay", this.ToggleOverlay)
        if (FocusVolume.SETTINGS.enable_overlay) {
            A_TrayMenu.Check("Show &Overlay")
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

        try processName := WinGetProcessName("ahk_id " hwnd)
        if (!processName or processName = "explorer.exe") {
            return -1
        }
        appAudio := FocusVolume.GetCachedAudioSession("ahk_id " hwnd)
        if (!appAudio) {
            return -1
        }
        volume := appAudio.session.GetMasterVolume()
        muted := appAudio.session.GetMute()
        status := muted ? "Muted" : Round(volume * 100) "%"

        this.UpdateIcon(status)
    }

    static UnLockFocusMenu(*) {
        FocusVolume.LockFocus(FocusVolume.STATE.application)
        Tray.UpdateMenu()
    }

    static ToggleTooltips(*) {
        FocusVolume.SETTINGS.enable_tooltips := !FocusVolume.SETTINGS.enable_tooltips
        if (FocusVolume.SETTINGS.enable_tooltips) {
            A_TrayMenu.Check("Show &Tooltips")
        } else {
            A_TrayMenu.Uncheck("Show &Tooltips")
            ToolTip()
        }

        IniWrite(FocusVolume.SETTINGS.enable_tooltips ? 1 : 0,
            FocusVolume.SETTINGS.file,
            "Preferences", "EnableTooltips"
        )
    }

    static ToggleOverlay(*) {
        FocusVolume.SETTINGS.enable_overlay := !FocusVolume.SETTINGS.enable_overlay

        if (FocusVolume.SETTINGS.enable_overlay) {
            A_TrayMenu.Check("Show &Overlay")
        } else {
            A_TrayMenu.Uncheck("Show &Overlay")
            ToolTip()
        }

        IniWrite(FocusVolume.SETTINGS.enable_overlay ? 1 : 0,
            FocusVolume.SETTINGS.file,
            "Preferences", "EnableOverlay"
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

class Graphics {
    /**
     * Creates a tooltip showing application and volume status for 1 second
     * @param {String} title Application name
     * @param {String} status Volume status
     */
    static CreateToolTip(title := "", status := "") {
        ToolTip(
            (title ?? "")
            (title and status ? " - " : "")
            (status ?? "")
        )

        SetTimer(() => ToolTip(), -1000)
    }

    static CreateOverlay(title := "", status := "", hwnd := 0) {
        static overlay
        if (!IsSet(overlay)) {
            MonitorGet(, &left, &top, &right, &bottom)
            overlay := ShinsOverlayClass(
                (right / 2) - 150,
                (bottom / 2) - 75,
                300,
                180,
                1, ; always on top
                1 ; vsync
            )
            overlay.SetAntialias(1)
        }
        static ARGBcolorizationColor := RegRead("HKEY_CURRENT_USER\Software\Microsoft\Windows\DWM",
            "ColorizationColor", "23a8f2")
        static RGBcolorizationColor := ARGBcolorizationColor & 0xFFFFFF
        static colour := {
            fg: 0xff000000 | RGBcolorizationColor,
            fg2: 0x33000000 | RGBcolorizationColor,
            bg: 0x40000000 | RGBcolorizationColor,
            bgshadow: 0xea1b1b1b,
            text: 0xffffffff,
            textshadow: "aa1b1b1b"
        }

        static centerX := (overlay.width / 2)
        static centerY := (overlay.height / 2)
        static thickness := 8
        static radius := 50
        static startAngle := 270

        if (hwnd) {
            WinGetPos(&hwndX, &hwndY, &hwndW, &hwndH, "ahk_id " hwnd)
            overlay.SetPosition(hwndX + (hwndW / 2) - (overlay.width / 2), hwndY + (hwndH / 2) - (overlay.height / 2))
        }

        if (overlay.BeginDraw()) {
            overlay.FillCircle(centerX, centerY, radius, colour.bgshadow)
            overlay.FillCircle(centerX, centerY, radius, colour.bg)
            if (SubStr(status, -1) = "%") {
                volume := Integer(StrReplace(status, "%", ""))
                volumeRadius := radius - thickness
                overlay.DrawCircle(centerX, centerY, volumeRadius, colour.fg2, thickness)

                if (volume > 0) {
                    sweepAngle := (volume = 100) ? 359.99 : (volume / 100) * 360
                    overlay.DrawArc(centerX, centerY, volumeRadius, startAngle, sweepAngle,
                        colour.fg,
                        thickness)
                }
            }

            overlay.DrawText(
                title,
                0,
                10,
                18,
                colour.text,
                "Segoe UI",
                "w" overlay.width " h40 aCenter ol" colour.textshadow
            )
            overlay.DrawText(
                status,
                0,
                centerY - 12,
                18,
                colour.text,
                "Segoe UI",
                "w" overlay.width " h40 aCenter fw600"
            )

            overlay.EndDraw()
        }

        SetTimer(() => overlay.Clear(), -1000)
    }
}
