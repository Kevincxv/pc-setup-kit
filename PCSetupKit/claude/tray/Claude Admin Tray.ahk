#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
; The PC Setup Kit app's tray side: it starts at login in the hidden tray (the ^ area) and runs the PC's maintenance on its own; small alerts when something needs the owner, and the
; parts of the app window (dashboard.ps1) that need admin rights. Clicking the icon opens the app window.
; With the optional Claude part (Messiah, setup.ps1 -WithClaude) it also holds the Messiah sessions (Claude Code with
; admin rights): minimizing one sends it to the tray, and at login it opens one hidden (continuing a conversation a
; restart cut off). Runs elevated (scheduled task) so it can hide admin windows and start maintenance without a prompt.

CL := EnvGet("USERPROFILE") "\.claude"
LNK := SessionShortcut()
AI := AiEnabled()
NAME := AI ? "Messiah" : "PC Setup Kit"
DetectHiddenWindows true
OnError TrayError

if FileExist(A_ScriptDir "\app.ico")   ; the app's icon (app-icon.ps1, installed by tray-app.ps1)
    TraySetIcon A_ScriptDir "\app.ico"
else
    TraySetIcon A_WinDir "\System32\imageres.dll", 110   ; gear with a check mark
A_IconTip := NAME
tray := A_TrayMenu
tray.Delete()
tray.Add("Open " NAME, (*) => ShowApp())
tray.Add()
if AI {
    tray.Add("New session", (*) => Run(LNK))
    tray.Add("Show sessions", (*) => ShowAll())
    tray.Add("Hide sessions", (*) => HideAll())
    tray.Add()
}
tray.Add("Run maintenance now", (*) => RunMaint())
tray.Add()
tray.Add("Remove tray icon", (*) => ExitApp())
tray.Default := "Open " NAME
tray.ClickCount := 1
OnMessage(0x404, TrayClick)
; the app window asks the tray for what needs admin rights (it may run without them): a registered message, let
; through from non-elevated windows; the window finds the tray through tray-hwnd.txt
APPCMD := DllCall("RegisterWindowMessage", "Str", "PCSetupKitAppCommand", "UInt")
DllCall("ChangeWindowMessageFilterEx", "Ptr", A_ScriptHwnd, "UInt", APPCMD, "UInt", 1, "Ptr", 0)
OnMessage(APPCMD, AppCommand)
try FileOpen(CL "\tray-hwnd.txt", "w").Write(A_ScriptHwnd)
SetTimer TodoTip, 5000
TodoTip()
SetTimer UnpinIcon, -5000
SetTimer StatusAtLogin, -8000

known := Map()  ; pid -> true if it's a Messiah launcher window
note := 0       ; the corner note currently shown
SetTimer Notify, 30000
SetTimer GamePerf, 300000   ; in-game frame rate and temperatures (game-perf.ps1)
OnMessage(0x219, DeviceChange)   ; WM_DEVICECHANGE: a kit USB plugged in gets a fresh settings backup
if AI {
    SetTimer Watch, 500
    SetTimer AutoStart, -3000
    SetTimer SessionCheck, 300000
    SetTimer RefreshSession, 900000
}

; The optional Claude part is on when setup recorded it (kit-options.txt: claude=on); PCs installed before the option
; existed all had it (same rule as ai-enabled.ps1)
AiEnabled() {
    f := CL "\kit-options.txt"
    if FileExist(f)
        return RegExMatch(FileRead(f), "m)^\s*claude\s*=\s*on\s*$") > 0
    return FileExist(LNK) || FileExist(CL "\admin-sessions.txt") ? true : false
}

; Never show AutoHotkey's error box: the tray runs all day in the background, and a window that closes while the tray
; looks at it (consoles come and go all the time) is not the owner's problem. Logged for /self-improve instead.
TrayError(e, *) {
    try FileAppend FormatTime(, "yyyy-MM-dd HH:mm:ss") "  " e.Message " (line " e.Line ", " e.What ")`n", CL "\tray-errors.log", "UTF-8"
    return 1
}

