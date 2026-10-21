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
            foreach (var part in Regex.Split(t, @"(\*\*[^*]+\*\*|`[^`]+`)"))
            {
                if (part == "") continue;
                var bm = Regex.Match(part, @"^\*\*(.+)\*\*$"); var cm = Regex.Match(part, "^`(.+)`$");
                if (bm.Success) { var sp = new Span { FontWeight = FontWeights.SemiBold }; AddPlain(sp.Inlines, bm.Groups[1].Value); to.Add(sp); }
                else if (cm.Success) { var x = cm.Groups[1].Value; if (IsTarget(x)) to.Add(Link(x, x, true)); else to.Add(new Run(x) { FontFamily = Theme.Mono, FontSize = 12.5, Background = B("Seg") }); }
                else AddPlain(to, part);
            }
        }
        // a document that can be selected but not edited (the chat's own scrolling and Ctrl+wheel zoom: ChatScroll)
        public static RichTextBox Doc() => new RichTextBox
        {
            Document = new FlowDocument { PagePadding = new Thickness(0), FontFamily = Theme.TextFont, FontSize = 14, Foreground = B("Text"), TextAlignment = TextAlignment.Left },
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
            System.Collections.Generic.List<string> code = null;
            foreach (var l in (md ?? "").Replace("\r", "").Split('\n'))
            {
                if (Regex.IsMatch(l, @"^\s*```"))
                {
                    if (code != null)
                    {   // a code block: its own box with a copy button
                        var ct = string.Join("\n", code);
                        var g = new Grid { Margin = Ui.Th("0,4,0,6") };
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
                if (l.Trim() == "") continue;
                var p = new Paragraph { Margin = Ui.Th("0,2,0,4") };
                var h = Regex.Match(l, @"^\s*#{1,4}\s+(.*)"); var bu = Regex.Match(l, @"^(\s*)[-*]\s+(.*)"); var nu = Regex.Match(l, @"^(\s*)(\d+[.)])\s+(.*)");
                if (h.Success) { AddInlines(p.Inlines, h.Groups[1].Value); p.FontWeight = FontWeights.SemiBold; p.FontSize = 15; p.Margin = Ui.Th("0,6,0,4"); }
                else if (bu.Success) { p.Margin = new Thickness(8 + 14 * Math.Min(3, (int)Math.Round(bu.Groups[1].Value.Length / 2.0)), 1, 0, 3); p.Inlines.Add(new Run("•  ")); AddInlines(p.Inlines, bu.Groups[2].Value); }
                else if (nu.Success) { p.Margin = Ui.Th("8,1,0,3"); p.Inlines.Add(new Run(nu.Groups[2].Value + "  ")); AddInlines(p.Inlines, nu.Groups[3].Value); }
                else AddInlines(p.Inlines, l);
                doc.Blocks.Add(p);
            }
            if (code != null) doc.Blocks.Add(new Paragraph(new Run(string.Join("\n", code))) { FontFamily = Theme.Mono, FontSize = 12 });   // (a block still being written)
            return rtb;
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
