using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using Messiah.Chat;
using WF = System.Windows.Forms;

namespace Messiah.Tray
{
    // The tray, inside the app (10/21 - before: an AutoHotkey script, Messiah Tray.ahk). The app starts with Windows from
    // the "Messiah Tray" task (--tray, with admin rights) and stays in the hidden tray (the ^ next to the clock): the icon
    // and its menu, Ctrl+Alt+M, what needs admin rights (the window's buttons), alerts, the Claude sessions, a kit USB
    // plugged in, the in-game measurements and the weekly live test. Everything that can go wrong is logged
    // (tray-errors.log), never shown as an error.
    class TrayHost
    {
        readonly MainWindow w; WF.NotifyIcon icon; HwndSource src; bool ai;
        static readonly uint AppCmd = Native.RegisterWindowMessage("PCSetupKitAppCommand");
        const int HotkeyId = 0x4D53;
        readonly List<DispatcherTimer> timers = new List<DispatcherTimer>();
        readonly Dictionary<int, bool> known = new Dictionary<int, bool>();   // pid -> a Messiah session's console?
        readonly Dictionary<string, bool> busy = new Dictionary<string, bool>(); string pending, pendingTab;

        public TrayHost(MainWindow w) { this.w = w; }

        public void Start()
        {
            ai = Kit.AiOn();
            Notes.Register();
            // the window's handle: the admin commands, Ctrl+Alt+M, drives plugged in
            var h = new WindowInteropHelper(w).EnsureHandle(); src = HwndSource.FromHwnd(h); src.AddHook(Hook);
            Native.ChangeWindowMessageFilterEx(h, AppCmd, 1, IntPtr.Zero);   // (the window started without admin rights may ask too)
            try { File.WriteAllText(Kit.P("tray-hwnd.txt"), ((long)h).ToString()); } catch { }
            if (!Native.RegisterHotKey(h, HotkeyId, 0x0002 | 0x0001 | 0x4000, 0x4D)) TrayLogic.Error("Ctrl+Alt+M is taken by another program");   // Ctrl+Alt+M, no repeat

            icon = new WF.NotifyIcon { Icon = LoadIcon(), Visible = true };
            SetTip(TrayLogic.Name);
            icon.MouseClick += (s, e) => { if (e.Button == WF.MouseButtons.Left) Safe(() => w.ShowApp()); };
            icon.ContextMenuStrip = Menu();

            Every(5, Tip); Tip();
            After(8, AtLogin);
            Every(30, Notify);
            Every(300, GamePerf);
            if (ai)
            {
                Every(0.5, Watch); After(3, () => AutoStart(false)); Every(300, SessionCheck); Every(900, RefreshSession);
                Every(3, ChatDone); Every(600, LiveTest);
            }
        }
        public void Stop() { foreach (var t in timers) t.Stop(); try { icon.Visible = false; icon.Dispose(); } catch { } try { Native.UnregisterHotKey(src.Handle, HotkeyId); } catch { } }

        System.Drawing.Icon LoadIcon()
        {
            var f = Path.Combine(Kit.TrayDir, "app.ico");
            try { if (File.Exists(f)) return new System.Drawing.Icon(f, WF.SystemInformation.SmallIconSize); } catch { }
            return System.Drawing.Icon.ExtractAssociatedIcon(Process.GetCurrentProcess().MainModule.FileName);
        }
        // (the tooltip may be two lines and longer than Windows Forms' 63 characters: up to 127, as Windows allows)
        void SetTip(string t)
        {
            if (t.Length > 127) t = t.Substring(0, 127);
            try
            {
                var f = typeof(WF.NotifyIcon).GetField("text", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance); f.SetValue(icon, t);
                if (icon.Visible) typeof(WF.NotifyIcon).GetMethod("UpdateIcon", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance).Invoke(icon, new object[] { true });
            }
            catch { icon.Text = t.Length > 63 ? t.Substring(0, 63) : t; }
        }

