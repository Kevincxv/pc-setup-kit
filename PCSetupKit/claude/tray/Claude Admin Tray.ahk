#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent
; The Messiah app's tray side: it starts at login in the hidden tray (the ^ area) and runs the PC's maintenance on its own; small alerts when something needs the owner, and the
; parts of the app window (MessiahApp.exe) that need admin rights. Clicking the icon opens the app window.
; With the AI assistant switched on (the app's Settings, or setup.ps1 -WithClaude) it also holds the Messiah sessions (Claude Code with
; admin rights): minimizing one sends it to the tray, and at login it opens one hidden (continuing a conversation a
; restart cut off). Runs elevated (scheduled task) so it can hide admin windows and start maintenance without a prompt.

CL := EnvGet("USERPROFILE") "\.claude"
LNK := SessionShortcut()
AI := AiEnabled()
NAME := "Messiah"   ; one app; the AI assistant (Claude) is a switch in its Settings
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
; Pause: the background maintenance, update check and update guard wait (kit-options.txt "pause-until=")
pauseMenu := Menu()
pauseMenu.Add("For 2 hours", (*) => SetPause(2))
pauseMenu.Add("Until tomorrow", (*) => SetPause(24))
pauseMenu.Add("Resume now", (*) => SetPause(0))
tray.Add("Pause maintenance", pauseMenu)
tray.Add("Cancel restart", (*) => Run(A_WinDir "\System32\shutdown.exe /a", , "Hide"))   ; stops a night restart's 5-minute countdown (restart-night.ps1)
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
SetTimer PreloadApp, -60000   ; the app window, hidden - opening it is instant (PreloadApp)

known := Map()  ; pid -> true if it's a Messiah launcher window
note := 0       ; the corner note currently shown
SetTimer Notify, 30000
SetTimer GamePerf, 300000   ; in-game frame rate and temperatures (game-perf.ps1)
OnMessage(0x219, DeviceChange)   ; WM_DEVICECHANGE: a kit USB plugged in gets a fresh settings backup
try Hotkey("^!m", (*) => ShowApp())   ; Ctrl+Alt+M opens the app from anywhere
if AI {
    SetTimer Watch, 500
    SetTimer AutoStart, -3000
    SetTimer SessionCheck, 300000
    SetTimer RefreshSession, 900000
    SetTimer ChatDone, 3000
    SetTimer LiveTest, 600000
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
        6, (*) => Run('powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "' CL '\maint-watch.ps1"'),
        7, (*) => Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' CL '\after-update.ps1" -Now', , "Hide"),   ; the owner's tweak choices, now (even while paused)
        8, (*) => Run('powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "' CL '\kit-update.ps1" -Reinstall'),               ; repair: the current release again
        9, (*) => Run('powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "' CL '\kit-update.ps1" -Rollback'),                ; undo the last update
        10, (*) => Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' CL '\ai-toggle.ps1" -On'),                               ; the AI assistant on: installs Claude Code, then its sign-in
        11, (*) => Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' CL '\ai-toggle.ps1" -Off', , "Hide"),
        12, (*) => Run('powershell.exe -NoExit -NoProfile -ExecutionPolicy Bypass -File "' CL '\gpu-rollback.ps1"'),
        13, (*) => Run('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' CL '\chat-host.ps1"', , "Hide"))   ; the app's chat with Claude (elevated, no window)                       ; back to the graphics driver before this one
    if work.Has(wParam)
        SetTimer work[wParam], -10
    return 1
}

