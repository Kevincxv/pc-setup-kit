using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Messiah
{
    // where the window was: the page (tab/sub-page) and the Status rows left open - it opens there next time
    // (app-last.txt "page=" / "open=a|b"; not kit-options.txt: a change there redraws the page). The PowerShell app's chat
    // lines ("chattab=", "chatzoom=") are kept as they are.
    static class AppLast
    {
        public static string Page = "", ChatTab = ""; public static double ChatZoom = 1;
        public static readonly HashSet<string> OpenRows = new HashSet<string>();
        static string F => Kit.P(App.Names.LastFile);
        public static void Load()
        {
            foreach (var l in Kit.Lines(F))
            {
                if (l.StartsWith("page=")) Page = l.Substring(5).Trim();
                else if (l.StartsWith("chattab=")) ChatTab = l.Substring(8).Trim();
                else if (l.StartsWith("chatzoom=") && double.TryParse(l.Substring(9).Trim(), System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var z)) ChatZoom = z;
                else if (l.StartsWith("open=")) foreach (var t in l.Substring(5).Split('|').Where(x => x.Trim() != "")) OpenRows.Add(t);
            }
        }
        public static void Save()
        {
            if (Kit.InTests) return;
            try
            {
                var keep = Kit.Lines(F).Where(l => !l.StartsWith("page=") && !l.StartsWith("open=") && !l.StartsWith("chattab=") && !l.StartsWith("chatzoom=")).ToList();
                File.WriteAllLines(F, new[] { "page=" + Page, "open=" + string.Join("|", OpenRows), "chattab=" + ChatTab, "chatzoom=" + ChatZoom.ToString(System.Globalization.CultureInfo.InvariantCulture) }.Concat(keep));
            }
            catch { }
        }
    }
}
