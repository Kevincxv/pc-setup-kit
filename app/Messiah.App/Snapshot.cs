using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Messiah
{
    // Everything a page shows, read in the background in one go (dashboard.ps1 read it while building the page, on the
    // window's thread - 1.4 s for Home). The page is built from this; a new snapshot that reads the same (Sig) redraws nothing.
    class Snapshot
    {
        public bool Ai; public List<Section> Secs; public StatusModel Sm; public string Playing;
        public Dictionary<string, object> WhatsNew; public DateTime? Paused; public List<Data.PowerEvent> Power; public List<Data.Change> Changes;
        public List<Line> Ram; public Dictionary<string, object> PerfLast, HealthLast;
        public List<Dictionary<string, object>> Health, Perf, Net; public List<(string When, string Text)> Timeline; public List<(DateTime When, string Text)> Notes; public Dictionary<string, object> Chat; public string KitVersion;
        public List<Line> Since; public DateTime? SinceAt; public Data.Gpu Gpu; public Data.Bios Bios; public System.IO.FileInfo LastBackup; public Dictionary<string, object> GameSaves, Tune, GpuState; public string PrevVersion; public DateTime? KitSince;
        public string Sig;

        public Section Sec(string title) => Secs.FirstOrDefault(s => s.Title.StartsWith(title));

        public static Snapshot Load(DateTime? checkingSince = null)
        {
            var s = new Snapshot { Ai = Kit.AiOn() };
            s.Secs = Data.KitStatus(s.Ai);
            s.Sm = StatusModel.Load(checkingSince);
            s.Playing = Data.Playing();
            s.WhatsNew = Data.WhatsNew();
            s.Paused = Data.PausedUntil();
            s.Power = Data.PowerEvents(); s.Changes = Data.PowerChanges();
            s.Ram = Data.RamTestNow();
            s.Health = Data.History(); s.Perf = Data.History("perf-history.json"); s.Net = Data.History("net-history.json");
            s.PerfLast = s.Perf.LastOrDefault(); s.HealthLast = s.Health.LastOrDefault();
            s.Timeline = Data.MaintTimeline(); s.Notes = Data.Notes();
            var st = Environment.GetEnvironmentVariable("PCKIT_SINCE_TEST"); s.SinceAt = Kit.InTests ? (DateTime.TryParse(st, out var sd) ? sd : (DateTime?)null) : Shell.SeenBefore;
            s.Since = Data.SinceLast(s.SinceAt);
            s.Chat = s.Ai ? Data.ChatState() : null;
            s.KitVersion = Kit.FirstLine(System.IO.Path.Combine(Kit.KitDir, "kit-version.txt")); s.KitSince = Kit.Stamp(System.IO.Path.Combine(Kit.KitDir, "kit-version.txt"));
            s.PrevVersion = Kit.FirstLine(System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), @"PCSetupKit\previous\version.txt"));
            s.Gpu = Data.GraphicsDriver(); s.Bios = Data.BiosInfo(); s.LastBackup = Data.LastSettingsBackup(); s.GameSaves = Kit.ReadJson(Kit.P("game-saves.json"));
            s.Tune = Kit.ReadJson(Kit.P("game-tune.json")); s.GpuState = Kit.ReadJson(Kit.P("gpu-state.json"));   // (Performance: the settings being tried, a driver on test)
            var sb = new StringBuilder();
            foreach (var sec in s.Secs) { sb.Append(sec.Title).Append('\n'); foreach (var l in sec.Lines) sb.Append(l.Level).Append('|').Append(l.Text).Append('\n'); }
            foreach (var r in s.Sm.Rows) sb.Append(r.Level).Append(r.State).Append(r.Detail).Append('\n');
            foreach (var f in new[] { "health-history.json", "notifications.log", "maint-history", "kit-options.txt", "tweak-status.json", "guard-state.json", "diag-state.json", "whats-new.json", "power-log.json", "ram-test.log", "perf-history.json", "game-saves.json", "gpu-hold.txt", "game-tune.json", "gpu-state.json" })
                sb.Append(Kit.Stamp(Kit.P(f))?.Ticks).Append(',');
            foreach (var l in s.Since) sb.Append(l.Text).Append('\n');
            sb.Append('\n').Append(s.Playing).Append('\n').Append(Json.B(s.Chat, "busy")).Append(Json.S(s.Chat, "step"));
            s.Sig = sb.ToString();
            return s;
        }
    }
}
