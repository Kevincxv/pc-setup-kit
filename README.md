# PC Setup Kit

Turns a Windows 11 PC into a tuned, debloated gaming PC **that then maintains itself** - drivers, updates, crash
detection, cleanup and scheduled checks - with plain scripts. **No AI and no account needed:** one command (or one USB
install) and it's done. You only do physical things (dusting, BIOS clicks), and only when the tray tells you how.

Optional: **Messiah**, a Claude Code setup on top, for people who want an AI assistant with admin rights on their PC.

> **Read this first**
> - Memory integrity (VBS) is turned **off** for gaming performance (a small security trade-off).
> - The kit never shuts down or restarts your PC; anything that needs a restart finishes the next time you turn it off.
> - With the optional Messiah: it runs Claude Code **without permission prompts**, as administrator, and needs
>   **your own Claude account** (Pro or higher). Only add it if you're OK with that.

## Install on an existing Windows 11 PC

**Easiest:** open the install page, **https://kevincxv.github.io/pc-setup-kit/**, and click the download button. Open the
file; if Windows says "Windows protected your PC", click **More info > Run anyway** (the file isn't signed by a paid
certificate). Afterwards the tray icon next to the clock and **PC Setup Kit Status** in the Start menu show what the PC
is doing.

Or open **PowerShell** and run (it asks for administrator rights by itself):

```powershell
irm https://github.com/Kevincxv/pc-setup-kit/releases/latest/download/install.ps1 | iex
```

It shows what it will do and asks you to type `YES`. Setup takes 15-30 minutes: tweaks, apps, then it optimizes the
PC (monitors, drivers, app updates, checks, benchmark), then the app - **Messiah** - opens on a welcome page with what
was done (the full report: `Documents\PC Setup Kit report.txt`).

It's one app with or without AI: the AI assistant (Claude, your own account) is a switch in its Settings. To have it on
from the start:

```powershell
& ([scriptblock]::Create((irm https://github.com/Kevincxv/pc-setup-kit/releases/latest/download/install.ps1))) -WithClaude
```

## Install on a fresh Windows (USB)

Download the latest release (**Releases** on the right > Source code (zip)) and follow `README.txt`:
Microsoft's Media Creation Tool USB plus `autounattend.xml` and the `PCSetupKit` folder on the USB root.

## What you get

- **Windows cleanup**: bloat apps, ads, telemetry, Copilot/Recall/AI features, Bing in search, background tasks.
- **Gaming tweaks**: Ultimate Performance power plan, Game Mode, GPU scheduling, no Game DVR, no mouse acceleration,
  no power-saving on controllers/Ethernet, every monitor at its native resolution and highest refresh rate (also one plugged in later).
- **Zero maintenance**, hidden in the background after each login: drivers, app updates, crash detection with
  automatic dump diagnosis, antivirus/clock/TRIM checks, monthly cleanup and restore point, a benchmark every 3 months,
  dusting reminder every 6 months, full re-optimize yearly. It waits while you're gaming.
- **More gaming settings**: Windows' "optimizations for windowed games" and variable refresh rate, NVIDIA low-latency
  mode and an unlimited shader cache (once per driver), no Windows Update restarts while you're signed in, the page
  file kept on, laptops kept on Balanced with full speed when plugged in. AMD dual-CCD X3D CPUs keep the Xbox Game Bar
  and AMD's V-Cache optimizer (they need them to put games on the right cores). Reminders for Resizable BAR off, games
  on a hard drive and the hypervisor running. Optional: Defender skips the game folders (the app's Settings).
- **Games, measured while you play**: a minute of each game's real frame rate (average and 1% lows, via Intel's
  PresentMon) plus the graphics card's temperature and throttling - so "the last driver or Windows update made my games
  slower" and "it runs hot while gaming" get noticed and named. Graphics driver resets (a freeze or black screen for a
  moment) are counted too, and old shader caches are cleared once after each driver update.
- **Network**: ping, jitter, packet loss and DNS speed over time (no speed tests, no data use); a slow router DNS on a
  wired connection is switched to a fast public one by itself.
- **Settings backup**: weekly, the look (wallpaper, dark mode, accent colour, taskbar, mouse, Start pins), game
  settings and the kit's own memory go to a second drive (or the kit USB, or Documents). Reinstalling Windows with the
  kit on the same PC brings them back by themselves - never onto a different PC.
- **Decisions by fixed rules**: safe things are fixed right away (monitor refresh rate, leftovers of deleted programs,
  Windows version upgrades before end of support, a memory test after repeated blue screens); things only you can do
  (BIOS settings, cleaning, cables) become plain step-by-step items in the tray - and disappear once fixed.
- **Tray icon** (next to the clock) and **the app**: status, what needs you, what's scheduled, and a **History** page (start-up time, disk space, temperatures, frame rates, ping over time); small alerts appear when
  something needs you (never over a game). **Optimize this PC now** re-runs the optimization anytime.
- **Automatic updates of the kit itself**: a new release installs within 4 hours (and at every login), without a restart, only once it passed every test and fresh install. Its self-test runs right away; a release that fails on a PC goes back to the version before by itself. Each release is checked to be accepted by the updaters of the last 10 releases, so PCs that fell behind catch up in one step.
- **Your choice, per change**: the app's Settings > "What the kit changes" lists every change with a plain explanation and a switch (memory integrity, OneDrive, Xbox Game Bar, telemetry, power plan, mouse acceleration, ...). Turning one off puts back what it changed and the guard keeps to it after updates.
- **Easy to live with**: a note after each kit update saying what's new, a weekly one-line summary, Pause maintenance (tray menu) for a stream or a tournament, "Remind me in a week" and a direct "fix it" button on to-do items, Repair / Undo the last update, back up or restore your settings by hand, and Ctrl+Alt+P (Ctrl+Alt+M with Messiah) to open the app from anywhere.- **Settings stay optimized**: 2 minutes after every Windows Update or driver install, everything an update can undo (settings, services, removed apps, the power plan, OneDrive, monitors, NVIDIA settings) is put back.
- **Self-testing**: weekly and after every update, the kit's test suite checks the maintenance scripts on the PC
  itself (in a sandbox - nothing changes).
- **Hands-off extras**: on Dell, HP and Lenovo Think* PCs the maker's own tool installs BIOS, firmware and drivers
  weekly; AMD Radeon cards get AMD's newest driver (like NVIDIA's); pending updates finish with a restart at night while
  nobody uses the PC (a switch; 5-minute warning, Cancel restart in the tray); an unused hypervisor is turned off;
  junk that came with the PC is removed (trial antivirus: one click); your files are copied to a second drive by itself
  once you pick it.
- **One-click fixes**: go back to the previous graphics driver (Maintenance page; the newer one is held back), uninstall
  from Settings, big Windows upgrades wait 45 days (security updates don't), and on laptops with two graphics chips
  every game is set to the fast one.
- **AI assistant** (optional, a switch in Settings): a Claude Code session always ready in the tray, hidden Claude runs that handle the
  maintenance with judgment, and a daily self-improvement pass.

## Remove it

```powershell
C:\PCSetupKit\uninstall.ps1                 # removes the maintenance, tray, shortcuts (and Messiah if installed)
C:\PCSetupKit\uninstall.ps1 -RevertTweaks   # ...and puts the Windows settings back
```

Nothing is deleted outright: removed files are moved to `%USERPROFILE%\.claude\pc-setup-kit-removed-<date>`.
Installed apps (and with Messiah, your Claude conversations and account) stay.

License: MIT. Code signing policy: https://kevincxv.github.io/pc-setup-kit/code-signing.html
