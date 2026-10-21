using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;

namespace Messiah
{
    // Files dropped from Explorer onto the window while it has admin rights (the tray starts it so): Windows refuses the
    // usual drag and drop (OLE) from a program without them to one with them, and Explorer has none. The older way - the
    // window accepts dropped files (WM_DROPFILES) - can be let through, so the window takes files that way: they go to the
    // chat (opened for them), as if dropped on it. Without admin rights the usual drag and drop works (InitChat).
    public partial class MainWindow
    {
        [DllImport("shell32.dll")] static extern void DragAcceptFiles(IntPtr h, bool accept);
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] static extern uint DragQueryFile(IntPtr drop, uint i, StringBuilder f, int n);
        [DllImport("shell32.dll")] static extern void DragFinish(IntPtr drop);
        [DllImport("ole32.dll")] static extern int RevokeDragDrop(IntPtr h);
        const int WM_DROPFILES = 0x0233;
        public static bool Elevated { get { try { return new WindowsPrincipal(WindowsIdentity.GetCurrent()).IsInRole(WindowsBuiltInRole.Administrator); } catch { return false; } } }

        void InitDrop()
        {
            SourceInitialized += (s, e) =>
            {
                if (!Elevated) return;
                var h = new WindowInteropHelper(this).Handle;
                foreach (var m in new uint[] { WM_DROPFILES, 0x004A, 0x0049 }) Native.ChangeWindowMessageFilterEx(h, m, 1, IntPtr.Zero);   // (WM_COPYDATA, WM_COPYGLOBALDATA carry the list)
                HwndSource.FromHwnd(h).AddHook(DropHook);
                // WPF's own drop target would be asked first - and refused: taken off once WPF has put it on
                Dispatcher.BeginInvoke(new Action(() => { RevokeDragDrop(h); DragAcceptFiles(h, true); }), DispatcherPriority.Loaded);
            };
        }
        IntPtr DropHook(IntPtr hwnd, int msg, IntPtr wp, IntPtr lp, ref bool handled)
        {
            if (msg != WM_DROPFILES) return IntPtr.Zero;
            handled = true;
            var files = DroppedFiles(wp);
            Dispatcher.BeginInvoke(new Action(() => Dropped(files)));
            return IntPtr.Zero;
        }
        static List<string> DroppedFiles(IntPtr drop)
        {
            var l = new List<string>();
            try
            {
                uint n = DragQueryFile(drop, 0xFFFFFFFF, null, 0);
                for (uint i = 0; i < n; i++) { var sb = new StringBuilder(32768); if (DragQueryFile(drop, i, sb, sb.Capacity) > 0) l.Add(sb.ToString()); }
            }
            finally { DragFinish(drop); }
            return l;
        }
        // --test: a real drop package (DROPFILES, as Windows hands it over) for these files, read back as a drop would be
        [DllImport("kernel32.dll")] static extern IntPtr GlobalAlloc(uint flags, UIntPtr size);
        [DllImport("kernel32.dll")] static extern IntPtr GlobalLock(IntPtr h);
        [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr h);
        internal static List<string> TestDrop(string[] files)
        {
            var list = Encoding.Unicode.GetBytes(string.Join("\0", files) + "\0\0");
            var h = GlobalAlloc(0x0042, (UIntPtr)(20 + list.Length)); var p = GlobalLock(h);   // GMEM_MOVEABLE | GMEM_ZEROINIT
            Marshal.WriteInt32(p, 0, 20); Marshal.WriteInt32(p, 16, 1);   // pFiles (the list after the 20-byte header), fWide
            Marshal.Copy(list, 0, p + 20, list.Length); GlobalUnlock(h);
            return DroppedFiles(h);
        }
        // (the files, wherever they were dropped: to the chat - opened for them; without the AI assistant there's no chat)
        internal void Dropped(List<string> files)
        {
            if (files.Count == 0) return;
            if (snap != null && !snap.Ai) { Say("Files can be dropped on the chat with Claude - switch on the AI assistant in Settings."); return; }
            if (ChatPanel.Visibility != Visibility.Visible) ShowChat(true);
            AddAttach(files);
        }
    }
}
