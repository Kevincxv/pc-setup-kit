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

Open **PowerShell** and run (it asks for administrator rights by itself):

```powershell
irm https://raw.githubusercontent.com/Kevincxv/pc-setup-kit/main/install.ps1 | iex
```

It shows what it will do and asks you to type `YES`. Setup takes 15-30 minutes: tweaks, apps, then it optimizes the
PC (monitors, drivers, app updates, checks, benchmark) and opens a report (`Documents\PC Setup Kit report.txt`) that
says what was done and anything that needs you.

With the optional Messiah (Claude):

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/Kevincxv/pc-setup-kit/main/install.ps1))) -WithClaude
```

## Install on a fresh Windows (USB)

Download the latest release (**Releases** on the right > Source code (zip)) and follow `README.txt`:
Microsoft's Media Creation Tool USB plus `autounattend.xml` and the `PCSetupKit` folder on the USB root.

## What you get

- **Windows cleanup**: bloat apps, ads, telemetry, Copilot/Recall/AI features, Bing in search, background tasks.
- **Gaming tweaks**: Ultimate Performance power plan, Game Mode, GPU scheduling, no Game DVR, no mouse acceleration,
  no power-saving on controllers/Ethernet, monitors at their highest refresh rate.
- **Zero maintenance**, hidden in the background after each login: drivers, app updates, crash detection with
  automatic dump diagnosis, antivirus/clock/TRIM checks, monthly cleanup and restore point, a benchmark every 3 months,
  dusting reminder every 6 months, full re-optimize yearly. It waits while you're gaming.
- **Decisions by fixed rules**: safe things are fixed right away (monitor refresh rate, leftovers of deleted programs,
  Windows version upgrades before end of support, a memory test after repeated blue screens); things only you can do
  (BIOS settings, cleaning, cables) become plain step-by-step items in the tray - and disappear once fixed.
- **Tray icon** (next to the clock): **Status** shows what needs you and what's scheduled; small alerts appear when
  something needs you (never over a game). **Optimize this PC now** re-runs the optimization anytime.
- **Automatic updates of the kit itself**: new releases install by themselves at login.
- **Self-testing**: weekly and after every update, the kit's test suite checks the maintenance scripts on the PC
  itself (in a sandbox - nothing changes).
- **With Messiah** (optional): a Claude Code session always ready in the tray, hidden Claude runs that handle the
  maintenance with judgment, and a daily self-improvement pass.

## Remove it

```powershell
C:\PCSetupKit\uninstall.ps1                 # removes the maintenance, tray, shortcuts (and Messiah if installed)
C:\PCSetupKit\uninstall.ps1 -RevertTweaks   # ...and puts the Windows settings back
```

Nothing is deleted outright: removed files are moved to `%USERPROFILE%\.claude\pc-setup-kit-removed-<date>`.
Installed apps (and with Messiah, your Claude conversations and account) stay.