; The hidden session keeps running old Claude Code after an update; refresh-session.ps1 restarts it on the new
; version when that can't disturb anything (hidden, idle, not mid-task) - same conversation, no prompt
RefreshSession() {
    try Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' CL '\refresh-session.ps1"', , "Hide"
}

; The Claude session shortcut (the elevated launcher). Since the app took over the Start menu entry it lives in .claude;
; older installs still have it in the Start menu until tray-app.ps1 moves it.
SessionShortcut() {
    for f in [CL "\Messiah Session.lnk", A_AppData "\Microsoft\Windows\Start Menu\Programs\Messiah.lnk", A_AppData "\Microsoft\Windows\Start Menu\Programs\Claude (Admin).lnk"] {
        if !FileExist(f)
            continue
        try FileGetShortcut f, , , &args
        catch
            continue
        if InStr(args, "claude-admin-launch.ps1")
            return f
    }
    return CL "\Messiah Session.lnk"
}

; What the app window asks for (see APPCMD). Runs after the message returns, so the window never waits on it.
AppCommand(wParam, *) {
    static work := Map(1, (*) => Run(LNK), 2, (*) => ShowAll(), 3, (*) => HideAll(), 4, (*) => RunMaint(true),
        5, (*) => Run('powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "' CL '\optimize.ps1"'),
        6, (*) => Run('powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "' CL '\maint-watch.ps1"'))
    if work.Has(wParam)
        SetTimer work[wParam], -10
    return 1
}

; The app window (dashboard.ps1; one window - starting it again brings it to the front; it falls back to the text
; status.ps1 by itself). Installs from before it: text.
ShowApp() {
    if FileExist(CL "\dashboard.ps1")
        Run 'conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' CL '\dashboard.ps1"', , "Hide"
    else
        Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' CL '\status.ps1"'
}

