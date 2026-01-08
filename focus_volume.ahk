#Requires AutoHotkey v2
#SingleInstance Force
Persistent

SETTINGS := {
    file: A_ScriptDir "\settings.ini",
    application: Trim(IniRead(A_ScriptDir "\settings.ini", "Preferences", "ApplicationTarget", 1)),
    focus_application: Trim(IniRead(A_ScriptDir "\settings.ini", "Preferences", "ToggleFocusApplication", 1)),
    enable_tooltips: !!Trim(IniRead(A_ScriptDir "\settings.ini", "Preferences", "EnableTooltips", 1)),
    debug: true,
}

; # is Win, + is Shift, ^ is Ctrl, ! is Alt
Volume_Up::
!Volume_Up:: {
    result := AudioManager.AppVolume(SETTINGS.application, "+2")
    if (result != -1) {
        Utility.UpdateAll(result)
    }
}

Volume_Down::
!Volume_Down:: {
    result := AudioManager.AppVolume(SETTINGS.application, "-2")
    if (result != -1) {
        Utility.UpdateAll(result)
    }
}

Volume_Mute:: {
    result := AudioManager.AppVolume(SETTINGS.application, "toggle")
    if (result != -1) {
        Utility.UpdateAll(result)
    }
}

!Volume_Mute:: {
    result := AudioManager.ToggleFocus(SETTINGS.focus_application)
    if (result != -1) {
        Utility.UpdateAll(result)
    }
}

lastChange := ""
focusedApp := ""

Utility.init()

class AudioManager {
    ; Returns object with title (String, window title) and state (String, can be "Muted" or current volume percent)
    static AppVolume(target := "A", level := "+1") {
        winTitle := ""
        volumeState := ""

        appName := this.GetAppName(target)
        if (!appName) {
            return -1
        }

        appAudioSession := this.GetAudioSession(appName)
        if (!appAudioSession) {
            return -1
        }

        currentVolume := this.GetAppVolume(appAudioSession)

        if (level = "toggle") {
            wasMuted := this.GetAppState(appAudioSession)
            this.SetAppState(appAudioSession, !wasMuted)
            volumeState := wasMuted ? Round(currentVolume * 100) "%" : "Muted"
        } else {
            newVolume := (level ~= "^[+-]")
                ? Max(0.0, Min(1.0, currentVolume + (Integer(level) / 100)))
                : Max(0.0, Min(1.0, Integer(level) / 100))
            this.SetAppState(appAudioSession, false)  ; Disable mute
            this.SetAppVolume(appAudioSession, newVolume)
            volumeState := Round(newVolume * 100) "%"
        }

        winTitle := Utility.FormatTitleCase(appName)

        global lastChange
        lastChange := { title: winTitle, state: volumeState }

        return { title: winTitle, state: volumeState }
    }

    static ToggleFocus(target := "A") {

        focused := this.GetAppName(target)
        focusState := ""

        if (focused = SETTINGS.application) {
            SETTINGS.application := IniRead(SETTINGS.file, "Preferences", "ApplicationTarget", 1)
            focusState := "Unfocused"

        } else {
            SETTINGS.application := focused
            focusState := "Focused"
        }

        winTitle := Utility.FormatTitleCase(focused)

        return { title: winTitle, state: focusState }
    }

    static GetAppName(target) {
        if (SubStr(target, -4) = ".exe") {
            target := "ahk_exe " target
        }

        try {
            hiddenWindowsState := DetectHiddenWindows(true) ; enable detecting hidden windows
            appName := WinGetProcessName(target)
            DetectHiddenWindows(hiddenWindowsState) ; sets detection to default
            return appName
        } catch {
            return ""
        }
    }

    static GetAppState(appAudioSession) {
        ; If the app is currently muted, returns 0 for unmuted,  1 for muted
        ComCall(6, appAudioSession, "Int*", &state := 0)
        return state
    }

    static SetAppState(appAudioSession, state) {
        ; set to 0 for unmuted,  1 for muted
        ComCall(5, appAudioSession, "Int", state, "Ptr", 0)
    }

    static GetAppVolume(appAudioSession) {
        ; returns float between 0 and 1
        ComCall(4, appAudioSession, "Float*", &currentVolume := 0)
        return currentVolume
    }

    static SetAppVolume(appAudioSession, newVolume) {
        ; set to float between 0 and 1
        ComCall(3, appAudioSession, "Float", newVolume, "Ptr", 0)
    }

