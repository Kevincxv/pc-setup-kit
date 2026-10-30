using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;

namespace Messiah.Pages
{
    // The connection while playing (10/25, the owner: "say when a bad match was the network rather than the PC"):
    // game-perf.ps1 pings the router and the internet through each measured minute (netPing, netJitter, netLoss,
    // netSpikes, gwPing, gwLoss, wifi); network-check.ps1 measures the same at idle at every check (net-history.json).
    // A session says network or PC; the Connection card says what the line does while you play, and what helps.
    static class Connection
    {
        internal static double? Idle;   // the internet ping at idle, the median of the last 30 days (Performance.Build sets it)
        internal static double? IdleOf(List<Dictionary<string, object>> net)
        {
            var v = net.Where(r => Kit.Date(Json.Get(r, "date")) > DateTime.Now.AddDays(-30)).Select(r => Json.N(r, "ping")).Where(x => x != null).Select(x => x.Value).OrderBy(x => x).ToList();
            return v.Count >= 3 ? v[v.Count / 2] : (double?)null;
        }
        // a minute's connection was bad: packets lost, lag spikes, an unsteady line, or the ping well over idle
        internal static bool Bad(Dictionary<string, object> r, double? idle) =>
            (Json.N(r, "netLoss") ?? 0) >= 2 || (Json.N(r, "netSpikes") ?? 0) >= 3 || (Json.N(r, "netJitter") ?? 0) >= 15 || (Json.N(r, "gwLoss") ?? 0) >= 2 ||
            (idle != null && Json.N(r, "netPing") is double p && p >= idle.Value + 30);

        // a session's line: the numbers and, when something was off, which one it was - the network or the PC
        internal static Line Session(Dictionary<string, object> r, bool pcBad)
        {
            var ping = Json.N(r, "netPing"); if (ping == null) return null;
            double loss = Json.N(r, "netLoss") ?? 0, spikes = Json.N(r, "netSpikes") ?? 0, jit = Json.N(r, "netJitter") ?? 0, gwLoss = Json.N(r, "gwLoss") ?? 0;
            var parts = new List<string> { $"ping {ping:0} ms" + (Idle != null ? $" ({Idle:0} at idle)" : "") };
            parts.Add(loss > 0 ? $"{loss}% of packets lost" : "no packets lost");
            if (spikes > 0) parts.Add($"{spikes:0} lag spike{(spikes == 1 ? "" : "s")}");
            if (jit >= 15) parts.Add($"unsteady (pings varied by {jit} ms)");
            var bad = Bad(r, Idle); var text = "Connection while playing: " + string.Join(", ", parts);
            if (!bad) return new Line(text + (pcBad ? " - fine, so the slow minute was the PC, not the network." : " - fine."), "dim");
            var where = gwLoss >= 2 ? "already on the way to the router - the cable or Wi-Fi" : Idle != null && ping >= Idle + 30 ? "the line filling up while the game uses it" : "past the router - the modem or the provider";
            return new Line(text + $" ({where}). " + (pcBad ? "Both the PC and the connection had a bad minute." : "The PC ran fine - if this match felt laggy, it was the connection, not the PC."), "warn");
        }

        // the card: what the line does while you play (all the measured minutes of 30 days), a chart, and what would help
        internal static UIElement Card(Snapshot s)
        {
            var rows = s.Perf.Where(r => Json.N(r, "netPing") != null && Kit.Date(Json.Get(r, "date")) > DateTime.Now.AddDays(-30)).ToList();
            if (rows.Count == 0) return null;
            var idle = IdleOf(s.Net); var pings = rows.Select(r => Json.N(r, "netPing").Value).OrderBy(x => x).ToList(); var med = pings[pings.Count / 2];
            int bad = rows.Count(r => Bad(r, idle)); var wifi = rows.Any(r => Json.B(r, "wifi"));
            double lossAvg = rows.Average(r => Json.N(r, "netLoss") ?? 0), gwLossAvg = rows.Average(r => Json.N(r, "gwLoss") ?? 0);
            var lines = new List<object>
            {
                new Line($"While you play: ping {med:0} ms{(idle != null ? $" ({idle:0} at idle)" : "")}, {(bad == 0 ? "no bad minutes" : $"{bad} of {rows.Count} measured minute{Kit.S(rows.Count)} with lag (lost packets or spikes)")} in the last 30 days.", bad > rows.Count / 4 ? "warn" : "info")
            };
            var grid = Ui.Pairs(new System.Windows.Controls.Primitives.UniformGrid { Columns = 2, Margin = Ui.Th("0,8,-14,0") });
            if (rows.Count >= 2) { var c = Charts.Chart("Ping while playing", " ms", Performance.Points(rows, "netPing", s.Tune, true), 0, 10, hint: false); ((FrameworkElement)c).Margin = Ui.Th("0,0,14,14"); grid.Children.Add(c); }
            var idleRows = s.Net.Where(r => Json.N(r, "ping") != null && Kit.Date(Json.Get(r, "date")) > DateTime.Now.AddDays(-30)).Select(r => (Kit.Date(Json.Get(r, "date")).Value, Json.N(r, "ping").Value)).ToList();
            if (idleRows.Count >= 2) { var c = Activity.Chart("Ping at idle (each check)", " ms", idleRows, 0, 10); c.Margin = Ui.Th("0,0,14,14"); grid.Children.Add(c); }
            if (grid.Children.Count > 0) lines.Add(grid);
            // what would help - only what the numbers point at
            var tips = new List<Line>();
            if (wifi) tips.Add(new Line("You play on Wi-Fi - a network cable is the biggest single fix for lag spikes and lost packets.", "warn"));
            if (idle != null && med >= idle + 20) tips.Add(new Line($"Lag builds up while the line is busy (ping {med - idle:0} ms higher while playing). Turn on your router's QoS / SQM (often called Smart Queue, Adaptive QoS or bufferbloat control) and give this PC priority, and pause big downloads - Steam, Windows Update, cloud backups - while you play.", "warn"));
            if (gwLossAvg >= 1) tips.Add(new Line("Packets are lost on the way to the router - try another cable or router port" + (wifi ? ", or move closer to the router." : "."), "warn"));
            else if (lossAvg >= 1) tips.Add(new Line("Packets are lost past the router (the home network is fine) - restart the modem; if it keeps happening it's the provider.", "warn"));
            var last = s.Net.LastOrDefault();
            if (last != null && Json.N(last, "dns") is double dns)
                tips.Add(new Line($"Name lookups (DNS, {Json.S(last, "dnsServer")}): {dns:0} ms" + (Json.N(last, "dnsBest") is double best ? $", the fastest public one {best:0} ms" : "") + (Json.S(s.Net.LastOrDefault(r => Json.S(r, "dnsSet") != ""), "dnsSet") == "public" ? " - Messiah switched to it because the router's was slow." : " - checked at every check; a slow one is switched by itself."), "dim"));
            if (tips.Count(t => t.Level == "warn") == 0) tips.Insert(0, new Line("Your connection is fine for games - lag in a match is the game's server, not your line or your PC.", "ok"));
            lines.AddRange(tips);
            lines.Add(new Line("Measured with pings only (no downloads, no data use): to your router and to the internet, every half second through each measured minute of play.", "dim"));
            return Ui.Card("Connection", "E701", lines);
        }
    }
}