; The app window (app\MessiahApp.exe; without it - a broken install - the text status.ps1). One window - starting it
; again brings it to the front.
AppExe() => FileExist(CL "\app\MessiahApp.exe") ? CL "\app\MessiahApp.exe" : ""
ShowApp(page := "") {
    ; already running (closing only hides it): told to show itself directly - instant, no new PowerShell
    if h := DllCall("OpenEventW", "UInt", 0x0002, "Int", 0, "Str", "Local\MessiahAppShow", "Ptr") {
        if page != ""
            try FileOpen(CL "\app-request.txt", "w", "UTF-8-RAW").Write("page=" page)
        DllCall("AllowSetForegroundWindow", "Int", -1), DllCall("SetEvent", "Ptr", h), DllCall("CloseHandle", "Ptr", h)
        return
    }
    if AppExe() != ""
        Run '"' AppExe() '" --live' (page != "" ? " --page " page : "")
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
    ; right after a new install (setup.ps1: "welcome=pending"): the welcome page, once (a game first: later)
    if RegExMatch(opts, "im)^\s*welcome\s*=\s*pending\s*$") && IniRead(CL "\tray-notified.ini", "shown", "welcome", "") = "" {
        if IsFullscreen()
            return SetTimer(StatusAtLogin, -60000)
        IniWrite 1, CL "\tray-notified.ini", "shown", "welcome"
        return ShowApp("Welcome")
    }
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

; The app window, started hidden a minute after login (--background): opening it is instant from then on, the first
; time too - closing it only hides it. Not under a fullscreen game (tried again a minute later), not in tests.
PreloadApp() {
    if EnvGet("PCKIT_IN_TESTS") != "" || AppExe() = ""
        return
    if IsFullscreen()
        return SetTimer(PreloadApp, -60000)
    Run '"' AppExe() '" --live --background'
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

; --- Alerts. Windows notifications are off on this PC (debloat), so the tray has its own small note in the corner (Alert:
; only when the owner turns corner alerts on):
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
                return Alert("Needs you (" items.Length "): " first (items.Length > 1 ? "`n+ " items.Length - 1 " more" : ""))
        }
    }
    f := CL "\tray-news.txt"   ; a short message from the maintenance: what's new after a kit update, the weekly summary
    if FileExist(f) {
        stamp := FileGetTime(f)
        if stamp != IniRead(notified, "shown", "news", "") {
            IniWrite stamp, notified, "shown", "news"
            txt := Trim(FileRead(f, "UTF-8"), " `r`n")
            if txt != ""
                return Alert(StrLen(txt) > 330 ? SubStr(txt, 1, 327) "..." : txt)
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
            return Alert(n " update(s)/fix(es) will finish the next time you turn the PC off.`nNo need to restart now - whenever suits you.")
        }
    }
}

; The owner's rule (10/10): Messiah works in the background and never pops up by itself - what the maintenance has to
; say goes to the app (Home, Notifications) and the tray's tooltip, quietly. "Show alerts in the corner" in Settings
; (kit-options.txt "cornernotes=on") brings the corner notes back. Notes about something the owner just did still show.
Alert(text) {
    opts := ""
    try opts := FileRead(CL "\kit-options.txt")
    if RegExMatch(opts, "im)^\s*cornernotes\s*=\s*on\s*$")
        return ShowNote(text)
    LogNote(text)
}

