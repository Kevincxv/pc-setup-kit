#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
; Tray icon of the PC Setup Kit: status, the maintenance to-do list and small alerts when something needs the owner.
; With the optional Claude part (Messiah, setup.ps1 -WithClaude) it also holds the Messiah sessions (Claude Code with
; admin rights): left-click opens a session or shows/hides them, minimizing one sends it to the tray, and at login it
; opens one hidden (continuing a conversation a restart cut off). Runs elevated (scheduled task) so it can hide admin windows.

CL := EnvGet("USERPROFILE") "\.claude"
LNK := A_AppData "\Microsoft\Windows\Start Menu\Programs\Messiah.lnk"
if !FileExist(LNK) && FileExist(StrReplace(LNK, "Messiah", "Claude (Admin)"))   ; until the next login moves it (migrate-names.ps1)
    LNK := StrReplace(LNK, "Messiah", "Claude (Admin)")
AI := AiEnabled()
NAME := AI ? "Messiah" : "PC Setup Kit"
DetectHiddenWindows true
OnError TrayError

if AI
    TraySetIcon EnvGet("USERPROFILE") "\.local\bin\claude.exe"
else
    TraySetIcon A_WinDir "\System32\imageres.dll", 110   ; gear with a check mark
A_IconTip := NAME
tray := A_TrayMenu
tray.Delete()
if AI {
    tray.Add("New " NAME " session", (*) => Run(LNK))
    tray.Add("Show sessions", (*) => ShowAll())
    tray.Add("Hide sessions", (*) => HideAll())
    tray.Add()
}
tray.Add("Status", (*) => ShowStatus())
tray.Add("Maintenance to-do list", (*) => OpenFile(CL "\maint-todo.txt", "Nothing needs you right now."))
tray.Add("Last maintenance report", (*) => OpenFile(CL "\maint-report.txt", "No report yet."))
if AI {   ; hidden Claude runs at login: /maintain when needed, then /self-improve once a day
    tray.Add("Watch maintenance live", (*) => Run('powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "' CL '\maint-watch.ps1"'))
    tray.Add("Self-improvement journal", (*) => OpenFile(CL "\selfimprove-journal.md", "No self-improvement runs yet."))
}
tray.Add("Run maintenance now", (*) => RunMaint())
tray.Add("Optimize this PC now", (*) => Run('powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "' CL '\optimize.ps1"'))
tray.Add()
tray.Add("Remove tray icon", (*) => ExitApp())
tray.Default := AI ? "New " NAME " session" : "Status"
tray.ClickCount := 1
OnMessage(0x404, TrayClick)
SetTimer TodoTip, 5000
TodoTip()
SetTimer PinIcon, -5000

known := Map()  ; pid -> true if it's a Messiah launcher window
note := 0       ; the corner note currently shown
SetTimer Notify, 30000
if AI {
    SetTimer Watch, 500
    SetTimer AutoStart, -3000
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

; The Status window (dashboard.ps1; it falls back to the text status.ps1 by itself). Installs from before it: text.
ShowStatus() {
    if FileExist(CL "\dashboard.ps1")
        Run 'conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' CL '\dashboard.ps1"', , "Hide"
    else
        Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' CL '\status.ps1"'
}

; Pin the icon next to the clock once. Windows keeps a tray entry per program and hides new ones in the ^ area; the
; tray runs as its own program (Messiah.exe / PC Setup Kit.exe, tray-app.ps1), so this pins only its own entry. Plain
; AutoHotkey64.exe is shared by every AutoHotkey script: left alone. Once the owner hides it again, that choice stays.
PinIcon() {
    static tries := 0
    exe := RegExReplace(A_AhkPath, ".*\\")
    if exe ~= "i)^AutoHotkey" || IniRead(CL "\tray-notified.ini", "shown", "pinned", "") = exe
        return
    Loop Reg, "HKCU\Control Panel\NotifyIconSettings", "K" {
        key := A_LoopRegKey "\" A_LoopRegName
        try path := RegRead(key, "ExecutablePath")
        catch
            continue
        if RegExReplace(path, ".*\\") != exe
            continue
        try RegRead(key, "IsPromoted")
        catch   ; never set = hidden by default
            RegWrite 1, "REG_DWORD", key, "IsPromoted"
        IniWrite exe, CL "\tray-notified.ini", "shown", "pinned"
        return
    }
    if ++tries < 20   ; Windows adds the entry shortly after the icon appears
        SetTimer PinIcon, -15000
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
NoteClick(*) {
    CloseNote()
    ShowStatus()
}
CloseNote() {
    global note
    try note.Destroy()
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

; Hidden session at login: the launcher sees CLAUDE_ADMIN_AUTOSTART and resumes or opens idle (no auto maintenance)
AutoStart() {
    ignore := RehearsalPids()
    for hwnd in Sessions() {
        try pid := WinGetPID(hwnd)
        catch
            continue   ; closed meanwhile
        if !ignore.Has(pid)
            return
    }
    EnvSet "CLAUDE_ADMIN_AUTOSTART", "1"
    try Run 'powershell.exe -NoLogo -ExecutionPolicy Bypass -File "' CL '\claude-admin-launch.ps1"', "C:\WINDOWS\system32", "Hide"
    EnvSet "CLAUDE_ADMIN_AUTOSTART"
}

TrayClick(wParam, lParam, *) {
    if (lParam != 0x202)  ; left button up
        return
    if !AI
        return (ShowStatus(), 1)
    wins := Sessions()
    if !wins.Length
        Run LNK
    else if AnyVisible(wins)
        HideAll()
    else
        ShowAll()
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

AnyVisible(wins) {
    for hwnd in wins
        try if DllCall("IsWindowVisible", "ptr", hwnd) && WinGetMinMax(hwnd) != -1
            return true
    return false
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
        tip .= "`nHidden maintenance running (right-click > Watch live)"
    A_IconTip := tip
}

MaintRunning() {
    f := CL "\maint-claude-running"
    boot := DateAdd(A_Now, -(A_TickCount // 1000), "Seconds")   ; a marker left from before a shutdown is stale
    return FileExist(f) && DateDiff(A_Now, FileGetTime(f), "Minutes") < 60 && DateDiff(FileGetTime(f), boot, "Seconds") > 0
}

OpenFile(f, emptyMsg) {
    if FileExist(f)
        Run 'notepad.exe "' f '"'
    else
        ShowNote(emptyMsg, false, 6)
}

RunMaint() {
    if AI && MaintRunning()
        return ShowNote("Hidden maintenance is already running.`nRight-click the tray icon > Watch maintenance live to follow it.", false, 8)
    Run 'conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' CL '\claude-bg-maint.ps1" -Force -Unattended', , "Hide"
    ShowNote("Maintenance started in the background.`n" (AI ? "Right-click the tray icon > Watch maintenance live to follow it." : "The result shows in Status and the last maintenance report."), false, 8)
}
