using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Messiah.Chat;

namespace Messiah
{
    // The chat with Claude, beside whatever page is open (dashboard.ps1's chat: the same behavior, words and keys)
    public partial class MainWindow
    {
        static SolidColorBrush Br(string k) => Theme.B[k];
        string chatDir = ChatData.Main; long chatPos; TextBlock live; string liveText = "";
        DockPanel lastUser; bool editing, sendBusy, renaming; string tabsKey, nowChat; int nowTick, fastN;
        readonly List<string> attach = new List<string>(); readonly Dictionary<string, string> lastSent = new Dictionary<string, string>();
        double chatW = 440, chatZoom = 1.0;
        readonly DispatcherTimer fast = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(1000) };   // (the NowBar's dot; answers arrive through the file watch)
        const string AttachRx = "^Attached: (.+)$";
        string AttDir => Kit.P("chat-attachments");

        void InitChat()
        {
            if (AppLast.ChatTab != "" && Regex.IsMatch(AppLast.ChatTab, @"^[\w-]+$") && Directory.Exists(Kit.P(@"chats\" + AppLast.ChatTab + @"\inbox"))) chatDir = Kit.P(@"chats\" + AppLast.ChatTab);
            chatZoom = Math.Min(1.6, Math.Max(0.8, AppLast.ChatZoom)); if (chatZoom != 1) ChatList.LayoutTransform = new ScaleTransform(chatZoom, chatZoom);
            if (double.TryParse(Kit.Opt("chatwidth", "440"), out var cw)) chatW = Math.Max(320, cw);
            try { if (Directory.Exists(AttDir)) foreach (var f in new DirectoryInfo(AttDir).GetFiles()) if (f.LastWriteTime < DateTime.Now.AddDays(-30)) f.Delete(); } catch { }
            IconBtn(ChatClose, "E711"); IconBtn(ChatNew, "E710"); IconBtn(ChatSend, "E724", true); IconBtn(ChatMenu, "E700"); ChatMenu.Margin = new Thickness(0); IconBtn(ChatRemote, "E8EA");
            ChatRemote.ToolTip = "Remote Control is on: this chat is on your phone (Claude app) and at claude.ai/code too - click to open it in the browser";
            ChatRemote.Click += (s, e) => { if (ChatRemote.Tag is string u && u != "") Actions.Open(u); };
            ChatMenu.Click += (s, e) => ShowChatMenu(ChatMenuPanel.Visibility != Visibility.Visible);
            ChatSearch.TextChanged += (s, e) => { ChatSearchHint.Visibility = ChatSearch.Text != "" ? Visibility.Collapsed : Visibility.Visible; if (ChatMenuPanel.Visibility == Visibility.Visible) UpdateChatMenu(); };
            ChatSplit.DragCompleted += (s, e) => { chatW = Math.Round(ChatCol.ActualWidth); Kit.SetOpt("chatwidth", chatW.ToString()); UpdateLayout2(); };
            ChatClose.Click += (s, e) => ShowChat(false);
            ChatNew.Click += (s, e) => NewConversation();
            ChatSend.Click += (s, e) => { if (sendBusy) ChatData.Send(chatDir, new Dictionary<string, object> { ["cmd"] = "stop" }); else SendChat(ChatInput.Text); };
            ChatInput.TextChanged += (s, e) => ChatHint.Visibility = ChatInput.Text != "" || attach.Count > 0 ? Visibility.Collapsed : Visibility.Visible;
            ChatInput.PreviewKeyDown += ChatInputKeys;
            ChatTitle.MouseLeftButtonDown += (s, e) => { if (e.ClickCount == 2) { e.Handled = true; StartRename(chatDir); } };
            // files dropped on the chat (from Explorer; Windows doesn't let a program without admin rights drop onto one with
            // them - then Ctrl+C the file in Explorer and Ctrl+V it here)
            ChatPanel.PreviewDragOver += (s, e) => { if (e.Data.GetDataPresent(DataFormats.FileDrop)) { e.Effects = DragDropEffects.Copy; e.Handled = true; } };
            ChatPanel.PreviewDragEnter += (s, e) => { if (e.Data.GetDataPresent(DataFormats.FileDrop)) { e.Effects = DragDropEffects.Copy; e.Handled = true; } };
            ChatPanel.PreviewDrop += (s, e) => { if (e.Data.GetDataPresent(DataFormats.FileDrop)) { e.Handled = true; AddAttach((string[])e.Data.GetData(DataFormats.FileDrop)); } };
            // the chat scrolls as one (the messages are documents that would keep the wheel to themselves); Ctrl+wheel: size
            ChatScroll.PreviewMouseWheel += (s, e) =>
            {
                e.Handled = true;
                if ((Keyboard.Modifiers & ModifierKeys.Control) != 0) { SetZoom(chatZoom + (e.Delta > 0 ? 0.1 : -0.1)); Say($"Chat text size: {(int)Math.Round(chatZoom * 100)}% (Ctrl+0: back to normal)"); }
                else ChatScroll.ScrollToVerticalOffset(ChatScroll.VerticalOffset - e.Delta);
            };
            // the speed, the find bar
            ChatMode.Style = (Style)FindResource("Btn"); ChatMode.Margin = Ui.Th("4,0,0,0"); ChatMode.Padding = Ui.Th("9,6");
            ChatMode.Click += (s, e) =>
            {
                var cm = new ContextMenu(); var cur = ChatData.Mode(chatDir).Value;
                foreach (var m in ChatData.Modes) { var mi = new MenuItem { Header = $"{m.Name} - {m.About}", IsCheckable = true, IsChecked = m.Value == cur }; var v = m.Value; mi.Click += (x, y) => SetMode(v); cm.Items.Add(mi); }
                cm.PlacementTarget = ChatMode; cm.Placement = PlacementMode.Bottom; cm.IsOpen = true;
            };
            UpdateModeBtn();
            foreach (var (b, g, tip) in new[] { (ChatFindPrev, "E70E", "Previous (Shift+Enter)"), (ChatFindNext, "E70D", "Next (Enter)"), (ChatFindClose, "E711", "Close (Esc)") }) { IconBtn(b, g); b.Padding = Ui.Th("6,4"); b.Margin = Ui.Th("2,0,0,0"); b.ToolTip = tip; ((TextBlock)b.Content).FontSize = 11; }
            ChatFindPrev.Click += (s, e) => StepFind(-1); ChatFindNext.Click += (s, e) => StepFind(1); ChatFindClose.Click += (s, e) => ShowFind(false);
            ChatFindBox.TextChanged += (s, e) => FindInChat(ChatFindBox.Text);
            ChatFindBox.PreviewKeyDown += (s, e) => { if (e.Key == Key.Return) { e.Handled = true; StepFind((Keyboard.Modifiers & ModifierKeys.Shift) != 0 ? -1 : 1); } else if (e.Key == Key.Escape) { e.Handled = true; ShowFind(false); } };
            // Ask Claude, top right; the line saying what's running
            AiPill.Style = (Style)FindResource("Btn"); AiPill.Margin = new Thickness(0); AiPill.Padding = Ui.Th("14,6"); AiPill.ToolTip = "Chat with Claude - it can look at this PC and fix things";
            var aisp = new StackPanel { Orientation = Orientation.Horizontal }; aisp.Children.Add(Ui.Glyph("E99A", 14, Br("Accent"))); aisp.Children.Add(new TextBlock { Text = "Ask Claude", Margin = Ui.Th("8,0,0,0"), VerticalAlignment = VerticalAlignment.Center }); AiPill.Content = aisp;
            AiPill.Click += (s, e) => ShowChat(ChatPanel.Visibility != Visibility.Visible);
            NowBar.MouseLeftButtonUp += (s, e) => { if ((NowBar.Tag as string) == "chat" && snap != null && snap.Ai) { if (nowChat != null && nowChat != chatDir) chatDir = nowChat; ShowChat(true); } else ShowPage("Activity", "Checks"); };
            PreviewKeyDown += WindowKeys;
            fast.Tick += (s, e) => { try { if (ChatPanel.Visibility == Visibility.Visible && fastN % 3 == 0) UpdateChat(); fastN++; UpdateNow(); } catch (Exception ex) { App.Log("chat tick: " + ex.Message); } };
        }
        void IconBtn(Button b, string glyph, bool accent = false)
        {
            b.Style = (Style)FindResource(accent ? "AccentBtn" : "Btn"); b.Margin = Ui.Th("4,0,0,0"); b.Padding = Ui.Th("9,7");
            b.Content = Ui.Glyph(glyph, 14, accent ? Br("OnAccent") : Br("Text"));
        }

        // --- open / close, the history
        public void ShowChat(bool on)
        {
            ChatPanel.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
            if (on)
            {
                // room for the page and the chat side by side, when the screen has it
                if (WindowState == WindowState.Normal && ActualWidth < chatW + 600) { var a = WorkArea(); var nw = Math.Min(a.Width, chatW + 760); if (nw > ActualWidth) { Width = nw; if (Left + nw > a.Right) Left = Math.Max(a.Left, a.Right - nw); } }
                OpenHistory(null); if (ChatData.State(chatDir) == null) ChatData.Send(chatDir, new Dictionary<string, object> { ["cmd"] = "start" }); ChatInput.Focus();
            }
            else ShowChatMenu(false);
            UpdateLayout2();
        }
        // the open chat's conversation: from its transcript; a conversation not saved yet (or a failed first message): the
        // events since its Claude started (deltas left out - the whole messages follow them)
        void OpenHistory(string session)
        {
            finds.Clear(); findAt = -1; if (ChatFind.Visibility == Visibility.Visible) { ChatFind.Visibility = Visibility.Collapsed; ChatFindCount.Text = ""; }
            UpdateModeBtn();
            ChatList.Children.Clear(); live = null; lastUser = null; if (editing) { StopEdit(); ChatInput.Text = ""; ClearAttach(); }
            var f = Path.Combine(chatDir, "events.jsonl"); int shown = 0;
            foreach (var (t, x) in ChatData.Transcript(session ?? ChatData.Session(chatDir))) { AddItem(t, x); shown++; }
            if (shown == 0)
            {
                var lines = ChatData.ReadShared(f).ToList(); lines = lines.Skip(Math.Max(0, lines.Count - 300)).ToList();
                int start = 0; for (int i = lines.Count - 1; i >= 0; i--) if (Regex.IsMatch(lines[i], "\"t\":\"session\"|\"t\":\"status\",\"text\":\"(New conversation|Opened an earlier|Continuing a copy)")) { start = i + 1; break; }
                foreach (var l in lines.Skip(start)) { var e = Kit.ParseJson(l); var t = Json.S(e, "t"); if (t != "" && t != "delta" && t != "session") { AddItem(t, Json.S(e, "text")); shown++; } }
            }
            if (shown == 0) ShowStart();
            try { chatPos = File.Exists(f) ? new FileInfo(f).Length : 0; } catch { chatPos = 0; }
            ChatScroll.ScrollToEnd();
            ChatTitle.Text = HeaderTitle(null); tabsKey = null; UpdateTabs();
        }
        string HeaderTitle(string auto) { var o = ChatData.OwnTitle(chatDir); return o != "" ? o : ChatData.Dirs().Count > 1 ? auto ?? ChatData.ChatTitle(chatDir) : "Claude"; }

        // one item of the conversation: the owner's message (a bubble, editable when it's the last), Claude's answer (with
        // its copy button), a step, an error, a status line
        void AddItem(string t, string text)
        {
            switch (t)
            {
                case "user":
                    {
                        var rtb = Md.Doc(); var doc = rtb.Document; var words = new List<string>(); var shown = new List<string>();
                        foreach (var l in (text ?? "").Replace("\r", "").Split('\n'))
                        {
                            var m = Regex.Match(l, AttachRx);
                            if (m.Success)
                            {
                                var f = m.Groups[1].Value.Trim(); shown.Add("xx " + Path.GetFileName(f));
                                var p = new Paragraph { Margin = Ui.Th("0,2,0,0"), FontSize = 12.5 }; p.Inlines.Add(new Run("\U0001F4CE "));
                                if (File.Exists(f) || Directory.Exists(f)) p.Inlines.Add(Md.Link(Path.GetFileName(f), f)); else p.Inlines.Add(new Run(Path.GetFileName(f)));
                                doc.Blocks.Add(p);
                            }
                            else words.Add(l);
                        }
                        var w = string.Join("\n", words).Trim();
                        if (w != "") { var p = new Paragraph { Margin = new Thickness(0) }; Md.AddPlain(p.Inlines, w); if (doc.Blocks.FirstBlock != null) doc.Blocks.InsertBefore(doc.Blocks.FirstBlock, p); else doc.Blocks.Add(p); }
                        if (doc.Blocks.Count == 0) return;
                        rtb.MaxWidth = Math.Max(40, Md.Width(w.Split('\n').Concat(shown)) + 16);
                        var b = new Border { CornerRadius = new CornerRadius(12), Padding = Ui.Th("10,6"), HorizontalAlignment = HorizontalAlignment.Right, Background = Theme.Tint(Br("Accent"), 0x40), Child = rtb };
                        // the last message can be edited (a pencil beside it on hover): sent again in its place
                        var wrap = new DockPanel { HorizontalAlignment = HorizontalAlignment.Right, Margin = Ui.Th("48,10,0,6"), Background = Brushes.Transparent, Tag = text };
                        var eb = new Button { ToolTip = "Edit - Claude answers the new version instead", VerticalAlignment = VerticalAlignment.Center, Opacity = 0 };
                        IconBtn(eb, "E70F"); eb.Margin = Ui.Th("0,0,6,0"); eb.Padding = Ui.Th("6,4"); ((TextBlock)eb.Content).FontSize = 12;
                        eb.Click += (s, e) => { if (wrap == lastUser) StartEdit((string)wrap.Tag); };
                        DockPanel.SetDock(eb, Dock.Left); wrap.Children.Add(eb); wrap.Children.Add(b);
                        wrap.MouseEnter += (s, e) => { if (wrap == lastUser) eb.Opacity = 1; }; wrap.MouseLeave += (s, e) => eb.Opacity = 0;
                        lastUser = wrap; ChatList.Children.Add(wrap);
                        break;
                    }
                case "text":
                    {
                        var sp = new StackPanel { Margin = Ui.Th("0,6,0,6"), Background = Brushes.Transparent };
                        sp.Children.Add(Md.Render(text));
                        var cp = Md.CopyBtn(text, "Copy this reply"); cp.HorizontalAlignment = HorizontalAlignment.Left; cp.Opacity = 0; cp.Margin = Ui.Th("0,2,0,0"); sp.Children.Add(cp);
                        sp.MouseEnter += (s, e) => cp.Opacity = 1; sp.MouseLeave += (s, e) => cp.Opacity = 0;
                        ChatList.Children.Add(sp);
                        break;
                    }
                case "tool":
                    {
                        var r = new DockPanel { Margin = Ui.Th("2,2,0,2") };
                        var g = Ui.Glyph("E756", 11, Br("Sub")); g.Margin = Ui.Th("0,1,8,0"); DockPanel.SetDock(g, Dock.Left); r.Children.Add(g);
                        r.Children.Add(new TextBlock { Text = text, Foreground = Br("Sub"), FontSize = 12, TextTrimming = TextTrimming.CharacterEllipsis, ToolTip = text });
                        ChatList.Children.Add(r);
                        break;
                    }
                case "error": ChatList.Children.Add(Ui.LineEl("WARNING: " + text, "warn")); break;
                case "status": if (text != "idle") { var x = Ui.Text(text, Br("Sub"), 12, null, "0,8,0,8"); x.HorizontalAlignment = HorizontalAlignment.Center; ChatList.Children.Add(x); } break;
            }
        }
        // suggestions on an empty chat (and the to-do walk-through)
        void ShowStart()
        {
            ChatList.Children.Clear();
            ChatList.Children.Add(Ui.Text("Ask anything - Claude can look at this PC and fix things, with admin rights. What it does shows here as it happens.", Br("Sub"), 13, null, "0,6,0,12"));
            var ideas = new List<string>(); if (File.Exists(Kit.P("maint-todo.txt"))) ideas.Add("Go through my to-do list with me");
            ideas.AddRange(new[] { "How is my PC doing?", "Why is my PC slow or stuttering?", "What did maintenance do this week?" });
            foreach (var i in ideas) { var b = Ui.Btn("E8BD", i, () => SendChat(i), small: true); b.Margin = Ui.Th("0,0,0,6"); b.HorizontalAlignment = HorizontalAlignment.Left; ChatList.Children.Add(b); }
        }

        // --- sending: a message, its files, an edit of the last one
        public void SendChat(string t)
        {
            if (t == "Go through my to-do list with me") t = "/maintain The owner opened the chat in the Messiah app. Briefly go through the open items in maint-todo.txt with them.";
            var files = attach.ToList();
            if ((t ?? "").Trim() == "" && files.Count == 0) return;
            if (t.Trim() != "") lastSent[chatDir] = t;
            if (files.Count > 0) { t = string.Join("\n", new[] { t.Trim() != "" ? t.TrimEnd() : "Take a look at this." }.Concat(files.Select(f => "Attached: " + f))); ClearAttach(); }
            if (editing && lastUser != null)
            {
                var i = ChatList.Children.IndexOf(lastUser);   // (the old message and everything after it go)
                if (i >= 0) while (ChatList.Children.Count > i) ChatList.Children.RemoveAt(i);
                lastUser = null; live = null; StopEdit();
                ChatData.Send(chatDir, new Dictionary<string, object> { ["cmd"] = "edit", ["text"] = t });
            }
            else { StopEdit(); ChatData.Send(chatDir, new Dictionary<string, object> { ["text"] = t }); }
            ChatInput.Text = ""; ChatWorking.Text = "Sending..."; ChatWorking.Visibility = Visibility.Visible;
        }
        void StartEdit(string text)
        {
            ClearAttach(); var w = new List<string>();
            foreach (var l in text.Replace("\r", "").Split('\n')) { var m = Regex.Match(l, AttachRx); if (m.Success) AddAttach(new[] { m.Groups[1].Value.Trim() }); else w.Add(l); }
            ChatInput.Text = string.Join("\n", w).Trim(); ChatInput.CaretIndex = ChatInput.Text.Length;
            editing = true; ChatEditing.Visibility = Visibility.Visible; ChatInput.Focus();
        }
        void StopEdit() { editing = false; ChatEditing.Visibility = Visibility.Collapsed; }
        // Enter sends (Shift+Enter: a new line); Up in an empty box: the last message again; Ctrl+V: a screenshot or files
        // from Explorer go with the message (text pastes as usual)
        void ChatInputKeys(object s, KeyEventArgs e)
        {
            var mods = Keyboard.Modifiers;
            if (e.Key == Key.Return && (mods & ModifierKeys.Shift) == 0) { e.Handled = true; if (!sendBusy || editing) SendChat(ChatInput.Text); }
            else if (e.Key == Key.Escape && editing) { e.Handled = true; StopEdit(); ChatInput.Text = ""; ClearAttach(); }
            else if (e.Key == Key.Up && ChatInput.Text == "" && lastSent.TryGetValue(chatDir, out var ls)) { e.Handled = true; ChatInput.Text = ls; ChatInput.CaretIndex = ls.Length; }
            else if (e.Key == Key.V && mods == ModifierKeys.Control)
            {
                try
                {
                    if (Clipboard.ContainsFileDropList()) { e.Handled = true; AddAttach(Clipboard.GetFileDropList().Cast<string>().ToArray()); }
                    else if (Clipboard.ContainsImage()) { e.Handled = true; var f = SaveClipImage(); if (f != null) AddAttach(new[] { f }); }
                }
                catch (Exception ex) { Say("Couldn't paste that: " + ex.Message); }
            }
        }
        // files going with the next message: pasted pictures (saved in .claude\chat-attachments - kept 30 days) and files
        // pasted or dropped from Explorer (sent as their paths; Claude Code reads pictures as pictures)
        void UpdateAttach()
        {
            ChatAttach.Children.Clear();
            foreach (var f in attach)
            {
                var chip = new Border { CornerRadius = new CornerRadius(6), Background = Br("Seg"), Padding = Ui.Th("8,2,2,2"), Margin = Ui.Th("0,0,6,4"), ToolTip = f };
                var sp = new StackPanel { Orientation = Orientation.Horizontal };
                var g = Ui.Glyph(Regex.IsMatch(f, @"\.(png|jpe?g|gif|bmp|webp)$", RegexOptions.IgnoreCase) ? "EB9F" : "E8A5", 12, Br("Sub")); g.Margin = Ui.Th("0,0,6,0"); sp.Children.Add(g);
                sp.Children.Add(new TextBlock { Text = Path.GetFileName(f), FontSize = 12, MaxWidth = 180, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center });
                var x = new Button { ToolTip = "Don't send this" }; IconBtn(x, "E711"); x.Margin = Ui.Th("4,0,0,0"); x.Padding = Ui.Th("4,2"); ((TextBlock)x.Content).FontSize = 9;
                var ff = f; x.Click += (s, e) => { attach.Remove(ff); UpdateAttach(); };
                sp.Children.Add(x); chip.Child = sp; ChatAttach.Children.Add(chip);
            }
            ChatAttach.Visibility = attach.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
            ChatHint.Visibility = ChatInput.Text != "" || attach.Count > 0 ? Visibility.Collapsed : Visibility.Visible;
        }
        void ClearAttach() { attach.Clear(); UpdateAttach(); }
        void AddAttach(IEnumerable<string> paths) { foreach (var f in paths) if (!string.IsNullOrEmpty(f) && (File.Exists(f) || Directory.Exists(f)) && !attach.Contains(f)) attach.Add(f); UpdateAttach(); ChatInput.Focus(); }
        // a picture on the clipboard (a screenshot, Win+Shift+S): saved as a PNG file to send
        string SaveClipImage()
        {
            var img = Clipboard.GetImage(); if (img == null) return null;
            Directory.CreateDirectory(AttDir); var f = Path.Combine(AttDir, $"screenshot-{DateTime.Now:yyyyMMdd-HHmmss-fff}.png");
            var enc = new PngBitmapEncoder(); enc.Frames.Add(BitmapFrame.Create(img)); using (var fs = File.Create(f)) enc.Save(fs);
            return f;
        }

        // --- following the chat: events.jsonl, whole lines only, from where it left off
        void UpdateChat()
        {
            var f = Path.Combine(chatDir, "events.jsonl"); if (!File.Exists(f)) return;
            string text;
            try
            {
                using (var fs = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete))
                {
                    if (fs.Length < chatPos) chatPos = 0;   // shortened by the host: read again
                    if (fs.Length == chatPos) return;
                    fs.Seek(chatPos, SeekOrigin.Begin); var buf = new byte[fs.Length - chatPos]; var n = fs.Read(buf, 0, buf.Length);
                    var cut = Array.LastIndexOf(buf, (byte)'\n', n - 1) + 1; if (cut <= 0) return;
                    text = Encoding.UTF8.GetString(buf, 0, cut); chatPos += cut;
                }
            }
            catch { return; }
            bool atEnd = ChatScroll.VerticalOffset >= ChatScroll.ScrollableHeight - 40;
            foreach (var line in text.Split('\n'))
            {
                var e = Kit.ParseJson(line); var t = Json.S(e, "t"); if (t == "") continue;
                if (t == "delta")
                {
                    if (live == null) { live = Ui.Text("", Br("Text"), 14, null, "0,6,0,6"); liveText = ""; ChatList.Children.Add(live); }
                    liveText += Json.S(e, "text"); live.Text = liveText; continue;
                }
                if (t == "text" && live != null) { ChatList.Children.Remove(live); live = null; }
                if ((t == "text" || t == "error" || (t == "status" && Json.S(e, "text") == "idle")) && ChatWorking.Text == "Sending...") ChatWorking.Visibility = Visibility.Collapsed;   // (a reply faster than the busy flag)
                if (t == "session") continue;
                if (ChatList.Children.Count > 0 && ChatList.Children[0] is TextBlock tb0 && tb0.Text.StartsWith("Ask anything")) ChatList.Children.Clear();
                AddItem(t, Json.S(e, "text"));
            }
            if (atEnd) ChatScroll.ScrollToEnd();
        }

        // --- what's running right now - a chat, a hidden maintenance run - one line at the top; the chat's own status
        string lastWa;
        void UpdateNow()
        {
            ReadRequest();
            (string Kind, string Text)? n = null;
            foreach (var d in ChatData.Dirs()) { var cs = ChatData.State(d); if (cs != null && Json.B(cs, "busy")) { nowChat = d; n = ("chat", "Claude is working" + (Json.S(cs, "step") != "" ? ": " + Json.S(cs, "step") : "")); break; } }
            if (n == null)
            {
                var m = Kit.P("maint-claude-running");
                if (File.Exists(m) && (DateTime.Now - File.GetLastWriteTime(m)).TotalMinutes < 60 && File.GetLastWriteTime(m) > Data.BootTime)
                {
                    var s = Kit.Lines(Kit.P("maint-claude-session"));
                    var kind = s.Length > 1 && s[1].Contains("improve") ? "improving Messiah" : s.Length > 1 && s[1].Contains("maintain") ? "checking the PC" : "maintenance";
                    n = ("maint", $"Claude is {kind} in the background" + (s.Length > 0 ? StepOf(s[0]) : ""));
                }
            }
            NowBar.Visibility = n != null ? Visibility.Visible : Visibility.Collapsed;
            if (n != null) { NowText.Text = n.Value.Text; NowBar.Tag = n.Value.Kind; NowDot.Opacity = nowTick++ % 2 == 1 ? 0.35 : 1; }
            var st = ChatData.State(chatDir);
            ChatStatus.Text = st == null ? "Starts when you send a message" : Json.B(st, "busy") ? "Working" : "Ready" + (Json.S(st, "remote") != "" ? " - on your phone too" : "");
            ChatRemote.Visibility = st != null && Json.S(st, "remote") != "" ? Visibility.Visible : Visibility.Collapsed; ChatRemote.Tag = Json.S(st, "remote");
            UpdateTabs();
            // the screen changed (resolution, another monitor): the window fits it again
            var wa = WorkArea().ToString(); if (lastWa != null && wa != lastWa) { FitToScreen(); UpdateLayout2(); } lastWa = wa;
            bool busy = st != null && Json.B(st, "busy");
            ChatWorking.Visibility = busy || (ChatWorking.Text == "Sending..." && st != null) ? Visibility.Visible : Visibility.Collapsed;
            if (busy) ChatWorking.Text = "● " + (Json.S(st, "step") != "" ? Json.S(st, "step") : "Thinking") + "...";
            if (sendBusy != busy) { sendBusy = busy; if (busy) { IconBtn(ChatSend, "E71A"); ChatSend.ToolTip = "Stop"; } else { IconBtn(ChatSend, "E724", true); ChatSend.ToolTip = "Send (Enter) - Shift+Enter for a new line"; } }
        }
        // the step a hidden run is on: from the end of its transcript (the last 64 KB, not the whole file)
        static string StepOf(string id)
        {
            try
            {
                var f = Directory.GetFiles(Kit.P("projects"), id + ".jsonl", SearchOption.AllDirectories).FirstOrDefault(); if (f == null) return "";
                string tail; using (var fs = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete)) { var n = (int)Math.Min(fs.Length, 65536); fs.Seek(-n, SeekOrigin.End); var b = new byte[n]; fs.Read(b, 0, n); tail = Encoding.UTF8.GetString(b); }
                string step = "";
                foreach (var l in tail.Split('\n').Reverse().Take(30).Reverse())
                {
                    if (!l.Contains("\"type\":\"assistant\"")) continue; var j = Kit.ParseJson(l);
                    foreach (var c in Json.L(Json.Get(j, "message"), "content")) if (Json.S(c, "type") == "tool_use") step = Json.S(Json.Get(c, "input"), "description") != "" ? Json.S(Json.Get(c, "input"), "description") : Json.S(c, "name");
                }
                return step != "" ? ": " + step : "";
            }
            catch { return ""; }
        }

        // --- tabs: the chats running here, under the title (only with more than one); rebuilt only when one changed
        void UpdateTabs()
        {
            var dirs = ChatData.Dirs();
            var tabs = dirs.Select(d => { var s = ChatData.State(d); return (Dir: d, Title: ChatData.ChatTitle(d), Busy: s != null && Json.B(s, "busy"), Pin: ChatData.Pinned(d)); }).ToList();
            var key = chatDir + "|" + string.Join("|", tabs.Select(t => $"{t.Dir}>{t.Title}>{t.Busy}>{t.Pin}"));
            if (key == tabsKey || renaming) return; tabsKey = key;
            ChatTabs.Children.Clear(); ChatTabs.Visibility = dirs.Count > 1 ? Visibility.Visible : Visibility.Collapsed;
            if (dirs.Count < 2) return;
            foreach (var t in tabs)
            {
                bool cur = t.Dir == chatDir; var d = t.Dir;
                var tab = new Border { CornerRadius = new CornerRadius(8), Padding = Ui.Th("9,4,4,4"), Margin = Ui.Th("0,0,6,6"), Cursor = Cursors.Hand, Tag = d, ToolTip = t.Title, BorderThickness = new Thickness(1), Background = cur ? Br("SegSel") : Br("Seg"), BorderBrush = cur ? Br("Accent") : Brushes.Transparent };
                var sp = new StackPanel { Orientation = Orientation.Horizontal };
                if (t.Busy) { var g = Ui.Glyph("E916", 11, Br("Accent")); g.Margin = Ui.Th("0,0,6,0"); sp.Children.Add(g); }
                else if (t.Pin) { var g = Ui.Glyph("E718", 11, Br("Sub")); g.Margin = Ui.Th("0,0,6,0"); sp.Children.Add(g); }
                sp.Children.Add(new TextBlock { Text = t.Title, FontSize = 12, MaxWidth = 140, TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center, Foreground = cur ? Br("Text") : Br("Sub") });
                // right-click: rename, pin, close; double-click: rename
                var cm = new ContextMenu();
                foreach (var (label, w) in new[] { ("Rename", "rename"), (t.Pin ? "Unpin" : "Pin (stays first, can't be closed by accident)", "pin"), ("Close", "close") })
                {
                    var mi = new MenuItem { Header = label }; if (w == "close" && (t.Pin || d == ChatData.Main)) mi.IsEnabled = false;
                    mi.Click += (x, y) => { if (w == "rename") StartRename(d); else if (w == "pin") TogglePin(d); else CloseTab(d); }; cm.Items.Add(mi);
                }
                tab.ContextMenu = cm;
                tab.MouseLeftButtonDown += (x, e) => { if (e.ClickCount == 2) { e.Handled = true; StartRename(d); } };
                if (d != ChatData.Main && !t.Pin)
                {
                    var xb = new Button { ToolTip = "Close this tab (the conversation stays in the list)", VerticalAlignment = VerticalAlignment.Center }; IconBtn(xb, "E711"); xb.Margin = Ui.Th("4,0,0,0"); xb.Padding = Ui.Th("4,2"); ((TextBlock)xb.Content).FontSize = 9;
                    xb.Click += (x, e) => { e.Handled = true; CloseTab(d); }; sp.Children.Add(xb);
                }
                else sp.Margin = Ui.Th("0,0,5,0");
                tab.Child = sp;
                if (!cur) { tab.MouseEnter += (x, e) => tab.Background = Br("NavHover"); tab.MouseLeave += (x, e) => tab.Background = Br("Seg"); }
                tab.MouseLeftButtonUp += (x, e) => { if (d != chatDir) SwitchChat(d); };
                ChatTabs.Children.Add(tab);
            }
        }
        void SwitchChat(string d)
        {
            chatDir = d; AppLast.ChatTab = d == ChatData.Main ? "" : Path.GetFileName(d); AppLast.Save();
            ShowChatMenu(false); OpenHistory(null); if (ChatData.State(chatDir) == null) ChatData.Send(chatDir, new Dictionary<string, object> { ["cmd"] = "start" }); UpdateNow(); ChatInput.Focus();
        }
        void NewTab()
        {
            var d = Kit.P($@"chats\{DateTime.Now:yyyyMMdd-HHmmss}"); Directory.CreateDirectory(Path.Combine(d, "inbox"));
            File.WriteAllText(Path.Combine(d, "name.txt"), "Messiah " + ChatData.Dirs().Count);   // (its name in Remote Control, on the phone)
            SwitchChat(d);
        }
        // a new conversation opens in a new tab and the one open keeps going (this chat still empty: it's already new)
        void NewConversation() { var cs = ChatData.State(chatDir); if (ChatData.Session(chatDir) != "" || (cs != null && Json.B(cs, "busy"))) NewTab(); else { ShowChatMenu(false); ShowStart(); ChatInput.Focus(); } }
        void CloseTab(string d)
        {
            if (ChatData.Pinned(d)) { Say("This tab is pinned - right-click it > Unpin first."); return; }
            var s = ChatData.State(d);
            if (s != null && Json.B(s, "busy") && MessageBox.Show("Claude is still working in this chat. Stop it and close the chat?", "Close chat", MessageBoxButton.OKCancel, MessageBoxImage.Question) != MessageBoxResult.OK) return;
            ChatData.Closing.Add(d);
            if (s != null) ChatData.Send(d, new Dictionary<string, object> { ["cmd"] = "quit" }); else try { Directory.Delete(d, true); } catch { }
            if (chatDir == d) SwitchChat(ChatData.Main); else if (ChatMenuPanel.Visibility == Visibility.Visible) UpdateChatMenu();
            tabsKey = null; UpdateTabs();
        }
        // pin: the tab stays first and has no close button; rename: a box in the tab (or the chat's title, with one chat) -
        // Enter keeps it, Esc goes back, empty = the conversation's own title again. Also its name in Remote Control.
        void TogglePin(string d)
        {
            var f = Path.Combine(d, "pinned.txt");
            if (File.Exists(f)) { File.Delete(f); Say("Unpinned."); } else { File.WriteAllText(f, DateTime.Now.ToString("s")); Say("Pinned - it stays first and can't be closed by accident."); }
            tabsKey = null; UpdateTabs();
        }
        void SaveName(string d, string name)
        {
            name = Regex.Replace(name ?? "", @"\s+", " ").Trim(); if (name.Length > 60) name = name.Substring(0, 60);
            if (name != "") { File.WriteAllText(Path.Combine(d, "title.txt"), name, new UTF8Encoding(false)); File.WriteAllText(Path.Combine(d, "name.txt"), name, Encoding.UTF8); }
            else if (File.Exists(Path.Combine(d, "title.txt"))) File.Delete(Path.Combine(d, "title.txt"));
        }
        void StartRename(string d)
        {
            if (renaming) return;
            var tab = ChatTabs.Children.OfType<Border>().FirstOrDefault(b => (b.Tag as string) == d);
            var box = new TextBox { Text = ChatData.ChatTitle(d), FontSize = 12, MinWidth = 140, MaxWidth = 220, Background = Br("Btn"), Foreground = Br("Text"), CaretBrush = Br("Text"), BorderBrush = Br("Accent"), Padding = Ui.Th("4,1") };
            UIElement old = null;
            if (tab != null && ChatTabs.Visibility == Visibility.Visible) { old = tab.Child; tab.Child = box; }
            else { box.FontSize = 15; ChatTitle.Visibility = Visibility.Collapsed; ChatTitleBox.Children.Insert(0, box); }
            renaming = true;
            void Done(bool keep)
            {
                if (!renaming) return; renaming = false;
                if (keep) SaveName(d, box.Text);
                if (old != null) tab.Child = old; else { ChatTitleBox.Children.Remove(box); ChatTitle.Visibility = Visibility.Visible; }
                tabsKey = null; UpdateTabs(); ChatTitle.Text = HeaderTitle(null);
            }
            box.KeyDown += (s, e) => { if (e.Key == Key.Return) { e.Handled = true; Done(true); } else if (e.Key == Key.Escape) { e.Handled = true; Done(false); } };
            box.LostKeyboardFocus += (s, e) => Done(true);
            box.Focus(); box.SelectAll();
        }

        // --- the chat menu (top left): the chats running here, a new one beside them, and earlier conversations (this PC's:
        // the app, the terminal, the phone) to pick up again - those are read in the background
        void ShowChatMenu(bool on)
        {
            ChatMenuPanel.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
            IconBtn(ChatMenu, on ? "E711" : "E700"); ChatMenu.Margin = new Thickness(0);
            if (on) { earlier = null; ChatSearch.Text = ""; UpdateChatMenu(); ChatSearch.Focus(); }   // (the earlier conversations: read again each time it opens)
        }
        List<ChatData.Earlier> earlier; int menuGen;
        void UpdateChatMenu()
        {
            var L = ChatMenuList; L.Children.Clear(); var q = ChatSearch.Text.Trim();
            var dirs = ChatData.Dirs(); var open = new Dictionary<string, string>(); foreach (var d in dirs) { var s = ChatData.Session(d); if (s != "") open[s] = d; }
            if (q == "")
            {
                L.Children.Add(Ui.Section("Chats running here"));
                foreach (var d in dirs)
                {
                    var s = ChatData.State(d);
                    var sub = s != null && Json.B(s, "busy") ? "Working" + (Json.S(s, "step") != "" ? ": " + Json.S(s, "step") : "") : s != null ? "Ready" + (Json.S(s, "remote") != "" ? " - on your phone too" : "") : "Starts when you send a message";
                    var dd = d; L.Children.Add(MenuRow(ChatData.ChatTitle(d), sub, () => SwitchChat(dd), d == chatDir, d != ChatData.Main ? () => CloseTab(dd) : (Action)null, s != null && Json.B(s, "busy") ? "E916" : "E8BD"));
                }
                L.Children.Add(MenuRow("New chat beside these", "Another Claude, working at the same time (Ctrl+T)", NewTab, false, null, "E710"));
                if (ChatData.Session(chatDir) != "") L.Children.Add(MenuRow("Copy this conversation", "The whole chat as text, to paste anywhere", () => { CopyConversation(); ShowChatMenu(false); }, false, null, "E8C8"));
            }
            L.Children.Add(Ui.Section("Earlier conversations"));
            if (earlier == null)
            {
                L.Children.Add(Ui.Text("Loading...", Br("Sub"), 13, null, "10,4,0,0"));
                var gen = ++menuGen;
                Task.Run(() => ChatData.Sessions()).ContinueWith(t => Dispatcher.BeginInvoke(new Action(() => { if (gen != menuGen) return; earlier = t.Result; if (ChatMenuPanel.Visibility == Visibility.Visible) UpdateChatMenu(); })));
                return;
            }
            int n = 0;
            foreach (var s in earlier)
            {
                if (q != "" && s.Title.IndexOf(q, StringComparison.OrdinalIgnoreCase) < 0) continue;
                if (n++ >= 50) break;
                var where = open.ContainsKey(s.Id) ? "open in a chat here" : s.InUse ? "open somewhere else now" : "";
                var ss = s; L.Children.Add(MenuRow(s.Title, Kit.FormatWhen(s.When) + (where != "" ? "  -  " + where : ""), () => OpenEarlier(ss), false, null, "E81C"));
            }
            if (n == 0) L.Children.Add(Ui.Text(q != "" ? $"Nothing matches \"{q}\"." : "No earlier conversations yet.", Br("Sub"), 13, null, "10,4,0,0"));
        }
        Border MenuRow(string title, string sub, Action go, bool current, Action close, string glyph)
        {
            var row = new Border { CornerRadius = new CornerRadius(8), Padding = Ui.Th("10,8"), Margin = Ui.Th("0,0,0,2"), Cursor = Cursors.Hand, Background = current ? Br("SegSel") : Brushes.Transparent };
            var dp = new DockPanel();
            var g = Ui.Glyph(glyph, 13, current ? Br("Accent") : Br("Sub")); g.Margin = Ui.Th("0,2,10,0"); g.VerticalAlignment = VerticalAlignment.Top; DockPanel.SetDock(g, Dock.Left); dp.Children.Add(g);
            if (close != null) { var x = new Button { ToolTip = "Close this chat (the conversation stays in the list below)", VerticalAlignment = VerticalAlignment.Center }; IconBtn(x, "E711"); x.Padding = Ui.Th("6,4"); x.Click += (s, e) => { e.Handled = true; close(); }; DockPanel.SetDock(x, Dock.Right); dp.Children.Add(x); }
            var sp = new StackPanel();
            sp.Children.Add(new TextBlock { Text = title, FontSize = 13, Foreground = Br("Text"), TextTrimming = TextTrimming.CharacterEllipsis, ToolTip = title });
            if (!string.IsNullOrEmpty(sub)) sp.Children.Add(new TextBlock { Text = sub, FontSize = 11.5, Foreground = Br("Sub"), TextTrimming = TextTrimming.CharacterEllipsis });
            dp.Children.Add(sp); row.Child = dp;
            row.MouseEnter += (s, e) => { if (!current) row.Background = Br("NavHover"); }; row.MouseLeave += (s, e) => row.Background = current ? Br("SegSel") : Brushes.Transparent;
            row.MouseLeftButtonUp += (s, e) => { try { go(); } catch (Exception ex) { Say("Couldn't do that: " + ex.Message); } };
            return row;
        }
        // an earlier conversation: in the chat that has it open, else in this chat (or a new one beside it, when this one is
        // busy). Open somewhere else right now: a copy, so the two don't write over each other.
        void OpenEarlier(ChatData.Earlier s)
        {
            foreach (var d in ChatData.Dirs()) if (ChatData.Session(d) == s.Id) { SwitchChat(d); return; }
            var cs = ChatData.State(chatDir);
            if (cs != null && Json.B(cs, "busy")) { var d = Kit.P($@"chats\{DateTime.Now:yyyyMMdd-HHmmss}"); Directory.CreateDirectory(Path.Combine(d, "inbox")); File.WriteAllText(Path.Combine(d, "name.txt"), "Messiah " + ChatData.Dirs().Count); chatDir = d; }
            ChatData.Send(chatDir, new Dictionary<string, object> { ["cmd"] = "open", ["session"] = s.Id, ["fork"] = s.InUse });
            ShowChatMenu(false); OpenHistory(s.Id);
            if (s.InUse) Say("That conversation is open somewhere else too - this chat continues a copy of it, so the two don't clash.");
            ChatTitle.Text = HeaderTitle(s.Title); ChatInput.Focus();
        }
        void CopyConversation()
        {
            var items = ChatData.Transcript(ChatData.Session(chatDir), 2000).Where(i => i.T == "user" || i.T == "text").ToList();
            if (items.Count == 0) { Say("Nothing in this chat yet."); return; }
            Md.Copy(string.Join("\n\n", items.Select(i => (i.T == "user" ? "You" : "Claude") + ":\n" + i.X.Trim())), $"Copied the conversation ({items.Count} messages).");
        }

        // --- the speed, per tab (mode.txt, read by chat-host.ps1)
        void UpdateModeBtn()
        {
            var m = ChatData.Mode(chatDir); var sp = new StackPanel { Orientation = Orientation.Horizontal };
            sp.Children.Add(Ui.Glyph(m.Name == "Quick" ? "E945" : "E9D9", 13, Br("Text"))); sp.Children.Add(new TextBlock { Text = m.Name, FontSize = 12, Margin = Ui.Th("6,0,0,0"), VerticalAlignment = VerticalAlignment.Center });
            ChatMode.Content = sp; ChatMode.ToolTip = $"Speed: {m.Name} ({m.About}). Click to change - for this tab.";
        }
        void SetMode(string v)
        {
            var f = Path.Combine(chatDir, "mode.txt");
            if (v == "opus/medium") { if (File.Exists(f)) File.Delete(f); } else File.WriteAllText(f, v);
            UpdateModeBtn(); var st = ChatData.State(chatDir); if (st != null) ChatData.Send(chatDir, new Dictionary<string, object> { ["cmd"] = "mode" });
            Say($"{ChatData.Mode(chatDir).Name} from now on in this tab{(st != null && Json.B(st, "busy") ? " - after the current answer" : "")}.");
        }
        // --- text size (Ctrl+wheel, Ctrl+0)
        void SetZoom(double z) { chatZoom = Math.Round(Math.Min(1.6, Math.Max(0.8, z)), 2); ChatList.LayoutTransform = new ScaleTransform(chatZoom, chatZoom); AppLast.ChatZoom = chatZoom; AppLast.Save(); }

        // --- find in the open conversation (Ctrl+F in the chat): every match marked, Enter / Shift+Enter go through them
        class Hit { public TextRange R; public Brush Bg; public RichTextBox Box; }
        readonly List<Hit> finds = new List<Hit>(); int findAt = -1;
        Brush FindBrush => Theme.Tint(Br("Warn"), 0x55); Brush FindCur => Theme.Tint(Br("Warn"), 0xB0);
        IEnumerable<RichTextBox> ChatDocs()
        {
            foreach (var el in ChatList.Children)
            {
                if (el is StackPanel sp && sp.Children.Count > 0 && sp.Children[0] is RichTextBox a) yield return a;
                else if (el is DockPanel dp && dp.Children.Count > 1 && dp.Children[1] is Border b && b.Child is RichTextBox c) yield return c;
            }
        }
        void ClearFinds() { foreach (var f in finds) try { f.R.ApplyPropertyValue(TextElement.BackgroundProperty, f.Bg); } catch { } finds.Clear(); findAt = -1; }
        void FindInChat(string q)
        {
            ClearFinds();
            if (q.Length >= 2)
                foreach (var rtb in ChatDocs().ToList())
                {
                    var hits = new List<(TextPointer, DependencyObject)>(); var p = rtb.Document.ContentStart;
                    while (p != null)
                    {
                        if (p.GetPointerContext(LogicalDirection.Forward) == TextPointerContext.Text)
                        { var run = p.GetTextInRun(LogicalDirection.Forward); int i = 0; while ((i = run.IndexOf(q, i, StringComparison.OrdinalIgnoreCase)) >= 0) { hits.Add((p.GetPositionAtOffset(i), p.Parent)); i += q.Length; } }
                        p = p.GetNextContextPosition(LogicalDirection.Forward);
                    }
                    foreach (var (pos, parent) in hits)   // (marked after the walk: marking splits the text it walks)
                    {
                        var r = new TextRange(pos, pos.GetPositionAtOffset(q.Length));
                        finds.Add(new Hit { R = r, Bg = (parent as TextElement)?.Background, Box = rtb }); r.ApplyPropertyValue(TextElement.BackgroundProperty, FindBrush);
                    }
                }
            ChatFindCount.Text = q.Length < 2 ? "" : finds.Count > 0 ? finds.Count + " found" : "Not found";
            if (finds.Count > 0) StepFind(finds.Count - 1, true);   // (the newest first - what was just said)
        }
        void StepFind(int n, bool absolute = false)
        {
            if (finds.Count == 0) return;
            if (findAt >= 0) finds[findAt].R.ApplyPropertyValue(TextElement.BackgroundProperty, FindBrush);
            findAt = absolute ? n : (findAt + n + finds.Count) % finds.Count;
            var f = finds[findAt]; f.R.ApplyPropertyValue(TextElement.BackgroundProperty, FindCur);
            ChatFindCount.Text = $"{findAt + 1} of {finds.Count}";
            try { var rc = f.R.Start.GetCharacterRect(LogicalDirection.Forward); var pt = f.Box.TranslatePoint(new Point(0, rc.Top), ChatScroll); ChatScroll.ScrollToVerticalOffset(Math.Max(0, ChatScroll.VerticalOffset + pt.Y - 80)); } catch { }
        }
        void ShowFind(bool on)
        {
            ChatFind.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
            if (on) { ChatFindBox.Focus(); ChatFindBox.SelectAll(); if (ChatFindBox.Text != "") FindInChat(ChatFindBox.Text); } else { ClearFinds(); ChatFindCount.Text = ""; ChatInput.Focus(); }
        }

        // --- keys for the whole window: the chat's tabs (Ctrl+T new, Ctrl+W close - the first chat: hides the chat,
        // Ctrl+Tab / Ctrl+Shift+Tab switch), Ctrl+F in the chat: find in the conversation, Ctrl+0: normal text size
        void WindowKeys(object s, KeyEventArgs e)
        {
            bool ctrl = (Keyboard.Modifiers & ModifierKeys.Control) != 0, shift = (Keyboard.Modifiers & ModifierKeys.Shift) != 0;
            bool ai = snap != null && snap.Ai, chatOn = ai && ChatPanel.Visibility == Visibility.Visible;
            var key = e.Key == Key.System ? e.SystemKey : e.Key;
            if (ctrl && key == Key.F && chatOn && ChatPanel.IsKeyboardFocusWithin) { ShowFind(true); e.Handled = true; }
            else if (ctrl && key == Key.T && ai) { e.Handled = true; if (!chatOn) ShowChat(true); NewConversation(); }
            else if (ctrl && key == Key.W && chatOn) { e.Handled = true; if (chatDir == ChatData.Main) ShowChat(false); else CloseTab(chatDir); }
            else if (ctrl && key == Key.Tab && chatOn) { e.Handled = true; var ds = ChatData.Dirs(); if (ds.Count > 1) { var i = ds.IndexOf(chatDir); SwitchChat(ds[((i + (shift ? -1 : 1)) + ds.Count) % ds.Count]); } }
            else if (ctrl && (key == Key.D0 || key == Key.NumPad0) && chatOn) { e.Handled = true; SetZoom(1); Say("Chat text size: normal."); }
        }
        // --test: the chat's messages (selectable documents, links only to what exists, copy buttons, attachments), editing,
        // find and the speed - dashboard.ps1's CHAT lines, with the same sample
        internal List<string> ChatSelfTest()
        {
            var o = new List<string>(); var win = Environment.GetEnvironmentVariable("SystemRoot") ?? @"C:\Windows";
            ChatList.Children.Clear();
            AddItem("text", $"## Head\nSee **{win}** and `{win}\\System32\\notepad.exe` or https://example.com/a.\nNot a link: `C:\\no\\such\\file.txt`\n```\n$x = 1\n```\n- point");
            AddItem("user", $"Look at this\nAttached: {win}\\win.ini");
            AddItem("user", "Just words"); o.Add($"CHAT PLAIN: {((RichTextBox)((Border)((DockPanel)ChatList.Children[ChatList.Children.Count - 1]).Children[1]).Child).Document.Blocks.Count} block");
            var reply = (StackPanel)ChatList.Children[0]; var doc = ((RichTextBox)reply.Children[0]).Document;
            var links = new List<string>(); int codeBoxes = 0; string code = "";
            foreach (var bl in doc.Blocks)
            {
                if (bl is Paragraph p) foreach (var i in p.Inlines) { if (i is Hyperlink h) links.Add(((ToolTip(h) ?? "").Replace("Open ", "").Replace("Show in File Explorer: ", ""))); else if (i is Span sp) foreach (var i2 in sp.Inlines) if (i2 is Hyperlink h2) links.Add((ToolTip(h2) ?? "").Replace("Show in File Explorer: ", "")); }
                else if (bl is BlockUIContainer bc) { codeBoxes++; code = ((TextBox)((Border)((Grid)bc.Child).Children[0]).Child).Text; }
            }
            o.Add($"CHAT: reply={reply.Children[0].GetType().Name} readonly={((RichTextBox)reply.Children[0]).IsReadOnly} blocks={doc.Blocks.Count} codeboxes={codeBoxes} code=[{code}] copy={((Button)reply.Children[1]).ToolTip}");
            o.Add("CHAT LINKS: " + string.Join(" | ", links));
            var ub = (DockPanel)ChatList.Children[1]; var udoc = ((RichTextBox)((Border)ub.Children[1]).Child).Document;
            var att = ((Paragraph)udoc.Blocks.LastBlock).Inlines.OfType<Hyperlink>().Select(h => (ToolTip(h) ?? "").Replace("Show in File Explorer: ", ""));
            o.Add($"CHAT USER: blocks={udoc.Blocks.Count} attach={string.Join(",", att)} width={(int)((RichTextBox)((Border)ub.Children[1]).Child).MaxWidth}");
            var hadLast = lastUser != null; lastUser = ub; StartEdit($"Fix this\nAttached: {win}\\win.ini"); o.Add($"CHAT EDIT: box=[{ChatInput.Text}] files={attach.Count} editing={editing} shown={ChatEditing.Visibility} last={hadLast}"); StopEdit(); ChatInput.Text = ""; ClearAttach();
            AddItem("text", "The **Head** again, and head once more"); FindInChat("head"); var n1 = finds.Count; var at1 = ChatFindCount.Text; StepFind(1); var at2 = ChatFindCount.Text;
            var marked = finds.Count(x => x.R.GetPropertyValue(TextElement.BackgroundProperty) is SolidColorBrush); ClearFinds();
            // (nothing left marked once the search closes)
            var fc = new[] { ((SolidColorBrush)FindBrush).Color, ((SolidColorBrush)FindCur).Color }; int left = 0;
            foreach (var rtb in ChatDocs()) for (var q = rtb.Document.ContentStart; q != null; q = q.GetNextContextPosition(LogicalDirection.Forward))
                    if (q.GetPointerContext(LogicalDirection.Forward) == TextPointerContext.Text && q.Parent is TextElement te && te.Background is SolidColorBrush sb && fc.Contains(sb.Color)) left++;
            o.Add($"CHAT FIND: found={n1} first=[{at1}] next=[{at2}] marked={marked} leftover={left}");
            var md = Path.Combine(Path.GetTempPath(), "app-mode-" + System.Diagnostics.Process.GetCurrentProcess().Id); Directory.CreateDirectory(md);
            var m0 = ChatData.Mode(md).Name; File.WriteAllText(Path.Combine(md, "mode.txt"), "opus/high"); var m1 = ChatData.Mode(md).Name; File.WriteAllText(Path.Combine(md, "mode.txt"), "junk"); var m2 = ChatData.Mode(md).Name; Directory.Delete(md, true);
            UpdateModeBtn(); o.Add($"CHAT MODE: default={m0} chosen={m1} junk={m2} button=[{(((ChatMode.Content as StackPanel)?.Children.OfType<TextBlock>().Skip(1).FirstOrDefault())?.Text)}]");
            ChatList.Children.Clear();
            // a tab's own name and pin (a scratch folder, not a real chat)
            var td = Path.Combine(Path.GetTempPath(), "app-tab-" + System.Diagnostics.Process.GetCurrentProcess().Id); Directory.CreateDirectory(td);
            SaveName(td, "  My   build chat  "); var t1 = ChatData.ChatTitle(td); var rc = Kit.FirstLine(Path.Combine(td, "name.txt")).Trim();
            SaveName(td, ""); var t2 = ChatData.ChatTitle(td);
            TogglePin(td); var p1 = File.Exists(Path.Combine(td, "pinned.txt")); CloseTab(td); var kept = Directory.Exists(td); TogglePin(td); var p2 = File.Exists(Path.Combine(td, "pinned.txt"));
            o.Add($"CHAT TAB: named=[{t1}] remote=[{rc}] cleared=[{t2}] pinned={p1} closeRefused={kept} unpinned={!p2}");
            try { Directory.Delete(td, true); } catch { }
            return o;
        }
        static string ToolTip(Hyperlink h) => h.ToolTip as string;

        // the tray asks for a chat to be shown (its "Claude finished" note): app-request.txt "chat=<tab>"
        void ReadChatRequest(string r)
        {
            var m = Regex.Match(r, @"^chat=([\w-]*)$"); if (!m.Success || snap == null || !snap.Ai) return;
            var d = m.Groups[1].Value != "" && Directory.Exists(Kit.P(@"chats\" + m.Groups[1].Value)) ? Kit.P(@"chats\" + m.Groups[1].Value) : ChatData.Main;
            if (ChatPanel.Visibility != Visibility.Visible) { chatDir = d; ShowChat(true); } else if (d != chatDir) SwitchChat(d);
        }
    }
}