; The app runs by itself: at login it starts in the hidden tray and opens no window. Only when the owner turns on
; "Open at login" in its Settings (kit-options.txt "openatlogin=on") the window opens, once per boot: a tray restart
; (update, crash, tray-app.ps1) keeps the boot and doesn't reopen it; a fullscreen game holds it up to 15 min after boot.
StatusAtLogin() {
    if EnvGet("PCKIT_IN_TESTS") != ""
        return
    opts := ""
    try opts := FileRead(CL "\kit-options.txt")
    if !RegExMatch(opts, "im)^\s*openatlogin\s*=\s*on\s*$")
        return
    ini := CL "\tray-notified.ini"
    boot := DateAdd(A_Now, -(A_TickCount // 1000), "Seconds")
    last := IniRead(ini, "shown", "status-boot", "")
    if last != "" && Abs(DateDiff(boot, last, "Seconds")) < 120
        return
    if IsFullscreen() && A_TickCount < 900000
        return SetTimer(StatusAtLogin, -60000)
    IniWrite boot, ini, "shown", "status-boot"
    if !IsFullscreen()
        ShowApp()
}

; The icon lives in the hidden tray (the ^ area next to the clock), which is where Windows puts a new program's icon.
; Versions up to 9/28 pinned it next to the clock once (recorded as "pinned=" in tray-notified.ini): that pin is undone
; once. A pin the owner makes by hand is theirs and stays. Plain AutoHotkey64.exe (shared by every script): left alone.
UnpinIcon() {
    static tries := 0
    ini := CL "\tray-notified.ini"
    exe := RegExReplace(A_AhkPath, ".*\\")
    if exe ~= "i)^AutoHotkey" || IniRead(ini, "shown", "pinned", "") != exe || IniRead(ini, "shown", "unpinned", "") = exe
        return
    Loop Reg, "HKCU\Control Panel\NotifyIconSettings", "K" {
        key := A_LoopRegKey "\" A_LoopRegName
        try path := RegRead(key, "ExecutablePath")
        catch
            continue
        if RegExReplace(path, ".*\\") != exe
            continue
        RegWrite 0, "REG_DWORD", key, "IsPromoted"
        IniWrite exe, ini, "shown", "unpinned"
        return
    }
    if ++tries < 20   ; Windows adds the entry shortly after the icon appears
        SetTimer UnpinIcon, -15000
}

; --- Alerts. Windows notifications are off on this PC (debloat), so the tray shows its own small note in the corner:
; it never takes focus, waits while a game or video is fullscreen, closes after 20 s, and each thing is shown once.
Notify() {
    if IsFullscreen()
        return
    notified := CL "\tray-notified.ini"
    f := CL "\maint-todo.txt"   ; things only the owner can do, left by hidden maintenance
    if FileExist(f) {
        stamp := FileGetTime(f)
        if stamp != IniRead(notified, "shown", "todo", "") {
            items := []
            Loop Parse FileRead(f, "UTF-8"), "`n", "`r"
                if Trim(A_LoopField) != ""
                    items.Push(Trim(A_LoopField))
            IniWrite stamp, notified, "shown", "todo"
            first := StrLen(items.Length ? items[1] : "") > 110 ? SubStr(items[1], 1, 107) "..." : (items.Length ? items[1] : "")
            if items.Length
                return ShowNote("Needs you (" items.Length "): " first (items.Length > 1 ? "`n+ " items.Length - 1 " more" : ""))
        }
    }
    f := CL "\restart-ledger.json"   ; work waiting for the owner's next shutdown/restart (once per new batch)
    if FileExist(f) {
        txt := FileRead(f, "UTF-8"), n := 0, p := 1
        while p := InStr(txt, '"Kind"', , p) {
            n++, p++
        }
        key := (RegExMatch(txt, '"boot":\s*"([^"]+)"', &m) ? m[1] : "") "|" n
        if n && key != IniRead(notified, "shown", "restart", "") {
            IniWrite key, notified, "shown", "restart"
            return ShowNote(n " update(s)/fix(es) will finish the next time you turn the PC off.`nNo need to restart now - whenever suits you.")
        }
    }
}

; The note: dark card with rounded corners (Windows 11), bottom-right, fades in, never takes focus.
; details = true: clicking opens Status (alerts); false: clicking just closes it (short messages)
ShowNote(text, details := true, seconds := 20) {
    global note
    LogNote(text)
    try note.Destroy()
    note := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000")   ; WS_EX_NOACTIVATE: never steals focus
    note.BackColor := "202020", note.MarginX := 20, note.MarginY := 16
    click := details ? NoteClick : (*) => CloseNote()
    note.SetFont("s10 bold c60CDFF", "Segoe UI"), note.SetFont(, "Segoe UI Variable Text")
    note.AddText("w300 +0x100", NAME).OnEvent("Click", click)
    note.SetFont("s10 norm c8A8A8A")
    note.AddText("x+8 yp w22 Right +0x100", Chr(0x2715)).OnEvent("Click", (*) => CloseNote())
    note.SetFont("s10 cF0F0F0")
    note.AddText("xm y+6 w330 +0x100", text).OnEvent("Click", click)
    note.SetFont("s8 c8A8A8A")
    note.AddText("xm y+10 w330 +0x100", details ? "Click for details" : "Click to close").OnEvent("Click", click)
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", note.Hwnd, "int", 33, "int*", 2, "int", 4)            ; rounded corners
    try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", note.Hwnd, "int", 34, "int*", 0x3A3A3A, "int", 4)     ; subtle border
    note.Show("NoActivate Hide")
    note.GetPos(, , &w, &h)
    MonitorGetWorkArea(MonitorGetPrimary(), , , &right, &bottom)
    WinSetTransparent 0, note.Hwnd
    note.Show("NoActivate x" (right - w - 16) " y" (bottom - h - 16))
    Loop 8 {
        Sleep 15
        try WinSetTransparent A_Index * 30 + 5, note.Hwnd
    }
    try WinSetTransparent "Off", note.Hwnd
    SetTimer CloseNote, -seconds * 1000
}
; Every note also goes to notifications.log ("yyyy-MM-dd HH:mm|text", newest last) - the app's Notifications page shows
; them, since a note disappears after a few seconds. Kept to the last 200.
LogNote(text) {
    f := CL "\notifications.log"
    try {
        FileAppend FormatTime(, "yyyy-MM-dd HH:mm") "|" StrReplace(StrReplace(text, "`r"), "`n", " / ") "`n", f, "UTF-8"
        if FileGetSize(f) > 60000 {
            lines := StrSplit(Trim(FileRead(f, "UTF-8"), "`n"), "`n"), keep := ""
            Loop Min(200, lines.Length)
                keep .= lines[lines.Length - Min(200, lines.Length) + A_Index] "`n"
            FileOpen(f, "w", "UTF-8").Write(keep)
        }
    }
}

NoteClick(*) {
    CloseNote()
    ShowApp()
}
CloseNote() {
    global note
    try note.Destroy()
}

; A drive arrived (DBT_DEVICEARRIVAL): 15 s later - once Windows has mounted it - settings-backup.ps1 -ToUsb puts a
; fresh backup on it if it's a kit USB (once a day), so a full reinstall brings the settings back. Not under tests.
DeviceChange(wParam, *) {
    if wParam = 0x8000
        SetTimer UsbBackup, -15000
}
UsbBackup() {
    if EnvGet("PCKIT_IN_TESTS") != "" || !FileExist(CL "\settings-backup.ps1")
        return
    try Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' CL '\settings-backup.ps1" -ToUsb', , "Hide"
}

; Every 5 minutes while something is fullscreen: game-perf.ps1 records a minute of the game's frame rate and the graphics
; card's temperature (it checks it's a game, and samples each game at most every 3 hours). Not under tests.
GamePerf() {
    if EnvGet("PCKIT_IN_TESTS") != "" || !IsFullscreen() || !FileExist(CL "\game-perf.ps1")
        return
    try Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' CL '\game-perf.ps1"', , "Hide"
}
; A game/video covering its whole monitor = don't pop anything up
IsFullscreen() {
    try {
        hwnd := WinExist("A")
        if !hwnd || WinGetClass(hwnd) ~= "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$"
            return false
        WinGetPos &x, &y, &w, &h, hwnd
        mi := Buffer(40, 0), NumPut("uint", 40, mi)
        DllCall("GetMonitorInfo", "ptr", DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr"), "ptr", mi)
        return x <= NumGet(mi, 4, "int") && y <= NumGet(mi, 8, "int") && x + w >= NumGet(mi, 12, "int") && y + h >= NumGet(mi, 16, "int")
    }
    return false
}

; Hidden session at login: the launcher sees CLAUDE_ADMIN_AUTOSTART and resumes or opens idle (no auto maintenance).
; revive: the 5-minute check (SessionCheck) - a fresh idle session, never a resumed one (mode 2)
AutoStart(revive := false) {
    ignore := RehearsalPids()
    for hwnd in Sessions() {
        try pid := WinGetPID(hwnd)
        catch
            continue   ; closed meanwhile
        if !ignore.Has(pid)
            return false
    }
    EnvSet "CLAUDE_ADMIN_AUTOSTART", revive ? "2" : "1"
    try Run 'powershell.exe -NoLogo -ExecutionPolicy Bypass -File "' CL '\claude-admin-launch.ps1"', "C:\WINDOWS\system32", "Hide"
    EnvSet "CLAUDE_ADMIN_AUTOSTART"
    return true
}

; A Messiah session is always there (the owner's rule): whatever ended the last one - closed, crashed, killed - a
; hidden idle one is back within 5 minutes. Not during a login rehearsal (it controls the sessions itself) or tests.
SessionCheck() {
    f := CL "\rehearsal.txt"
    if EnvGet("PCKIT_IN_TESTS") != "" || FileExist(f) && DateDiff(A_Now, FileGetTime(f), "Minutes") < 10
        return
    if AutoStart(true)
        try FileAppend FormatTime(, "M/d/yyyy h:mm tt") "  No Messiah session was running - opened a hidden one`r`n", CL "\session-refresh.log", "UTF-8"
}

TrayClick(wParam, lParam, *) {
    if (lParam != 0x202)  ; left button up
        return
    ShowApp()
    return 1
}

; Session windows. Any window can close between listing it and looking at it, so every look is allowed to fail.
Sessions() {
    global known
    wins := []
    for hwnd in WinGetList("ahk_class ConsoleWindowClass") {
        try pid := WinGetPID(hwnd)
        catch
            continue
        if !known.Has(pid) {
            cmd := ""
            try for p in ComObjGet("winmgmts:").ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" pid)
                cmd := p.CommandLine
            known[pid] := InStr(cmd, "claude-admin-launch.ps1") > 0
        }
        if known[pid]
            wins.Push(hwnd)
    }
    return wins
}

ShowAll() {
    for hwnd in Sessions()
        try {
            WinShow hwnd
            if WinGetMinMax(hwnd) = -1
                WinRestore hwnd
            WinActivate hwnd
        }
}

HideAll() {
    for hwnd in Sessions()
        try WinHide hwnd
}

Watch() {
    global known
    for pid in [known*]
        if !ProcessExist(pid)
            known.Delete(pid)
    ; Minimize = send to tray
    for hwnd in Sessions()
        try if DllCall("IsWindowVisible", "ptr", hwnd) && WinGetMinMax(hwnd) = -1
            WinHide hwnd
}

; Login rehearsal (rehearse-login.ps1): "ignorepids=" lists sessions that stay open during the test and should count
; as "not running"; honored only for 10 minutes after the file was written
RehearsalPids() {
    m := Map(), f := CL "\rehearsal.txt"
    if FileExist(f) && DateDiff(A_Now, FileGetTime(f), "Minutes") < 10
        Loop Parse FileRead(f), "`n", "`r"
            if RegExMatch(A_LoopField, "^ignorepids=(.*)", &mm)
                for p in StrSplit(mm[1], ",")
                    if IsInteger(Trim(p))
                        m[Integer(Trim(p))] := true
    return m
}

; Tooltip shows whether hidden maintenance is running and how many items need the owner
TodoTip() {
    f := CL "\maint-todo.txt"
    n := 0
    if FileExist(f)
        Loop Parse FileRead(f), "`n", "`r"
            if Trim(A_LoopField) != ""
                n++
    tip := n ? NAME " - " n " maintenance item" (n = 1 ? " needs" : "s need") " you" : NAME
    if AI && MaintRunning()
        tip .= "`nHidden maintenance running (open " NAME " > Maintenance > Watch live)"
    A_IconTip := tip
}

MaintRunning() {
    f := CL "\maint-claude-running"
    boot := DateAdd(A_Now, -(A_TickCount // 1000), "Seconds")   ; a marker left from before a shutdown is stale
    return FileExist(f) && DateDiff(A_Now, FileGetTime(f), "Minutes") < 60 && DateDiff(FileGetTime(f), boot, "Seconds") > 0
}

; quiet: asked by the app window, which says so itself
RunMaint(quiet := false) {
    if AI && MaintRunning()
        return quiet ? 0 : ShowNote("Hidden maintenance is already running.`nOpen " NAME " > Maintenance > Watch live to follow it.", false, 8)
    Run 'conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' CL '\claude-bg-maint.ps1" -Force -Unattended', , "Hide"
    if !quiet
        ShowNote("Maintenance started in the background.`nThe result shows in " NAME " (click this).", true, 8)
}
