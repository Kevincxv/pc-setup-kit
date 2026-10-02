# Messiah — PC Setup Kit

**One click turns a Windows 11 PC into a clean, fast gaming PC that then looks after itself.**
No bloat, no ads, no telemetry, tuned for games — and after that, drivers, updates, crash checks and cleanup all happen
on their own. No account and no AI needed.

**Install page:** https://kevincxv.github.io/pc-setup-kit/

---

## Two ways to use it

| | **Already have Windows 11** | **New PC, or a clean reinstall** |
|---|---|---|
| What | Cleans up and tunes the Windows you have | A USB stick that installs a slimmed-down Windows 11 and sets the PC up by itself |
| How | Install page > **Download the installer** | Install page > **Make an install USB** (needs an 8 GB+ stick; it gets erased) |
| Time | 15–30 minutes, hands-off | 20–40 minutes to make the stick, then about 20 minutes on the new PC |
| Your files | Kept | The drive you pick is wiped |

---

## What it does

**Removes the bloat**
- Preinstalled apps and ads: Copilot, Widgets, Teams, Outlook, News, Weather, Clipchamp, Solitaire, TikTok, Spotify and ~50 more.
- Telemetry, ads in Start and Settings, Bing in search, Recall and the other built-in AI features, background tasks that report usage.
- OneDrive, old Windows parts (Internet Explorer's engine, the old Media Player, WordPad, Steps Recorder…), PowerShell 2.0, and ~7 GB of reserved storage.
- Edge's desktop icon, taskbar pin and "make Edge your default" prompts.

**On the install USB it goes further — tiny11 as the base.** Windows on the stick comes without all of the above *and*
without Edge, WebView2, the Xbox app, text-to-speech, OCR, handwriting and face sign-in, with a clean Start menu
(Windows' own tools only — no placeholders that install Outlook or WhatsApp when clicked). Unlike tiny11 "core",
Windows can still install every update and repair itself.

**Tunes for games**
- Ultimate Performance power plan, Game Mode, hardware GPU scheduling, no background game recording, no mouse acceleration.
- Every monitor at its native resolution and highest refresh rate — also one you plug in later.
- Lower input lag in borderless games, variable refresh rate, NVIDIA low-latency mode and a bigger shader cache.
- No power-saving on controllers and wired network. Laptops stay on Balanced, at full speed when plugged in.
- Installs Steam, Discord, Chrome, Git, WinDbg and AutoHotkey (plus the NVIDIA App on NVIDIA cards).

**Looks after itself** — hidden, after every login, and never while you're playing
- Drivers (NVIDIA and AMD graphics too; Dell, HP and Lenovo through the maker's own tool) and app updates.
- Crash detection with automatic diagnosis of blue screens.
- Puts back anything a Windows update undid, two minutes after the update.
- Monthly cleanup and restore point, SSD TRIM, antivirus and clock checks.
- Measures your games' frame rate and temperatures while you play, and watches ping and packet loss — so "the last
  update made my games slower" gets noticed.
- Backs up your settings (wallpaper, dark mode, game settings) every week, so a reinstall brings them back.
- Updates itself, but only to versions that passed a full test install first.

**You stay in control**
- The **Messiah** app (Start menu, the tray icon next to the clock, or **Ctrl+Alt+M**) shows what the PC is doing and
  anything that needs you. Usually nothing does.
- Every change has its own switch in **Settings > What Messiah changes**. Switching one off puts it back as it was.
- Things only you can do (a BIOS setting, dusting the PC) come as plain step-by-step to-dos, and disappear once done.
- One-click undo of the last update or the last graphics driver, and a full uninstall.

**Optional AI assistant.** A switch in Settings adds Claude (your own Claude account, Pro or higher): it handles the
maintenance with judgment and you can ask it anything about your PC.

---

## Install on a PC that already has Windows 11

1. Open **https://kevincxv.github.io/pc-setup-kit/** and click **Download the installer**. Open the file.
2. If Windows shows **"Windows protected your PC"**, click **More info**, then **Run anyway** (see the FAQ below).
3. Click **Yes** for administrator rights, read what it will do, and type `YES`.
4. Wait 15–30 minutes. The Messiah app then opens with what it did.

Prefer a command? In PowerShell:

```powershell
irm https://github.com/Kevincxv/pc-setup-kit/releases/latest/download/install.ps1 | iex
```

## Install Windows from scratch (USB)

1. On any Windows PC, open the install page and click **Make an install USB**. Pick the stick. It downloads Windows 11
   from Microsoft, slims it down and adds the kit.
2. Plug the stick into the new PC, turn it on and press the boot-menu key (often **F8**, **F11** or **F12**). Pick the USB.
3. Choose the language and the drive to install on. **This is the one screen to be careful on** — only delete the
   partitions on the drive you want wiped.
4. Pick a username and password (no Microsoft account needed). At the desktop, a **"Setting up this PC"** window shows
   the progress. Keep the stick in until it says it's finished.

Have a Windows license ready: new PCs usually have one built in; otherwise you'll need a product key.

---

## Good to know before you install

- **Memory integrity (VBS) is turned off** for gaming performance. That's a small security trade-off; it's a switch in Settings.
- **Restarts:** it never restarts while you're using the PC. Pending Windows updates can finish with a restart at night,
  when nobody has used the PC for an hour (5-minute warning, a switch in Settings).
- **USB installs:** drive encryption isn't turned on automatically (you can turn it on in Settings), and PCs without
  TPM 2.0 or Secure Boot can install too — Microsoft doesn't officially support Windows 11 on those.
- **It never changes BIOS settings** and never uninstalls apps you installed yourself.

## FAQ

**Why does Windows say "Windows protected your PC"?**
The installer isn't code-signed — a signing certificate costs money every year, and this project is free. Click
**More info > Run anyway**. Everything it runs is the open-source code in this repository.

**Do I need an account or AI?** No. Everything works without either. The AI assistant is optional.

**What does it keep on purpose?** Windows Update, Windows Security (Defender) and Windows' repair tools — so the PC
stays patched. The Xbox Game Bar on AMD Ryzen 9 X3D CPUs (AMD's driver needs it to put games on the fast cores).
On an existing PC, Edge stays installed but hidden, because other apps use its engine.

**Can I get something back?** Yes — switch it off in Settings, or reinstall it from the Microsoft Store or
Settings > Optional features.

## Remove it

In the app: **Settings > Uninstall**. Or in PowerShell:

```powershell
C:\PCSetupKit\uninstall.ps1                 # removes Messiah and its maintenance
C:\PCSetupKit\uninstall.ps1 -RevertTweaks   # ...and puts the Windows settings back
```

Nothing is deleted outright: removed files go to `%USERPROFILE%\.claude\pc-setup-kit-removed-<date>`.

---

## For developers

- `PCSetupKit\` — the kit: `setup.ps1`, `tweaks.ps1`, `uninstall.ps1`, the maintenance scripts in `claude\`, the app
  (`claude\dashboard.ps1`) and the tray.
- `PCSetupKit\tests\` — over 1,000 tests (`run-tests.ps1`), run on every push, plus a real fresh install on GitHub, in
  Windows Sandbox and from a USB stick in a virtual PC (`tests\vm`) before a release goes out.
- Releases become **Latest** only after every check passes; installed PCs then update within 4 hours.

License: MIT.