    static GetAudioSession(appName := "A") {
        GUID := Buffer(16)
        DllCall("ole32\CLSIDFromString", "Str", "{77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F}", "Ptr", GUID)

        IMMDeviceEnumerator := ComObject("{BCDE0395-E52F-467C-8E3D-C4579291692E}",
            "{A95664D2-9614-4F35-A746-DE8DB63617E6}"
        )
        ComCall(4, IMMDeviceEnumerator, "UInt", 0, "UInt", 1, "Ptr*", &IMMDevice := 0)

        ComCall(3, IMMDevice, "Ptr", GUID, "UInt", 23, "Ptr", 0, "Ptr*", &IAudioSessionManager2 := 0)
        ObjRelease(IMMDevice)

        ComCall(5, IAudioSessionManager2, "Ptr*", &IAudioSessionEnumerator := 0) || DllCall("SetLastError", "UInt",
            0)
        ObjRelease(IAudioSessionManager2)

        ComCall(3, IAudioSessionEnumerator, "UInt*", &cSessions := 0)
        ; loops through sessions by the target app name to find one with audio, for apps like Chrome which create multiple windows
        loop cSessions {
            ComCall(4, IAudioSessionEnumerator, "Int", A_Index - 1, "Ptr*", &IAudioSessionControl := 0)
            IAudioSessionControl2 := ComObjQuery(IAudioSessionControl, "{BFB7FF88-7239-4FC9-8FA2-07C950BE9C6D}")
            ObjRelease(IAudioSessionControl)

            ComCall(14, IAudioSessionControl2, "UInt*", &pid := 0)

            if (pid != 0 && ProcessGetName(pid) == appName) {
                ISimpleAudioVolume := ComObjQuery(IAudioSessionControl2, "{87CE5498-68D6-44E5-9215-6DA47EF883D8}")

                ObjRelease(IAudioSessionEnumerator)
                return ISimpleAudioVolume
            }
        }
        return ""
    }
}

class Utility {
    static init() {
        if (!FileExist(SETTINGS.file)) {
            Utility.DefaultSettings
        }

        Tray.UpdateIcon()
        Tray.UpdateMenu()

        SetTimer(() => this.CheckFocusedWindow(), 5000)
    }

    static UpdateAll(result := { title: "", state: "" }) {
        if (SETTINGS.enable_tooltips) {
            this.CreateToolTip(result.title " - " result.state)
        }

        Tray.UpdateIcon(result.state)
        Tray.UpdateMenu(result.title " - " result.state)
    }

    static CreateToolTip(msg) {
        ToolTip(msg)
        SetTimer(() => ToolTip(), -1000)
    }

    static CheckFocusedWindow() {
        global focusedApp

        appName := AudioManager.GetAppName(SETTINGS.application)
        if (!appName) {
            return
        }

        if (appName = focusedApp || appName = "explorer.exe") {
            return
        }

        focusedApp := appName
        session := AudioManager.GetAudioSession(appName)
        if (!session) {
            return
        }

        volume := AudioManager.GetAppVolume(session)
        muted := AudioManager.GetAppState(session)

        state := muted ? "Muted" : Round(volume * 100) "%"

        Tray.UpdateIcon(state)
    }

    static FormatTitleCase(title) {
        return StrUpper(SubStr(name := RegExReplace(title, "\.exe$", ""), 1, 1)) . SubStr(name, 2)
    }

    static DefaultSettings() {

        IniWrite("A", SETTINGS.file, "Preferences", "ApplicationTarget")
        IniWrite("A", SETTINGS.file, "Preferences", "ToggleFocusApplication")
        IniWrite(1, SETTINGS.file, "Preferences", "EnableTooltips")
    }
}

class Tray {
    static UpdateIcon(volume := "") {
        trayIcon := A_WinDir . "\System32\SndVolSSO.dll"
        if (volume = "" || SubStr(volume, -1) != "%") {
            TraySetIcon(trayIcon, 11)
            return
        }

        if (volume = "Muted") {
            TraySetIcon(trayIcon, 2)
        } else if (volume != "") {
            volumeLevel := Integer(StrReplace(volume, "%"))
            if (volumeLevel = 0) {
                TraySetIcon(trayIcon, 8)
            } else if (volumeLevel <= 49) {
                TraySetIcon(trayIcon, 9)
            }
            else if (volumeLevel <= 99) {
                TraySetIcon(trayIcon, 10)
            } else {
                TraySetIcon(trayIcon, 11)
            }
        }
    }

    static UpdateMenu(msg := "") {
        A_TrayMenu.Delete()

        if (msg != "") {
            A_TrayMenu.Add("Last Change: " msg, this.Empty)
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
            A_TrayMenu.Add("&Reload", this.Restart)
        }

        A_TrayMenu.Add("E&xit", this.Exit)
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
            Utility.DefaultSettings
        }

        Run(SETTINGS.file)

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

    static Empty(*) {

    }
}
