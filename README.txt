PC SETUP KIT - fresh Windows 11 with all the tweaks + Messiah
======================================================================

WHAT YOU NEED
- A USB stick, 8 GB or bigger (it gets erased).
- Your friend's Windows license (new PCs usually have one built in; otherwise a product key).
- Your friend's own Claude account (Pro or higher) for Messiah. Never share yours.

MAKE THE USB (once, on any PC)
1. Download Microsoft's "Media Creation Tool" for Windows 11:
   https://www.microsoft.com/software-download/windows11  ->  "Create Windows 11 Installation Media"
2. Run it and choose "USB flash drive". Wait for it to finish.
3. Copy these two items from this folder to the ROOT of the USB (next to setup.exe):
     autounattend.xml
     PCSetupKit\   (the whole folder)

INSTALL ON THE NEW PC
1. Plug the USB into the new PC, turn it on, press the boot-menu key (F8/F11/F12 depending on the board) and pick the USB.
2. Setup asks for language/keyboard and the product key/edition ("I don't have a product key" is fine if the PC
   has a built-in license; pick the edition it came with, usually Home or Pro).
3. Setup asks WHERE to install. Pick the right drive and delete its old partitions if it's a fresh install.
   (Nothing is wiped automatically - this is the one screen to be careful on.)
4. After it restarts a few times: pick region/keyboard, Wi-Fi (or plug in Ethernet), then a username and password.
   No Microsoft account is needed; the ad and privacy screens are skipped.
5. At the first desktop a blue "PC Setup Kit" window appears. KEEP THE USB PLUGGED IN until it says it's finished
   (10-20 minutes, depending on internet speed). It:
     - removes Windows bloat (Copilot, Widgets, Teams, Outlook, OneDrive, news/ads, Xbox Game Bar...)
     - turns off telemetry, ads, Bing search, Recall/AI features, background tasks
     - gaming tweaks: Ultimate Performance power plan, Game Mode on, hardware GPU scheduling, Game DVR off,
       memory integrity (VBS) off, mouse acceleration off, no power-saving on controllers/Ethernet
     - blocks motherboard "auto driver installer" bloat
     - installs Git, Steam, Discord, Chrome, WinDbg, AutoHotkey, NVIDIA App (only with an NVIDIA card), Claude Code
     - creates "Messiah" (Start menu + desktop + tray icon) with hidden background maintenance
6. Messiah opens. Your friend logs in with THEIR Claude account, then Claude runs /pc-optimize:
   updates, drivers, hardware audit (BIOS version, RAM EXPO/XMP, graphics card PCIe link, monitor refresh rates),
   crash check, overlays, benchmark - and guides them through any BIOS steps.

ON AN EXISTING WINDOWS 11 PC (no reinstall)
Easiest: open PowerShell and run
    irm https://raw.githubusercontent.com/Kevincxv/pc-setup-kit/main/install.ps1 | iex
Or copy the PCSetupKit folder anywhere, right-click PCSetupKit\setup.ps1 > "Run with PowerShell", approve the admin prompt.

REMOVE IT
C:\PCSetupKit\uninstall.ps1 removes Messiah, the tray icon and the maintenance (add -RevertTweaks to also put
the Windows settings back). Nothing is deleted outright; removed files go to %USERPROFILE%\.claude\pc-setup-kit-removed-<date>.

UPDATES
PCs set up from the kit update themselves from https://github.com/Kevincxv/pc-setup-kit (new releases install
at the next login).

NOTES
- Everything is official Microsoft Windows; updates keep working. The kit only changes settings and removes apps.
- Undo: most changes are listed in C:\PCSetupKit\setup.log. Messiah can undo any of them on request.
- Messiah runs with permission prompts skipped: it acts without asking (it does ask before uninstalling
  the owner's apps or BIOS steps). Only give it to friends who are OK with that.
- Claude NEVER shuts down or restarts the PC (a built-in block enforces it). It does every fix right away; anything
  that needs a restart (Windows updates, drivers) finishes by itself the next time the owner turns the PC off -
  whenever suits them - and the check after that confirms it worked.
- Edge stays installed (Windows and many apps need its web engine) but is kept out of the way.
- Security note: memory integrity (VBS) is turned off for gaming performance.
- Each person needs their own Claude account (Pro or higher). The hidden maintenance uses that account's usage.

THE TRAY ICON (hidden icons area, next to the clock)
- At every login a Messiah session opens hidden there, so Claude is always ready. Click the icon to show or
  hide it; minimizing the window sends it back to the tray.
- If the PC was turned off while Claude was working, the next start picks the conversation up and finishes the job.
- Small alerts appear in the corner when something needs the owner (never over a fullscreen game; they wait).
- Right-click menu: Status (one page: what needs you, what waits for the next restart, last check, next checks),
  Watch maintenance live, to-do list, last report, self-improvement journal, run maintenance now.
- When Claude Code updates itself, the hidden session is quietly restarted on the new version once it's idle.

ZERO-MAINTENANCE (built in)
About 2 minutes after each login (and whenever Messiah is opened) maintenance runs hidden in the background:
  - every run: drivers, Claude Code, tweak guard, crash detection + automatic dump diagnosis (WinDbg),
    antivirus scan if >7 days old, clock sync, hardware reminders, restart check (what's waiting for the next
    shutdown, and afterwards whether it all finished)
  - weekly: app updates (Steam/Discord/Chrome/NVIDIA update themselves)
  - weekly and after every kit update: a self-test - the kit's own test suite checks the maintenance scripts on
    this PC (in a sandbox, nothing changes); a failure is a WARNING Claude fixes
  - monthly: restore point, Windows cleanup (safe allow-list only - never Downloads, Recycle Bin, shader cache),
    old driver versions, leftovers of uninstalled programs, SSD TRIM check, Windows end-of-support check
When something needs judgment, Claude handles it by itself (hidden, then tells the owner only what they must do):
  - any WARNING (crash, failed update, leftovers, an update that didn't finish after a restart), or Windows nearing
    end of support
  - every 3 months: BIOS / chipset / SSD firmware check, re-benchmark vs the baseline
  - every 6 months: reminder to dust the PC + temperature check + backup reminder
  - every year: full /pc-optimize re-audit
  - once a day: a self-improvement pass on the maintenance scripts (with automatic rollback if it breaks something)
Backups: a PC with one drive can't be backed up to itself; when a second or external drive is plugged in, the
maintenance report suggests letting Claude set up automatic backups to it.
The owner never has to do maintenance; only physical things (dusting, BIOS clicks) when Claude asks.
