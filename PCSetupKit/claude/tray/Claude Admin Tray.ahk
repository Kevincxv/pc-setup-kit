#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
; Tray icon for Claude (Admin) sessions, so they don't need a taskbar pin.
; Left-click: open a session if none is running, otherwise show/hide the session windows.
; Minimizing a session window sends it to the tray. Runs elevated (scheduled task) so it can hide admin windows.
; At login it opens one session hidden in the tray (continuing a conversation a restart cut off), so Claude is always ready.

LNK := A_AppData "\Microsoft\Windows\Start Menu\Programs\Claude (Admin).lnk"
CL := EnvGet("USERPROFILE") "\.claude"
DetectHiddenWindows true

TraySetIcon EnvGet("USERPROFILE") "\.local\bin\claude.exe"
A_IconTip := "Claude (Admin)"
tray := A_TrayMenu
tray.Delete()
tray.Add("New Claude (Admin) session", (*) => Run(LNK))
tray.Add("Show sessions", (*) => ShowAll())
tray.Add("Hide sessions", (*) => HideAll())
tray.Add()
tray.Add("Status", (*) => ShowStatus())
; Hidden maintenance (runs headless at login: /maintain when needed, then /self-improve once a day)
tray.Add("Watch maintenance live", (*) => Run('powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "' CL '\maint-watch.ps1"'))
tray.Add("Maintenance to-do list", (*) => OpenFile(CL "\maint-todo.txt", "Nothing needs you right now."))
tray.Add("Last maintenance report", (*) => OpenFile(CL "\maint-report.txt", "No report yet."))
tray.Add("Self-improvement journal", (*) => OpenFile(CL "\selfimprove-journal.md", "No self-improvement runs yet."))
tray.Add("Run hidden maintenance now", (*) => RunMaint())
tray.Add()
tray.Add("Remove tray icon", (*) => ExitApp())
tray.Default := "New Claude (Admin) session"
tray.ClickCount := 1
OnMessage(0x404, TrayClick)
SetTimer Watch, 500
SetTimer TodoTip, 5000
TodoTip()

known := Map()  ; pid -> true if it's a Claude (Admin) launcher window
note := 0       ; the corner alert currently shown
SetTimer AutoStart, -3000
SetTimer Notify, 30000
SetTimer RefreshSession, 900000

; The hidden session keeps running old Claude Code after an update; refresh-session.ps1 restarts it on the new
; version when that can't disturb anything (hidden, idle, not mid-task) - same conversation, no prompt
RefreshSession() {
    try Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' CL '\refresh-session.ps1"', , "Hide"
}

ShowStatus() => Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' CL '\status.ps1"')

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

ShowNote(text) {
    global note
    try note.Destroy()
    note := Gui("+AlwaysOnTop -Caption +ToolWindow +Border +E0x08000000")   ; WS_EX_NOACTIVATE: never steals focus
    note.BackColor := "1F1F1F", note.MarginX := 14, note.MarginY := 10
    note.SetFont("s10 bold cFFFFFF", "Segoe UI")
    note.AddText("w330 +0x100", "Claude (Admin)").OnEvent("Click", NoteClick)
    note.SetFont("s10 norm cE6E6E6")
    note.AddText("w330 y+4 +0x100", text).OnEvent("Click", NoteClick)
    note.SetFont("s8 c9A9A9A")
    note.AddText("w330 y+8 +0x100", "Click for details - closes by itself").OnEvent("Click", NoteClick)
    note.Show("NoActivate Hide")
    note.GetPos(, , &w, &h)
    MonitorGetWorkArea(MonitorGetPrimary(), , , &right, &bottom)
    note.Show("NoActivate x" (right - w - 12) " y" (bottom - h - 12))
    SetTimer CloseNote, -20000
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
    for hwnd in Sessions()
        if !ignore.Has(WinGetPID(hwnd))
            return
    EnvSet "CLAUDE_ADMIN_AUTOSTART", "1"
    try Run 'powershell.exe -NoLogo -ExecutionPolicy Bypass -File "' CL '\claude-admin-launch.ps1"', "C:\WINDOWS\system32", "Hide"
    EnvSet "CLAUDE_ADMIN_AUTOSTART"
}

TrayClick(wParam, lParam, *) {
    if (lParam != 0x202)  ; left button up
        return
    wins := Sessions()
    if !wins.Length
        Run LNK
    else if AnyVisible(wins)
        HideAll()
    else
        ShowAll()
    return 1
}

Sessions() {
    global known
    wins := []
    for hwnd in WinGetList("ahk_class ConsoleWindowClass") {
        pid := WinGetPID(hwnd)
        if !known.Has(pid) {
            cmd := ""
            for p in ComObjGet("winmgmts:").ExecQuery("SELECT CommandLine FROM Win32_Process WHERE ProcessId=" pid)
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
        if DllCall("IsWindowVisible", "ptr", hwnd) && WinGetMinMax(hwnd) != -1
            return true
    return false
}

ShowAll() {
    for hwnd in Sessions() {
        WinShow hwnd
        if WinGetMinMax(hwnd) = -1
            WinRestore hwnd
        WinActivate hwnd
    }
}

HideAll() {
    for hwnd in Sessions()
        WinHide hwnd
}

Watch() {
    global known
    for pid in [known*]
        if !ProcessExist(pid)
            known.Delete(pid)
    ; Minimize = send to tray
    for hwnd in Sessions()
        if DllCall("IsWindowVisible", "ptr", hwnd) && WinGetMinMax(hwnd) = -1
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
    tip := n ? "Claude (Admin) - " n " maintenance item" (n = 1 ? "" : "s") " need you" : "Claude (Admin)"
    if MaintRunning()
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
        MsgBox emptyMsg, "Claude (Admin)", "Iconi T5"
}

RunMaint() {
    if MaintRunning()
        return MsgBox("Hidden maintenance is already running. Use 'Watch maintenance live' to follow it.", "Claude (Admin)", "Iconi T8")
    Run 'conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' CL '\claude-bg-maint.ps1" -Force -Unattended', , "Hide"
    TrayTip "Hidden maintenance started. Right-click the tray icon > Watch maintenance live to follow it.", "Claude (Admin)"
}