        WF.ContextMenuStrip Menu()
        {
            var m = new WF.ContextMenuStrip();
            var open = new WF.ToolStripMenuItem("Open " + TrayLogic.Name, null, (s, e) => Safe(() => w.ShowApp())) { Font = new System.Drawing.Font(WF.Control.DefaultFont, System.Drawing.FontStyle.Bold) };
            m.Items.Add(open); m.Items.Add(new WF.ToolStripSeparator());
            if (ai)
            {
                m.Items.Add("New session", null, (s, e) => Safe(() => Run(SessionShortcut(), "")));
                m.Items.Add("Show sessions", null, (s, e) => Safe(ShowAll));
                m.Items.Add("Hide sessions", null, (s, e) => Safe(HideAll));
                m.Items.Add(new WF.ToolStripSeparator());
            }
            m.Items.Add("Run maintenance now", null, (s, e) => Safe(() => RunMaint(false)));
            var pause = new WF.ToolStripMenuItem("Pause maintenance");
            pause.DropDownItems.Add("For 2 hours", null, (s, e) => Safe(() => Notes.Show(TrayLogic.SetPause(2), "-", 8)));
            pause.DropDownItems.Add("Until tomorrow", null, (s, e) => Safe(() => Notes.Show(TrayLogic.SetPause(24), "-", 8)));
            pause.DropDownItems.Add("Resume now", null, (s, e) => Safe(() => Notes.Show(TrayLogic.SetPause(0), "-", 8)));
            m.Items.Add(pause);
            m.Items.Add("Cancel restart", null, (s, e) => Safe(() => Hidden(Path.Combine(Environment.SystemDirectory, "shutdown.exe"), "/a")));   // a night restart's 5-minute countdown (restart-night.ps1)
            m.Items.Add(new WF.ToolStripSeparator());
            m.Items.Add("Remove tray icon", null, (s, e) => icon.Visible = false);   // (until the next login; the app keeps working)
            return m;
        }

        // --- the window's messages: what needs admin rights (Actions.SendTray), Ctrl+Alt+M, a drive plugged in
        IntPtr Hook(IntPtr hwnd, int msg, IntPtr wp, IntPtr lp, ref bool handled)
        {
            if (msg == AppCmd) { var n = wp.ToInt32(); w.Dispatcher.BeginInvoke(new Action(() => Safe(() => Command(n)))); handled = true; return (IntPtr)1; }
            if (msg == 0x0312 && wp.ToInt32() == HotkeyId) { Safe(() => w.ShowApp()); handled = true; }   // WM_HOTKEY
            if (msg == 0x0219 && wp.ToInt32() == 0x8000) After(15, UsbBackup);   // WM_DEVICECHANGE, a device arrived: once Windows has mounted it
            return IntPtr.Zero;
        }
        // the scripts behind the app's admin commands: "window" (a console the owner watches), "hidden", "plain" (its own
        // window, no -NoExit) - --tray-test commands prints it
        public static readonly Dictionary<Actions.Cmd, (string How, string Script, string Args)> Scripts = new Dictionary<Actions.Cmd, (string, string, string)>
        {
            [Actions.Cmd.Optimize] = ("window", "optimize.ps1", ""), [Actions.Cmd.WatchLive] = ("window", "maint-watch.ps1", ""),
            [Actions.Cmd.ApplyTweaks] = ("hidden", "after-update.ps1", "-Now"),   // the owner's tweak choices, now (even while paused)
            [Actions.Cmd.Repair] = ("window", "kit-update.ps1", "-Reinstall"), [Actions.Cmd.Rollback] = ("window", "kit-update.ps1", "-Rollback"),
            [Actions.Cmd.AiOn] = ("plain", "ai-toggle.ps1", "-On"),   // installs Claude Code, then its sign-in
            [Actions.Cmd.AiOff] = ("hidden", "ai-toggle.ps1", "-Off"), [Actions.Cmd.GpuRollback] = ("window", "gpu-rollback.ps1", ""),
            [Actions.Cmd.ChatHost] = ("hidden", "chat-host.ps1", ""),   // the app's chat with Claude (with admin rights, no window)
        };
        void Command(int n)
        {
            var c = (Actions.Cmd)n;
            if (c == Actions.Cmd.NewSession) Run(SessionShortcut(), "");
            else if (c == Actions.Cmd.ShowSessions) ShowAll();
            else if (c == Actions.Cmd.HideSessions) HideAll();
            else if (c == Actions.Cmd.RunMaint) RunMaint(true);
            else if (Scripts.TryGetValue(c, out var s))
            {
                if (s.How == "window") Window(s.Script, s.Args);
                else if (s.How == "hidden") Ps(s.Script, s.Args);
                else Run("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -File \"{Kit.P(s.Script)}\" {s.Args}");
            }
        }
        // --tray-test menu: the menu as the owner sees it (with or without the AI assistant)
        internal static string MenuText(bool ai)
        {
            var h = new TrayHost(null) { ai = ai }; var sb = new StringBuilder();
            void Add(WF.ToolStripItemCollection items, string pre) { foreach (WF.ToolStripItem i in items) { sb.Append(pre).Append(i is WF.ToolStripSeparator ? "-" : i.Text).Append('\n'); if (i is WF.ToolStripMenuItem mi && mi.DropDownItems.Count > 0) Add(mi.DropDownItems, pre + "  "); } }
            Add(h.Menu().Items, ""); return sb.ToString();
        }

