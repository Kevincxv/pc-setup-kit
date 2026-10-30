using System;
using System.Runtime.InteropServices;
using System.Text;

namespace Messiah
{
    // Windows functions the app needs (the same ones dashboard.ps1 declared as KitApp.N, plus game-check.ps1's)
    static class Native
    {
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);
        [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern uint RegisterWindowMessage(string s);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
        [StructLayout(LayoutKind.Sequential)] public struct MARGINS { public int L, R, T, B; }
        [DllImport("dwmapi.dll")] public static extern int DwmExtendFrameIntoClientArea(IntPtr h, ref MARGINS m);

        // game-check.ps1's signals: Windows' "fullscreen app" state and a foreground window covering its monitor
        [DllImport("shell32.dll")] public static extern int SHQueryUserNotificationState(out int state);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr h, uint f);
        [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr m, ref MONITORINFO mi);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
        public struct RECT { public int Left, Top, Right, Bottom; }
        public struct MONITORINFO { public int cbSize; public RECT rcMonitor, rcWork; public uint dwFlags; }
        public delegate bool EnumProc(IntPtr h, IntPtr l);
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int i);
        [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr h, int i, int v);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr h, int a, out int v, int s);

        // a program's path without opening its modules (Process.MainModule reads every loaded DLL - slow, and refused for
        // protected processes); null when it can't be read
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageName(IntPtr h, int flags, StringBuilder s, ref int size);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
        public static string ImagePath(int pid)
        {
            var h = OpenProcess(0x1000, false, pid); if (h == IntPtr.Zero) return null;   // PROCESS_QUERY_LIMITED_INFORMATION
            try { var sb = new StringBuilder(1024); int n = sb.Capacity; return QueryFullProcessImageName(h, 0, sb, ref n) ? sb.ToString() : null; }
            finally { CloseHandle(h); }
        }
        // the tray's: admin commands from a window without admin rights, Ctrl+Alt+M, time since the last keyboard or mouse input
        [DllImport("user32.dll")] public static extern bool ChangeWindowMessageFilterEx(IntPtr h, uint msg, uint action, IntPtr info);
        [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h, int id, uint mods, uint vk);
        [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h, int id);
        [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize, dwTime; }
        [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO i);
        public static long IdleMs() { var i = new LASTINPUTINFO { cbSize = 8 }; return GetLastInputInfo(ref i) ? (uint)Environment.TickCount - i.dwTime : 0; }
        // a shortcut's arguments (Windows Script Host - part of Windows); "" when it can't be read
        public static string ShortcutArgs(string lnk)
        {
            try { dynamic sh = Activator.CreateInstance(Type.GetTypeFromProgID("WScript.Shell")); return (string)sh.CreateShortcut(lnk).Arguments ?? ""; } catch { return ""; }
        }
        // a window covering its whole monitor
        public static bool Covers(IntPtr h)
        {
            GetWindowRect(h, out var r); var mi = new MONITORINFO { cbSize = 40 }; GetMonitorInfo(MonitorFromWindow(h, 2), ref mi);
            return r.Left <= mi.rcMonitor.Left && r.Top <= mi.rcMonitor.Top && r.Right >= mi.rcMonitor.Right && r.Bottom >= mi.rcMonitor.Bottom;
        }
        // game-check.ps1's GameCheck.Cover.Behind: the window that really covers a monitor behind the one in front - visible,
        // not cloaked, not click-through or no-activate (overlays), not the desktop; its program's name, or ""
        public static string Behind(IntPtr front, string[] skip)
        {
            string found = "";
            EnumWindows((h, l) =>
            {
                if (h == front || !IsWindowVisible(h) || IsIconic(h)) return true;
                int ex = GetWindowLong(h, -20); if ((ex & 0x20) != 0 || (ex & 0x08000000) != 0) return true;
                DwmGetWindowAttribute(h, 14, out var cl, 4); if (cl != 0) return true;
                var c = new StringBuilder(64); GetClassName(h, c, 64); var cs = c.ToString();
                if (cs == "Progman" || cs == "WorkerW" || cs == "Shell_TrayWnd" || cs == "Shell_SecondaryTrayWnd" || !Covers(h)) return true;
                GetWindowThreadProcessId(h, out var pid); string n;
                try { using (var p = System.Diagnostics.Process.GetProcessById((int)pid)) n = p.ProcessName; } catch { return true; }
                if (Array.IndexOf(skip, n) >= 0) return true;
                found = n; return false;
            }, IntPtr.Zero);
            return found;
        }
        // the main screen's refresh rate now (Performance's game verdicts: a game at its cap just under it is smooth, not capped)
        [DllImport("user32.dll")] static extern IntPtr GetDC(IntPtr h);
        [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr h, IntPtr dc);
        [DllImport("gdi32.dll")] static extern int GetDeviceCaps(IntPtr dc, int i);
        // (tests: PCKIT_SCREEN_HZ pins it - a verdict read 'Smooth' on GitHub's 60 Hz runner and 'paced by' at 240 Hz, 10/30)
        public static int ScreenHz() { if (Kit.InTests && int.TryParse(Environment.GetEnvironmentVariable("PCKIT_SCREEN_HZ"), out var t)) return t; try { var dc = GetDC(IntPtr.Zero); try { var hz = GetDeviceCaps(dc, 116); return hz > 1 ? hz : 0; } finally { ReleaseDC(IntPtr.Zero, dc); } } catch { return 0; } }
    }
}
