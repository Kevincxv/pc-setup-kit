PC SETUP KIT - fresh Windows 11 with all the tweaks, maintaining itself (no AI needed)
======================================================================

WHAT YOU NEED
- A USB stick, 8 GB or bigger (it gets erased).
- Your friend's Windows license (new PCs usually have one built in; otherwise a product key).
- Nothing else. (Only for the optional Messiah: your friend's own Claude account, Pro or higher. Never share yours.)

MAKE THE USB (once, on any PC)
1. Download Microsoft's "Media Creation Tool" for Windows 11:
   https://www.microsoft.com/software-download/windows11  ->  "Create Windows 11 Installation Media"
2. Run it and choose "USB flash drive". Wait for it to finish.
3. Copy these two items from this folder to the ROOT of the USB (next to setup.exe):
     autounattend.xml
     PCSetupKit\   (the whole folder)
4. Optional - Messiah (Claude Code with admin rights, needs a Claude account): put an empty file named
   with-claude.txt inside the PCSetupKit folder on the USB.

INSTALL ON THE NEW PC
1. Plug the USB into the new PC, turn it on, press the boot-menu key (F8/F11/F12 depending on the board) and pick the USB.
2. Setup asks for language/keyboard and the product key/edition ("I don't have a product key" is fine if the PC
   has a built-in license; pick the edition it came with, usually Home or Pro).
3. Setup asks WHERE to install. Pick the right drive and delete its old partitions if it's a fresh install.
   (Nothing is wiped automatically - this is the one screen to be careful on.)
4. After it restarts a few times: pick region/keyboard, Wi-Fi (or plug in Ethernet), then a username and password.
   No Microsoft account is needed; the ad and privacy screens are skipped.
5. At the first desktop a blue "PC Setup Kit" window appears. KEEP THE USB PLUGGED IN until it says it's finished
   (15-30 minutes, depending on internet speed). It:
     - removes Windows bloat (Copilot, Widgets, Teams, Outlook, OneDrive, news/ads, Xbox Game Bar...)
     - turns off telemetry, ads, Bing search, Recall/AI features, background tasks
     - gaming tweaks: Ultimate Performance power plan, Game Mode on, hardware GPU scheduling, Game DVR off,
       memory integrity (VBS) off, mouse acceleration off, no power-saving on controllers/Ethernet
     - blocks motherboard "auto driver installer" bloat
     - installs Git, Steam, Discord, Chrome, WinDbg, AutoHotkey, NVIDIA App (only with an NVIDIA card)
     - sets up the maintenance (runs hidden at every login) and the tray icon
     - optimizes the PC: monitors at their highest refresh rate, drivers and app updates, hardware checks
       (BIOS age, RAM EXPO/XMP, graphics card slot, monitors, drives), crash check, benchmark
6. A report opens (Documents\PC Setup Kit report.txt): what was done, and anything that needs your friend
   (for example a BIOS setting), explained step by step.
   With Messiah: instead, Messiah opens, your friend logs in with THEIR Claude account, and Claude runs /pc-optimize.

ON AN EXISTING WINDOWS 11 PC (no reinstall)
Easiest: open PowerShell and run
    irm https://raw.githubusercontent.com/Kevincxv/pc-setup-kit/main/install.ps1 | iex
With Messiah:
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Kevincxv/pc-setup-kit/main/install.ps1))) -WithClaude
Or copy the PCSetupKit folder anywhere, right-click PCSetupKit\setup.ps1 > "Run with PowerShell", approve the admin prompt.

REMOVE IT
C:\PCSetupKit\uninstall.ps1 removes the maintenance, the tray icon and Messiah if installed (add -RevertTweaks to
also put the Windows settings back). Nothing is deleted outright; removed files go to
%USERPROFILE%\.claude\pc-setup-kit-removed-<date>.

UPDATES
PCs set up from the kit update themselves from https://github.com/Kevincxv/pc-setup-kit (new releases install
at the next login).

NOTES
- Everything is official Microsoft Windows; updates keep working. The kit only changes settings and removes apps.
- Undo: most changes are listed in C:\PCSetupKit\setup.log; uninstall.ps1 -RevertTweaks puts the settings back.
- The kit NEVER shuts down or restarts the PC. It does every fix right away; anything that needs a restart (Windows
  updates, drivers, a memory test) finishes by itself the next time the owner turns the PC off - whenever suits
  them - and the check after that confirms it worked.
- It never changes BIOS settings and never uninstalls the owner's apps; it explains those steps instead.
- Edge stays installed (Windows and many apps need its web engine) but is kept out of the way.
- Security note: memory integrity (VBS) is turned off for gaming performance.
- Messiah (optional) runs with permission prompts skipped: it acts without asking (it does ask before uninstalling
  the owner's apps or BIOS steps). Only add it for friends who are OK with that; its hidden maintenance uses their
  Claude account's usage.

THE TRAY ICON (next to the clock) AND THE STATUS WINDOW
- The tray icon pins itself next to the clock once (hide it again in Settings > Personalization > Taskbar if you
  like; it stays hidden then).
- Click it (or right-click > Status), or open "PC Setup Kit Status" ("Messiah Status" with Messiah) in the Start
  menu: a window with what needs you, what waits for the next restart, the last check and when the next checks
  are. It updates by itself and has buttons to run maintenance, optimize the PC and open the full report.
- Small alerts appear in the corner when something needs the owner (never over a fullscreen game; they wait).
- Right-click menu: Status, maintenance to-do list, last maintenance report, run maintenance now,
  Optimize this PC now.
- To-do items explain exactly what to do and disappear once it's done. To dismiss one (for example if you keep
  something as it is on purpose), open the to-do list and delete its line.
- With Messiah: a Messiah session is always open hidden in the tray (click to show or hide it), and the menu also
  has Watch maintenance live and the self-improvement journal.

ZERO-MAINTENANCE (built in, no AI needed)
About 2 minutes after each login maintenance runs hidden in the background:
  - every run: drivers, tweak guard, crash detection + automatic dump diagnosis (WinDbg), antivirus scan if
    >7 days old, clock sync, hardware checks, restart check (what's waiting for the next shutdown, and afterwards
    whether it all finished)
  - weekly: app updates (Steam/Discord/Chrome/NVIDIA update themselves)
  - weekly and after every kit update: a self-test - the kit's own test suite checks the maintenance scripts on
    this PC (in a sandbox, nothing changes)
  - monthly: restore point, Windows cleanup (safe allow-list only - never Downloads, Recycle Bin, shader cache),
    old driver versions, leftovers of uninstalled programs, SSD TRIM check, Windows end-of-support check
Then fixed rules decide what to do with what it found:
  - fixed right away: monitor refresh rate, leftovers of deleted programs (disabled, not deleted), Windows version
    upgrade before end of support, a memory test at the next restart after repeated blue screens
  - explained step by step in the tray: BIOS update or settings (EXPO/XMP), graphics card slot, cables, backups,
    low disk space, a failing drive, apps that keep failing to update, crashes and what they point at
  - every 3 months: benchmark vs the one from setup (an item if the PC got slower)
  - every 6 months: reminder to dust the PC
  - every year: a full re-optimize
With Messiah these are handled by Claude instead (with judgment), plus a daily self-improvement pass on the scripts.
Backups: a PC with one drive can't be backed up to itself; when a second or external drive is plugged in, the tray
explains how to turn on File History for it.
The owner never has to do maintenance; only physical things (dusting, BIOS clicks) when the tray asks.