        // --- starting things (with the tray's admin rights)
        static void Run(string exe, string args, string dir = null) { try { Process.Start(new ProcessStartInfo(exe, args) { UseShellExecute = true, WorkingDirectory = dir ?? Kit.Cl }); } catch (Exception e) { TrayLogic.Error($"run {exe}: {e.Message}"); } }
        static void Hidden(string exe, string args) { try { Process.Start(new ProcessStartInfo(exe, args) { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = Kit.Cl }); } catch (Exception e) { TrayLogic.Error($"run {exe}: {e.Message}"); } }
        static void Ps(string script, string args) { if (File.Exists(Kit.P(script))) Hidden("powershell.exe", $"-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"{Kit.P(script)}\" {args}"); }
        static void Window(string script, string args) => Run("powershell.exe", $"-NoExit -NoProfile -ExecutionPolicy Bypass -File \"{Kit.P(script)}\" {args}");
        void Safe(Action a) { try { a(); } catch (Exception e) { TrayLogic.Error(e.Message + " " + e.StackTrace?.Split('\n').FirstOrDefault()?.Trim()); } }
        void Every(double seconds, Action a) { var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(seconds) }; t.Tick += (s, e) => Safe(a); t.Start(); timers.Add(t); }
        void After(double seconds, Action a) { var t = new DispatcherTimer { Interval = TimeSpan.FromSeconds(seconds) }; t.Tick += (s, e) => { t.Stop(); timers.Remove(t); Safe(a); }; t.Start(); timers.Add(t); }

        void Tip() => SetTip(TrayLogic.Tip(ai));
        // the welcome page once after a new install; the window at login only with "Open at login" on
        void AtLogin()
        {
            var p = TrayLogic.AtLogin(IsFullscreen());
            if (p == "wait") { After(60, AtLogin); return; }
            if (p == null) return;
            if (p != "") Notes.Open("page=" + p); else w.ShowApp();
        }
        void Notify()
        {
            var t = TrayLogic.Notify(IsFullscreen());
            if (t != null && TrayLogic.Alert(t)) Notes.Show(t, t.StartsWith("Needs you") ? "page=Home" : "");
        }
        void RunMaint(bool quiet)
        {
            if (ai && TrayLogic.MaintRunning()) { if (!quiet) Notes.Show($"Hidden maintenance is already running.\nOpen {TrayLogic.Name} > Activity > Watch live to follow it.", "-", 8); return; }
            Hidden(Path.Combine(Environment.SystemDirectory, "conhost.exe"), $"--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"{Kit.P("claude-bg-maint.ps1")}\" -Force -Unattended -Now");
            if (!quiet) Notes.Show($"Maintenance started in the background.\nThe result shows in {TrayLogic.Name} (click this).", "page=Activity/Checks", 8);
        }
        // a kit USB: a fresh settings backup on it (once a day); the owner's files when it's their backup drive
        void UsbBackup() { if (Kit.InTests) return; Ps("settings-backup.ps1", "-ToUsb"); Ps("files-backup.ps1", "-Arrived"); }
        // every 5 minutes while something is fullscreen: a minute of the game's frame rate (game-perf.ps1 decides)
        void GamePerf() { if (!Kit.InTests && IsFullscreen()) Ps("game-perf.ps1", ""); }
        // the weekly live self-test: only after 30+ minutes without keyboard or mouse (live-test.ps1 checks the rest)
        void LiveTest()
        {
            var f = Kit.P("live-test.json");
            if (Kit.InTests || Native.IdleMs() < 1800000 || IsFullscreen() || !File.Exists(Kit.P("live-test.ps1"))) return;
            if (File.Exists(f) && (DateTime.Now - File.GetLastWriteTime(f)).TotalDays < 7) return;
            Ps("live-test.ps1", "");
        }
        void RefreshSession() => Ps("refresh-session.ps1", "");   // the hidden session onto a new Claude Code, when it can't disturb

        // a game or video covering its whole monitor: nothing pops up
        public static bool IsFullscreen()
        {
            var fg = Native.GetForegroundWindow(); if (fg == IntPtr.Zero) return false;
            var c = new StringBuilder(64); Native.GetClassName(fg, c, 64);
            if (System.Text.RegularExpressions.Regex.IsMatch(c.ToString(), "^(Progman|WorkerW|Shell_TrayWnd|Shell_SecondaryTrayWnd)$")) return false;
            return Native.Covers(fg);
        }

