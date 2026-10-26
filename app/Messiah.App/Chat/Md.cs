using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;

namespace Messiah.Chat
{
    // Markdown, simply: paragraphs, bullets, headings, code blocks, **bold** and `code` - in a read-only document, so the
    // text can be selected and copied (Ctrl+C, right-click); web addresses and files that exist are links
    // (dashboard.ps1's New-Md, Add-Inlines, Add-Plain, New-Link, New-ChatDoc, New-CopyBtn)
    static class Md
    {
        static SolidColorBrush B(string k) => Theme.B[k];
        public static readonly Regex LinkRx = new Regex(@"(https?://[^\s<>""`]*[^\s<>""`.,;:!?)\]]|[A-Za-z]:\\[^\s<>""`|*?]*[^\s<>""`|*?.,;:!?)\]])");
        static string LinkPath(string t) => Regex.Replace(t, @":\d+(:\d+)?$", "");   // (file.ps1:42 - the file)
        public static bool IsTarget(string t)
        {
            if (Regex.IsMatch(t, @"^https?://\S+$")) return true;
            if (!Regex.IsMatch(t, @"^[A-Za-z]:\\")) return false;
            try { var p = LinkPath(t); return File.Exists(p) || Directory.Exists(p); } catch { return false; }
        }
        // a link: web addresses open in the browser, folders in Explorer, files selected in Explorer (never run)
        public static void OpenTarget(string t)
        {
            if (Regex.IsMatch(t, "^https?://")) { Actions.Open(t); return; }
            var p = LinkPath(t);
            if (Directory.Exists(p)) Actions.Open("explorer.exe", $"\"{p}\"");
            else if (File.Exists(p)) Actions.Open("explorer.exe", $"/select,\"{p}\"");
            else Shell.Say($"Can't find {p} any more.");
        }
        public static Hyperlink Link(string text, string target, bool code = false)
        {
            var h = new Hyperlink(new Run(text)) { Foreground = B("Accent"), Cursor = System.Windows.Input.Cursors.Hand, ToolTip = Regex.IsMatch(target, "^https?://") ? "Open " + target : "Show in File Explorer: " + target };
            if (code) { h.FontFamily = Theme.Mono; h.FontSize = 12.5; }
            h.Click += (s, e) => { try { OpenTarget(target); } catch (Exception ex) { Shell.Say("Couldn't open it: " + ex.Message); } };
            return h;
        }
        public static void AddPlain(InlineCollection to, string t)
        {
            var parts = LinkRx.Split(t);
            for (int i = 0; i < parts.Length; i++) { if (parts[i] == "") continue; if (i % 2 == 1 && IsTarget(parts[i])) to.Add(Link(parts[i], parts[i])); else to.Add(new Run(parts[i])); }
        }
        static void AddInlines(InlineCollection to, string t)
        {
            foreach (var part in Regex.Split(t, @"(\*\*[^*]+\*\*|`[^`]+`|\[[^\]\n]+\]\((?:https?://|[A-Za-z]:\\)[^)\s]+\))"))
            {
                if (part == "") continue;
                var bm = Regex.Match(part, @"^\*\*(.+)\*\*$"); var cm = Regex.Match(part, "^`(.+)`$"); var lm = Regex.Match(part, @"^\[(.+)\]\((.+)\)$");
                if (lm.Success) { if (IsTarget(lm.Groups[2].Value)) to.Add(Link(lm.Groups[1].Value, lm.Groups[2].Value)); else to.Add(new Run(lm.Groups[1].Value)); }   // ([words](address): the words, a link)
                else if (bm.Success) { var sp = new Span { FontWeight = FontWeights.SemiBold }; AddPlain(sp.Inlines, bm.Groups[1].Value); to.Add(sp); }
                else if (cm.Success) { var x = cm.Groups[1].Value; if (IsTarget(x)) to.Add(Link(x, x, true)); else to.Add(new Run(x) { FontFamily = Theme.Mono, FontSize = 12.5, Background = B("Seg") }); }
                else AddPlain(to, part);
            }
        }
        // a document that can be selected but not edited (the chat's own scrolling and Ctrl+wheel zoom: ChatScroll)
        public static RichTextBox Doc() => new RichTextBox
        {
            Document = new FlowDocument { PagePadding = new Thickness(0), FontFamily = Theme.TextFont, FontSize = 14, Foreground = B("Text"), TextAlignment = TextAlignment.Left, LineHeight = 21 },   // (1.5 lines: 10/25, easier to read)
            IsReadOnly = true, IsDocumentEnabled = true, Background = Brushes.Transparent, BorderThickness = new Thickness(0), Padding = new Thickness(0), Foreground = B("Text"),
            FocusVisualStyle = null, SelectionBrush = B("Accent"), VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled
        };
        public static void Copy(string t, string said = "Copied.") { try { Clipboard.SetText(t); Shell.Say(said); } catch (Exception e) { Shell.Say("Couldn't copy: " + e.Message); } }
        public static Button CopyBtn(string text, string tip)
        {
            var b = Ui.IconBtn("E8C8", tip, null); b.Padding = Ui.Th("6,4"); b.Margin = new Thickness(0); ((TextBlock)b.Content).FontSize = 12;
            b.Click += (s, e) => { e.Handled = true; Copy(text); };
            return b;
        }
        public static RichTextBox Render(string md)
        {
            var rtb = Doc(); var doc = rtb.Document;
            System.Collections.Generic.List<string> code = null, rows = null; var lists = new System.Collections.Generic.List<(int Ind, List L)>();
            foreach (var l in (md ?? "").Replace("\r", "").Split('\n'))
            {
                if (Regex.IsMatch(l, @"^\s*```"))
                {
                    if (rows != null) { doc.Blocks.Add(Table(rows)); rows = null; }
                    lists.Clear();
                    if (code != null)
                    {   // a code block: its own box with a copy button
                        var ct = string.Join("\n", code);
                        var g = new Grid { Margin = Ui.Th("0,2,0,12") };
                        var cb = new Border { Background = B("Seg"), CornerRadius = new CornerRadius(6), Padding = Ui.Th("10,8,36,8") };
                        cb.Child = new TextBox { Text = ct, IsReadOnly = true, FontFamily = Theme.Mono, FontSize = 12, TextWrapping = TextWrapping.Wrap, Foreground = B("Text"), Background = Brushes.Transparent, BorderThickness = new Thickness(0), Padding = new Thickness(0), SelectionBrush = B("Accent"), FocusVisualStyle = null, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled };
                        g.Children.Add(cb);
                        var cp = CopyBtn(ct, "Copy this"); cp.HorizontalAlignment = HorizontalAlignment.Right; cp.VerticalAlignment = VerticalAlignment.Top; cp.Margin = Ui.Th("0,4,4,0"); g.Children.Add(cp);
                        doc.Blocks.Add(new BlockUIContainer(g)); code = null;
                    }
                    else code = new System.Collections.Generic.List<string>();
                    continue;
                }
                if (code != null) { code.Add(l); continue; }
                // a table (| a | b |): rows of cells, the |---| line under the head left out, the head bold
                if (Regex.IsMatch(l, @"^\s*\|.*\|\s*$")) { lists.Clear(); (rows = rows ?? new System.Collections.Generic.List<string>()).Add(l); continue; }
                if (rows != null) { doc.Blocks.Add(Table(rows)); rows = null; }
                if (l.Trim() == "") continue;   // (a list goes on past a blank line - Markdown's loose list)
                var h = Regex.Match(l, @"^\s*(#{1,4})\s+(.*)"); var bu = Regex.Match(l, @"^(\s*)[-*+]\s+(.*)"); var nu = Regex.Match(l, @"^(\s*)(\d+)[.)]\s+(.*)");
                if (bu.Success || nu.Success) { AddItem(doc, lists, (bu.Success ? bu : nu).Groups[1].Value.Length, nu.Success && !bu.Success ? int.Parse(nu.Groups[2].Value) : 0, bu.Success ? bu.Groups[2].Value : nu.Groups[3].Value); continue; }
                lists.Clear();
                if (Regex.IsMatch(l, @"^\s*(-{3,}|\*{3,}|_{3,})\s*$"))   // --- : a thin line between parts
                { doc.Blocks.Add(new BlockUIContainer(new Border { Height = 1, Background = B("Border"), Margin = Ui.Th("0,6,0,12") })); continue; }
                var p = new Paragraph { Margin = Ui.Th("0,0,0,10") };
                var q = Regex.Match(l, @"^\s*>\s?(.*)");
                if (h.Success)
                {   // a heading: bigger, room above it so the parts of a reply stand apart
                    AddInlines(p.Inlines, h.Groups[2].Value); p.FontWeight = FontWeights.SemiBold; p.FontFamily = Theme.Display;
                    p.FontSize = h.Groups[1].Value.Length <= 2 ? 17 : 15; p.LineHeight = 24; p.Margin = Ui.Th(doc.Blocks.Count == 0 ? "0,0,0,6" : "0,14,0,6");
                }
                else if (q.Success) { AddInlines(p.Inlines, q.Groups[1].Value); p.Foreground = B("Sub"); p.BorderBrush = B("Accent"); p.BorderThickness = new Thickness(3, 0, 0, 0); p.Padding = Ui.Th("12,2,0,2"); }   // > a quote
                else AddInlines(p.Inlines, l);
                doc.Blocks.Add(p);
            }
            if (rows != null) doc.Blocks.Add(Table(rows));
            if (code != null) doc.Blocks.Add(new Paragraph(new Run(string.Join("\n", code))) { FontFamily = Theme.Mono, FontSize = 12 });   // (a block still being written)
            return rtb;
        }
        // a bullet or numbered point: real lists (10/25: a wrapped line went back under the dot - now it hangs under the
        // words), one inside another by its indent; num 0 = a bullet
        static void AddItem(FlowDocument doc, System.Collections.Generic.List<(int Ind, List L)> lists, int ind, int num, string text)
        {
            var kind = num > 0 ? TextMarkerStyle.Decimal : TextMarkerStyle.Disc;
            while (lists.Count > 0 && lists[lists.Count - 1].Ind > ind) lists.RemoveAt(lists.Count - 1);
            if (lists.Count > 0 && lists[lists.Count - 1].Ind == ind && lists[lists.Count - 1].L.MarkerStyle != kind) lists.RemoveAt(lists.Count - 1);
            if (lists.Count == 0 || lists[lists.Count - 1].Ind < ind)
            {
                var L = new List { MarkerStyle = kind, MarkerOffset = 8, Padding = new Thickness(num > 0 ? 26 : 22, 0, 0, 0), Margin = Ui.Th(lists.Count == 0 ? "0,0,0,10" : "0,4,0,0") };
                if (num > 0) L.StartIndex = num;
                if (lists.Count == 0) doc.Blocks.Add(L); else { var parent = lists[lists.Count - 1].L; if (parent.ListItems.LastListItem != null) parent.ListItems.LastListItem.Blocks.Add(L); else doc.Blocks.Add(L); }
                lists.Add((ind, L));
            }
            var p = new Paragraph { Margin = Ui.Th("0,0,0,5") }; AddInlines(p.Inlines, text);
            lists[lists.Count - 1].L.ListItems.Add(new ListItem(p));
        }
        static Table Table(System.Collections.Generic.List<string> lines)
        {
            var cells = lines.Where(l => !Regex.IsMatch(l, @"^\s*\|[\s:|-]+\|\s*$")).Select(l => l.Trim().Trim('|').Split('|').Select(c => c.Trim()).ToArray()).ToList();
            var t = new Table { CellSpacing = 0, Margin = Ui.Th("0,2,0,12"), BorderBrush = B("Border"), BorderThickness = new Thickness(1, 1, 0, 0) };
            var n = cells.Count == 0 ? 0 : cells.Max(r => r.Length); for (int i = 0; i < n; i++) t.Columns.Add(new TableColumn());
            var g = new TableRowGroup(); t.RowGroups.Add(g);
            for (int r = 0; r < cells.Count; r++)
            {
                var row = new TableRow(); if (r == 0) { row.FontWeight = FontWeights.SemiBold; row.Background = B("Seg"); }
                for (int c = 0; c < n; c++)
                {
                    var p = new Paragraph { Margin = new Thickness(0), FontSize = 13 }; AddInlines(p.Inlines, c < cells[r].Length ? cells[r][c] : "");
                    row.Cells.Add(new TableCell(p) { Padding = Ui.Th("8,4"), BorderBrush = B("Border"), BorderThickness = new Thickness(0, 0, 1, 1) });
                }
                g.Rows.Add(row);
            }
            return t;
        }
        // a bubble only as wide as its longest line (a document would always fill the chat)
        public static double Width(System.Collections.Generic.IEnumerable<string> lines)
        {
            var tf = new Typeface(Theme.TextFont, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal); double max = 0;
#pragma warning disable CS0618
            foreach (var s in lines) if (!string.IsNullOrEmpty(s)) max = Math.Max(max, new FormattedText(s, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, tf, 14.0, B("Text")).WidthIncludingTrailingWhitespace);
#pragma warning restore CS0618
            return max;
        }
    }
}
