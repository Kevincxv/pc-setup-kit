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
        public List<Dictionary<string, object>> Health, Perf, Net; public List<(DateTime When, string Text)> Timeline; public List<(DateTime When, string Text)> Notes; public Dictionary<string, object> Chat; public string KitVersion;
        public List<Line> Since; public DateTime? SinceAt; public Data.Gpu Gpu; public Data.Bios Bios; public System.IO.FileInfo LastBackup; public Dictionary<string, object> GameSaves, Tune, GpuState, RamState; public List<Data.RamCheck> RamChecks; public Data.Session LastSession; public Dictionary<string, object> Fans; public List<Dictionary<string, object>> Bench; public bool BenchRunning; public Dictionary<string, object> Storage, StorageStatus; public string PrevVersion; public DateTime? KitSince;
        public string Sig, Times;   // (Times: each part's ms - --test DATA, the start-up timing)

        public Section Sec(string title) => Secs.FirstOrDefault(s => s.Title.StartsWith(title));

        public static Snapshot Load(DateTime? checkingSince = null)
        {
            var sw = System.Diagnostics.Stopwatch.StartNew(); var times = new List<string>(); void Lap(string part) { times.Add(part + " " + sw.ElapsedMilliseconds); sw.Restart(); }
            var s = new Snapshot { Ai = Kit.AiOn() };
            s.Secs = Data.KitStatus(s.Ai); Lap("status"); times[times.Count - 1] += $" ({Data.StatusTimes})";
            s.Sm = StatusModel.Load(checkingSince); Lap("checks"); times[times.Count - 1] += $" ({s.Sm.Times})";
            s.Playing = Data.Playing(); Lap("playing");
            s.WhatsNew = Data.WhatsNew();
            s.Paused = Data.PausedUntil(); Lap("news");
            s.Power = Data.PowerEvents(); s.Changes = Data.PowerChanges(); Lap("power");
            s.Ram = Data.RamTestNow(); Lap("ramtest");
            s.Health = Data.History(); s.Perf = Data.History("perf-history.json"); Data.LearnTitles(s.Perf); s.Net = Data.History("net-history.json"); Lap("history");
            s.PerfLast = s.Perf.LastOrDefault(); s.HealthLast = s.Health.LastOrDefault();
            s.Timeline = Data.MaintTimeline(); Lap("timeline"); s.Notes = Data.Notes(); Lap("notes");
            var st = Environment.GetEnvironmentVariable("PCKIT_SINCE_TEST"); s.SinceAt = Kit.InTests ? (DateTime.TryParse(st, out var sd) ? sd : (DateTime?)null) : Shell.SeenBefore;
            s.Since = Data.SinceLast(s.SinceAt); Lap("since");
            s.Chat = s.Ai ? Data.ChatState() : null; Lap("chat");
            s.KitVersion = Kit.FirstLine(System.IO.Path.Combine(Kit.KitDir, "kit-version.txt")); s.KitSince = Kit.Stamp(System.IO.Path.Combine(Kit.KitDir, "kit-version.txt"));
            s.PrevVersion = Kit.FirstLine(System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), @"PCSetupKit\previous\version.txt"));
            (s.Gpu, s.Bios) = Data.Hardware(); Lap("hardware"); s.LastBackup = Data.LastSettingsBackup(); s.GameSaves = Kit.ReadJson(Kit.P("game-saves.json")); Lap("backup");
            s.RamChecks = Data.RamChecks(); Lap("ramchecks"); s.LastSession = Data.LastSession(s.Perf); Lap("session"); s.Fans = Kit.ReadJson(Kit.P("fan-state.json")); s.Bench = Data.History("benchmarks.json"); s.BenchRunning = System.IO.File.Exists(Kit.P("bench-running.txt")) && System.IO.File.GetLastWriteTime(Kit.P("bench-running.txt")) > DateTime.Now.AddMinutes(-10); s.RamState = Kit.ReadJson(Kit.P("ram-check.json"));   // (Stability: the memory test)
            s.Tune = Kit.ReadJson(Kit.P("game-tune.json")); s.GpuState = Kit.ReadJson(Kit.P("gpu-state.json"));
            s.Storage = Kit.ReadJson(Kit.P("storage.json")); s.StorageStatus = Kit.ReadJson(Kit.P("storage-status.json"));   // (Games > Storage)   // (Performance: the settings being tried, a driver on test)
            Lap("files");
            var sb = new StringBuilder();
            foreach (var sec in s.Secs) { sb.Append(sec.Title).Append('\n'); foreach (var l in sec.Lines) sb.Append(l.Level).Append('|').Append(l.Text).Append('\n'); }
            foreach (var r in s.Sm.Rows) sb.Append(r.Level).Append(r.State).Append(r.Detail).Append('\n');
            foreach (var f in new[] { "health-history.json", "notifications.log", "maint-history", "kit-options.txt", "tweak-status.json", "guard-state.json", "diag-state.json", "whats-new.json", "power-log.json", "ram-test.log", "perf-history.json", "game-saves.json", "gpu-hold.txt", "game-tune.json", "gpu-state.json", "ram-check.json", "game-sessions.log", "fan-state.json", "benchmarks.json", "bench-running.txt", "storage.json", "storage-status.json", "improve-state.json", "claude-usage.json" })
                sb.Append(Kit.Stamp(Kit.P(f))?.Ticks).Append(',');
            foreach (var l in s.Since) sb.Append(l.Text).Append('\n');
            sb.Append('\n').Append(s.Playing).Append('\n').Append(Json.B(s.Chat, "busy")).Append(Json.S(s.Chat, "step")).Append('\n').Append(s.Gpu?.Version).Append(s.Bios?.Version);   // (the hardware arrives after the first read)
            s.Sig = sb.ToString(); Lap("sig"); s.Times = string.Join(", ", times);
            return s;
        }
    }
}