        // --- "Claude finished": a chat that was working is done while the owner isn't looking at the app - shown even
        // with corner alerts off (they asked for it); held while a game is fullscreen; a click opens that chat
        void ChatDone()
        {
            foreach (var d in ChatData.Dirs())
            {
                var st = ChatData.State(d);
                if (st == null) { busy.Remove(d); continue; }   // (no host: nothing to say)
                var now = Json.B(st, "busy"); var was = busy.TryGetValue(d, out var b) && b; busy[d] = now;
                if (was && !now && !AppInFront()) { pending = TrayLogic.LastReply(d); pendingTab = d == ChatData.Main ? "" : Path.GetFileName(d); }
            }
            if (pending == null || IsFullscreen()) return;
            var txt = pending; pending = null;
            if (AppInFront()) return;
            Notes.Show("Claude finished" + (txt == "-" ? "." : ": " + txt), "chat=" + pendingTab, 15);
        }
        bool AppInFront() => w.IsVisible && w.IsActive;

        // --- the Messiah sessions (Claude Code with admin rights, in console windows): minimized = to the tray, one always
        // there (hidden), shown / hidden from the menu. Any window can close between listing it and looking at it.
        string SessionShortcut()
        {
            var sm = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), @"Microsoft\Windows\Start Menu\Programs");
            foreach (var f in new[] { Kit.P("Messiah Session.lnk"), Path.Combine(sm, "Messiah.lnk"), Path.Combine(sm, "Claude (Admin).lnk") })
                if (File.Exists(f) && Native.ShortcutArgs(f).Contains("claude-admin-launch.ps1")) return f;
            return Kit.P("Messiah Session.lnk");
        }
        List<IntPtr> Sessions()
        {
            var wins = new List<IntPtr>();
            Native.EnumWindows((h, l) =>
            {
                var c = new StringBuilder(64); Native.GetClassName(h, c, 64); if (c.ToString() != "ConsoleWindowClass") return true;
                Native.GetWindowThreadProcessId(h, out var pid);
                if (!known.TryGetValue((int)pid, out var isSession))
                {
                    var cmd = "";
                    try { using (var s = new ManagementObjectSearcher($"SELECT CommandLine FROM Win32_Process WHERE ProcessId={pid}")) foreach (ManagementObject o in s.Get()) cmd = (o["CommandLine"] ?? "").ToString(); } catch { }
                    known[(int)pid] = isSession = cmd.Contains("claude-admin-launch.ps1");
                }
                if (isSession) wins.Add(h);
                return true;
            }, IntPtr.Zero);
            return wins;
        }
        void ShowAll() { foreach (var h in Sessions()) { Native.ShowWindow(h, 5); if (Native.IsIconic(h)) Native.ShowWindow(h, 9); Native.SetForegroundWindow(h); } }
        void HideAll() { foreach (var h in Sessions()) Native.ShowWindow(h, 0); }
        void Watch()
        {
            foreach (var pid in known.Keys.ToList()) if (!Alive(pid)) known.Remove(pid);
            foreach (var h in Sessions()) if (Native.IsWindowVisible(h) && Native.IsIconic(h)) Native.ShowWindow(h, 0);   // minimized = to the tray
        }
        static bool Alive(int pid) { try { using (var p = Process.GetProcessById(pid)) return !p.HasExited; } catch { return false; } }
        // a hidden session at login (the launcher sees CLAUDE_ADMIN_AUTOSTART: resumes, or opens idle); revive: the 5-minute
        // check - a fresh idle one, never a resumed one
        bool AutoStart(bool revive)
        {
            var ignore = TrayLogic.RehearsalPids();
            foreach (var h in Sessions()) { Native.GetWindowThreadProcessId(h, out var pid); if (!ignore.Contains((int)pid)) return false; }
            // (its console starts hidden - the shell honors that - and inherits the flag, set for the moment it starts)
            Environment.SetEnvironmentVariable("CLAUDE_ADMIN_AUTOSTART", revive ? "2" : "1");
            try { Process.Start(new ProcessStartInfo("powershell.exe", $"-NoLogo -ExecutionPolicy Bypass -File \"{Kit.P("claude-admin-launch.ps1")}\"") { UseShellExecute = true, WorkingDirectory = Environment.SystemDirectory, WindowStyle = ProcessWindowStyle.Hidden }); }
            catch (Exception e) { TrayLogic.Error("session: " + e.Message); return false; }
            finally { Environment.SetEnvironmentVariable("CLAUDE_ADMIN_AUTOSTART", null); }
            return true;
        }
        // a Messiah session is always there (the owner's rule): whatever ended the last one, a hidden idle one is back within
        // 5 minutes - not during a login rehearsal (it controls the sessions itself)
        void SessionCheck()
        {
            var f = Kit.P("rehearsal.txt");
            if (Kit.InTests || (File.Exists(f) && (DateTime.Now - File.GetLastWriteTime(f)).TotalMinutes < 10)) return;
            if (AutoStart(true)) try { File.AppendAllText(Kit.P("session-refresh.log"), $"{DateTime.Now:M/d/yyyy h:mm tt}  No Messiah session was running - opened a hidden one\r\n"); } catch { }
        }
    }
}