; --- "Claude finished": a chat in the app that was working is done while the owner isn't looking at the app (its window
; isn't the one in front) - a note about something the owner asked for, so it shows even with corner alerts off. It
; waits while a game or video is fullscreen. Clicking it opens that chat (app-request.txt, read by the app).
ChatDone() {
    static busy := Map(), pending := "", pendingTab := ""
    dirs := [CL "\chat"]
    Loop Files CL "\chats\*", "D"
        dirs.Push(A_LoopFileFullPath)
    for d in dirs {
        st := ""
        try st := FileRead(d "\state.json", "UTF-8")
        if RegExMatch(st, '"busy":\s*true')
            now := true
        else if RegExMatch(st, '"busy":\s*false')
            now := false
        else {   ; no host (closed, not started yet): nothing to say
            if busy.Has(d)
                busy.Delete(d)
            continue
        }
        was := busy.Has(d) ? busy[d] : false
        busy[d] := now
        if was && !now && !AppInFront()
            pending := LastReply(d), pendingTab := (d = CL "\chat") ? "" : RegExReplace(d, ".*\\")
    }
    if pending = "" || IsFullscreen()
        return
    txt := pending, tab := pendingTab, pending := ""
    if AppInFront()   ; (back at the app meanwhile: seen it)
        return
    ShowNote("Claude finished" (txt = "-" ? "." : ": " txt), (*) => OpenChat(tab), 15)
}
; the window of the app (it keeps its handle in app-window.txt) is the one in front
AppInFront() {
    try {
        h := Trim(FileRead(CL "\app-window.txt"))
        return h != "" && WinActive("ahk_id " h) ? true : false
    }
    return false
}
; the chat's last answer, short (events.jsonl: {"t":"text","text":...}); "-" when there's none
LastReply(d) {
    try {
        txt := FileRead(d "\events.jsonl", "UTF-8")
        p := InStr(txt, '"t":"text"', , -1)
        if p && RegExMatch(txt, '"text":"((?:[^"\\]|\\.)*)"', &m, p) {
            s := m[1]
            while RegExMatch(s, "\\u([0-9a-fA-F]{4})", &u)
                s := StrReplace(s, u[0], Chr(Integer("0x" u[1])))
            s := StrReplace(StrReplace(StrReplace(StrReplace(s, "\n", " "), "\r", ""), '\"', '"'), "\\", "\")
            s := Trim(RegExReplace(RegExReplace(s, "[*``#]+", ""), "\s+", " "))
            return StrLen(s) > 140 ? SubStr(s, 1, 137) "..." : (s = "" ? "-" : s)
        }
    }
    return "-"
}
; --- The weekly live self-test (live-test.ps1): only while nobody uses the PC (30+ minutes without keyboard or mouse);
; the script checks the rest (a week since the last one, no game, no busy chat, no hidden maintenance)
LiveTest() {
    f := CL "\live-test.json"
    if EnvGet("PCKIT_IN_TESTS") != "" || A_TimeIdlePhysical < 1800000 || IsFullscreen() || !FileExist(CL "\live-test.ps1")
        return
    if FileExist(f) && DateDiff(A_Now, FileGetTime(f), "Days") < 7
        return
    try Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' CL '\live-test.ps1"', , "Hide"
}
OpenChat(tab) {
    try FileOpen(CL "\app-request.txt", "w", "UTF-8-RAW").Write("chat=" tab)
    ShowApp("Chat")
}

; The note: dark card with rounded corners (Windows 11), bottom-right, fades in, never takes focus.
; details = true: clicking opens Status (alerts); false: clicking just closes it (short messages); a function: clicking
; does that
ShowNote(text, details := true, seconds := 20) {
    global note
    LogNote(text)
    try note.Destroy()
    note := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x08000000")   ; WS_EX_NOACTIVATE: never steals focus
    note.BackColor := "202020", note.MarginX := 20, note.MarginY := 16
    act := details
    click := HasMethod(details) ? (*) => (CloseNote(), act()) : details ? NoteClick : (*) => CloseNote()
    note.SetFont("s10 bold c60CDFF", "Segoe UI"), note.SetFont(, "Segoe UI Variable Text")
    note.AddText("w300 +0x100", NAME).OnEvent("Click", click)
    note.SetFont("s10 norm c8A8A8A")
    note.AddText("x+8 yp w22 Right +0x100", Chr(0x2715)).OnEvent("Click", (*) => CloseNote())
    note.SetFont("s10 cF0F0F0")
    note.AddText("xm y+6 w330 +0x100", text).OnEvent("Click", click)
    note.SetFont("s8 c8A8A8A")
    note.AddText("xm y+10 w330 +0x100", HasMethod(details) ? "Click to open the chat" : details ? "Click for details" : "Click to close").OnEvent("Click", click)
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

; Pause maintenance for some hours (0 = resume): kit-options.txt "pause-until=<local time>", read by
; claude-bg-maint.ps1, update-check.ps1 and after-update.ps1 (paused.ps1)
SetPause(hours) {
    f := CL "\kit-options.txt", keep := ""
    try Loop Parse FileRead(f, "UTF-8"), "`n", "`r"
        if Trim(A_LoopField) != "" && !RegExMatch(A_LoopField, "^\s*pause-until\s*=")
            keep .= A_LoopField "`n"
    if hours
        keep .= "pause-until=" FormatTime(DateAdd(A_Now, hours, "Hours"), "yyyy-MM-ddTHH:mm:ss") "`n"
    try FileOpen(f, "w", "UTF-8-RAW").Write(keep)
    ShowNote(hours ? "Maintenance paused until " FormatTime(DateAdd(A_Now, hours, "Hours"), "ddd h:mm tt") ".`nTray > Pause maintenance > Resume now to start it again." : "Maintenance runs again as usual.", false, 8)
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
    if FileExist(CL "\files-backup.ps1")   ; the owner's files, when it's the drive chosen for them (files-backup.ps1)
        try Run 'powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' CL '\files-backup.ps1" -Arrived', , "Hide"
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
    Run 'conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "' CL '\claude-bg-maint.ps1" -Force -Unattended -Now', , "Hide"
    if !quiet
        ShowNote("Maintenance started in the background.`nThe result shows in " NAME " (click this).", true, 8)
}
