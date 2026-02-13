#requires AutoHotkey v2

/**
 * Forked from {@link https://github.com/nperovic/SystemThemeAwareToolTip/blob/main/SystemThemeAwareToolTip.ahk|nperovic/SystemThemeAwareToolTip}
 * @author nperovic
 * @date 2024/03/20
 * @description 
 * Make your ToolTip style conform to the current system theme (dark/light mode, rounded corners of Win 11 windows).
 * Simply include this Class in your script, no need to create an instance.
 */
class SystemThemeAwareToolTip {
    static IsDarkMode => !RegRead("HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
        "AppsUseLightTheme", 1)

    static __New() {
        if this.HasOwnProp("HTT") || !this.IsDarkMode
            return

        GroupAdd("tooltips_class32", "ahk_class tooltips_class32")

        this.HTT := DllCall("User32.dll\CreateWindowEx", "UInt", 8, "Ptr", StrPtr("tooltips_class32"), "Ptr", 0, "UInt",
        3, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "Ptr", A_ScriptHwnd, "Ptr", 0, "Ptr", 0, "Ptr", 0)
        this.SubWndProc := CallbackCreate(TT_WNDPROC, , 4)
        this.OriWndProc := DllCall(A_PtrSize = 8 ? "SetClassLongPtr" : "SetClassLongW", "Ptr", this.HTT, "Int", -24,
            "Ptr", this.SubWndProc, "UPtr")

        TT_WNDPROC(hWnd, uMsg, wParam, lParam) {
            static WM_CREATE := 0x0001

            if (this.IsDarkMode && uMsg = WM_CREATE) {
                SetDarkToolTip(hWnd)

                if (VerCompare(A_OSVersion, "10.0.22000") > 0) {
                    SetRoundedCorner(hWnd, 3)
                }

            }

            return DllCall(This.OriWndProc, "Ptr", hWnd, "UInt", uMsg, "Ptr", wParam, "Ptr", lParam, "UInt")
        }

        SetDarkToolTip(hWnd) => DllCall("UxTheme\SetWindowTheme", "Ptr", hWnd, "Ptr", StrPtr("DarkMode_Explorer"),
        "Ptr", StrPtr("ToolTip"))

        SetRoundedCorner(hwnd, level := 3) => DllCall("Dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 33, "Ptr*",
            level, "UInt", 4)
    }

    static __Delete() => (this.HTT && WinKill("ahk_group tooltips_class32"))
}
