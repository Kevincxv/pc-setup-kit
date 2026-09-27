# PC Setup Kit

Turns a Windows 11 PC into a tuned, debloated gaming PC and installs **Claude (Admin)**, a Claude Code setup that
then maintains the PC by itself: drivers, updates, crash diagnosis, cleanup, and scheduled hardware checks.
You only do physical things (dusting, BIOS clicks) when it asks.

> **Read this first**
> - Claude (Admin) runs Claude Code **without permission prompts**, as administrator. Only install it if you're OK with that.
> - You need **your own Claude account** (Pro or higher). The hidden maintenance uses that account's usage.
> - Memory integrity (VBS) is turned **off** for gaming performance (a small security trade-off).
> - Claude never shuts down or restarts your PC; anything that needs a restart finishes the next time you turn it off.

## Install on an existing Windows 11 PC

Open **PowerShell** and run (it asks for administrator rights by itself):

```powershell
irm https://raw.githubusercontent.com/Kevincxv/pc-setup-kit/main/install.ps1 | iex
```

It shows what it will do and asks you to type `YES`. Setup takes 10-20 minutes; then Claude (Admin) opens,
you log in with your Claude account, and it runs the `/pc-optimize` playbook (updates, drivers, hardware audit,
benchmark) and guides you through any BIOS steps.

## Install on a fresh Windows (USB)

Download the latest release (**Releases** on the right > Source code (zip)) and follow `README.txt`:
Microsoft's Media Creation Tool USB plus `autounattend.xml` and the `PCSetupKit` folder on the USB root.

## What you get

- **Windows cleanup**: bloat apps, ads, telemetry, Copilot/Recall/AI features, Bing in search, background tasks.
- **Gaming tweaks**: Ultimate Performance power plan, Game Mode, GPU scheduling, no Game DVR, no mouse acceleration,
  no power-saving on controllers/Ethernet.
- **Tray icon** (next to the clock): a Claude (Admin) session is always open hidden there; right-click > **Status**
  shows what needs you and what's scheduled. Small alerts appear when something needs you (never over a game).
- **Zero maintenance**, hidden in the background after each login: drivers, app updates, crash detection with
  automatic dump diagnosis, antivirus/clock/TRIM checks, monthly cleanup and restore point, BIOS/firmware checks
  every 3 months, dusting reminder every 6 months, full re-audit yearly. It waits while you're gaming.
- **Automatic updates of the kit itself**: new releases install by themselves at login.

## Remove it

```powershell
C:\PCSetupKit\uninstall.ps1                 # removes Claude (Admin), tray, maintenance, shortcuts
C:\PCSetupKit\uninstall.ps1 -RevertTweaks   # ...and puts the Windows settings back
```

Nothing is deleted outright: removed files are moved to `%USERPROFILE%\.claude\pc-setup-kit-removed-<date>`.
Your Claude conversations, account and installed apps stay.
