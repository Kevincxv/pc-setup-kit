using System;
using System.IO;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Threading;
using Messiah.Chat;

namespace Messiah
{
    // Live: the window follows the files it shows instead of reading everything again every few seconds - a check that
    // finished, the to-do list, an option, a chat's answer arriving: on screen within a moment. Bursts (a check writes a
    // dozen files) are drawn once. Hidden, nothing is watched; a slow timer still covers what changes with the clock
    // ("today 8:44 AM", a pause running out).
    public partial class MainWindow
    {
        FileSystemWatcher watchCl, watchChat, watchChats;
        readonly DispatcherTimer settle = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(250) };
        // a chat's answer streams in: read as it comes (only what's new is read), not held to the once-a-second pace
        readonly DispatcherTimer chatSettle = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(60) };
        bool dataDirty, watching; DateTime lastLive = DateTime.MinValue;
        // the app's own files and logs nobody shows: no redraw for them (app-last.txt is written by the app itself)
        static readonly Regex Ignore = new Regex(@"^(app-(last|window|request|errors)|tray-(hwnd|errors)|.*\.(tmp|log|lock)$|~)", RegexOptions.IgnoreCase);

        void InitLive()
        {
            chatSettle.Tick += (s, e) =>
            {
                chatSettle.Stop();
                try { if (ChatPanel.Visibility == Visibility.Visible) UpdateChat(); UpdateNow(); } catch (Exception ex) { App.Log("live chat: " + ex.Message); }
            };
            settle.Tick += (s, e) =>
            {
                // at most one redraw a second while files keep changing (a check running)
                if ((DateTime.Now - lastLive).TotalMilliseconds < 1000) return;
                settle.Stop(); lastLive = DateTime.Now;
                try
                {
                    if (dataDirty) { dataDirty = false; Refresh(false); UpdateNow(); }
                }
                catch (Exception ex) { App.Log("live: " + ex.Message); }
            };
        }
        FileSystemWatcher Watch(string dir, bool sub, bool chat)
        {
            if (!Directory.Exists(dir)) return null;
            try
            {
                var w = new FileSystemWatcher(dir) { IncludeSubdirectories = sub, NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.Size | NotifyFilters.DirectoryName, InternalBufferSize = 32768 };
                FileSystemEventHandler h = (s, e) => Changed(e.Name, chat);
                w.Changed += h; w.Created += h; w.Deleted += h; w.Renamed += (s, e) => Changed(e.Name, chat);
                w.Error += (s, e) => Dispatcher.BeginInvoke(new Action(() => { dataDirty = true; settle.Start(); chatSettle.Start(); }));   // (missed some: read everything)
                w.EnableRaisingEvents = true; return w;
            }
            catch (Exception ex) { App.Log("watch " + dir + ": " + ex.Message); return null; }
        }
        // (a watcher's thread)
        void Changed(string name, bool chat)
        {
            if (!watching || name == null) return;
            var leaf = Path.GetFileName(name);
            if (!chat && Ignore.IsMatch(leaf)) return;
            if (chat && !(leaf == "state.json" || leaf == "events.jsonl" || leaf == "title.txt" || leaf == "pinned.txt" || leaf == "mode.txt" || !leaf.Contains("."))) return;
            Dispatcher.BeginInvoke(new Action(() =>
            {
                if (!chat && (leaf == "chat" || leaf == "chats")) StartWatching();   // (the chat folders made just now)
                if (chat) { chatSettle.Stop(); chatSettle.Start(); return; }
                dataDirty = true; settle.Stop(); settle.Start();
            }));
        }
        // shown: watch; hidden: not (the show signal and the tray's work need no file watching)
        void StartWatching()
        {
            watching = true;
            if (watchCl == null) watchCl = Watch(Kit.Cl, false, false);
            if (watchChat == null) watchChat = Watch(ChatData.Main, false, true);
            if (watchChats == null) watchChats = Watch(Kit.P("chats"), true, true);
            foreach (var w in new[] { watchCl, watchChat, watchChats }) if (w != null) w.EnableRaisingEvents = true;
        }
        void StopWatching()
        {
            watching = false; settle.Stop(); chatSettle.Stop();
            foreach (var w in new[] { watchCl, watchChat, watchChats }) if (w != null) try { w.EnableRaisingEvents = false; } catch { }
        }
    }
}
