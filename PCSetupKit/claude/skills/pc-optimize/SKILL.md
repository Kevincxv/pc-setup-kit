---
name: pc-optimize
description: Full new-PC optimization playbook for a Windows 11 gaming PC set up with the PC Setup Kit - updates, drivers, debloat check, hardware audit (BIOS, RAM EXPO/XMP, GPU PCIe link, monitor refresh, storage, controllers), crash/stability check, overlays, benchmark, and guided BIOS work. Use when the user runs /pc-optimize or asks to optimize, audit, or debloat this PC.
---

# PC optimize playbook

You are Claude Code running elevated with permission prompts skipped, on a Windows 11 PC that was installed with the
PC Setup Kit (tweaks, apps, and this launcher were set up automatically at first login). The owner may not be technical:
explain in plain language, one short status line before long-running steps, and a clear report at the end.

## Ground rules (learned the hard way - follow them)
- **Ask before** uninstalling anything the owner installed, or any BIOS step. Removing Microsoft bloat
  and tweaking Windows settings needs no confirmation (that is what the kit is for).
- **Never shut down, restart or log off the PC** (a hook blocks it anyway). Do every fix that can be done now; leave work
  that needs a restart pending - Windows finishes it whenever the owner turns the PC off or restarts on their own schedule
  (fast startup is off, so a normal shutdown completes pending updates/drivers). Arm
  `& "$env:USERPROFILE\.claude\resume-after-restart.ps1" -Prompt "Verify <what>"` so the tray reopens the conversation
  (hidden) after their next start and you verify it then. Tell the owner in one line: "finishes next time you turn the PC off".
- **Never write BIOS/UEFI NVRAM variables from Windows** and never flash BIOS with unofficial tools (e.g. AFUWIN). BIOS
  changes are done by the owner in the BIOS screen, following your exact step-by-step menu paths.
- **Never claim a value you could not read.** If a setting is unreadable (e.g. vendor "Setup" stores, error 203), say so
  and give the default only as a default. Before recommending a BIOS option, check it is not hidden (IFR `SuppressIf`).
- **Never delete crash dumps** (C:\Windows\Minidump, MEMORY.DMP) - they identify the cause of blue screens.
- Disk Cleanup (`cleanmgr /sagerun:N`) only with an **allow-list** of categories (see periodic-maint.ps1). Never enable
  DownloadsFolder, Recycle Bin, D3D Shader Cache (games stutter while it rebuilds), dump/error-report files, Previous
  Installations (needed to roll back an upgrade for 10 days), or the DISM-based ones (Update Cleanup, Device Driver Packages,
  Language Pack) - those hang while a restart is pending. Always run it with a timeout.
- The harness may block `Remove-Item` on paths it thinks are system paths. Use `[IO.Directory]::Delete($p, $true)` /
  `[IO.File]::Delete($p)` in PowerShell, or `rm -rf` in Bash, after checking the path.
- In Windows PowerShell 5.1 don't use `Start-Job` for long work (it can hang); use `Start-Process -PassThru` + wait.
- winget packages installed per-user can't be uninstalled from an elevated shell - delete their folder instead.
- Partition numbers change after reboots; identify partitions by label/filesystem, never by number alone.
- Keep a list of every change in `%USERPROFILE%\Documents\PC-Tweaks-Log.txt` (what changed, old value, how to undo).
- Kit files: `C:\PCSetupKit\` (setup.log, tweaks.ps1). Launcher files: `%USERPROFILE%\.claude\` (claude-admin-launch.ps1,
  claude-bg-maint.ps1 -> maint-report.txt, driver-check.ps1, claude-maint.ps1, health-check.ps1, resume-after-restart.ps1).

## 1. Setup check
- Read `C:\PCSetupKit\setup.log`; fix anything that failed (app installs, NVIDIA App, Claude Code).
- Run `& C:\PCSetupKit\tweaks.ps1` - it prints only what it had to (re)apply.
- Confirm OneDrive is gone and the "Claude Background Maintenance" task exists.

## 2. Updates (everything current before auditing)
- Windows Update including optional driver updates (Microsoft.Update.Session COM: search `IsInstalled=0 and IsHidden=0`,
  download, install). Microsoft Store app updates. `winget upgrade --all --silent --accept-package-agreements --accept-source-agreements`.
- GPU driver: NVIDIA - compare `nvidia-smi` with the NVIDIA App's `%LOCALAPPDATA%\NVIDIA Corporation\NVIDIA app\NvBackend\DriverRecommendations.dat`
  (see driver-check.ps1); AMD - check amd.com for the latest Adrenalin; Intel Arc - Intel driver page.
- Chipset driver: AMD chipset (amd.com) or Intel chipset/ME via the board vendor. Note versions.

## 3. Hardware audit
Collect and report: CPU, motherboard (Win32_BaseBoard), BIOS version + date (Win32_BIOS), RAM kit (part number,
`Speed` vs `ConfiguredClockSpeed`), GPU(s), storage (Get-PhysicalDisk + reliability counters), monitors, network, controllers.
- **BIOS**: web-search the board's support page for the newest BIOS. If behind, explain benefits (stability, memory
  compatibility, security) and offer the guided update (section 7).
- **RAM**: if ConfiguredClockSpeed equals the JEDEC default (4800/5200/5600 DDR5, 2133-3200 DDR4) and the kit's part
  number is rated faster, EXPO/XMP is off -> BIOS step.
- **GPU PCIe link**: `Get-PnpDeviceProperty ... DEVPKEY_PciDevice_CurrentLinkWidth/MaxLinkWidth/CurrentLinkSpeed`, and
  confirm under load (`nvidia-smi --query-gpu=pcie.link.gen.current,pcie.link.width.current` while `winsat formal` runs).
  Width below the card's max = BIOS slot/bifurcation setting, riser cable, or seating. Check Resizable BAR (nvidia-smi -q BAR1 total ~ VRAM).
- **Monitors**: for each display compare current refresh with the max at that resolution (EnumDisplaySettings) and the
  connection type (`WmiMonitorConnectionParams.VideoOutputTechnology`: 5 = HDMI, 10 = DisplayPort). HDMI 2.0 caps 1440p at
  144Hz. Set the highest refresh with ChangeDisplaySettingsEx if the owner agrees. If they keep a monitor lower on purpose,
  add its name to `%USERPROFILE%\.claude\health-ignore.txt`.
- **Storage**: NVMe link (gen/width), health, wear, temperature, TRIM (`fsutil behavior query DisableDeleteNotify`).
- **iGPU**: if a discrete GPU drives all monitors and the CPU's iGPU is unused, offer to disable it (Device Manager now;
  BIOS option names vary - on AMD CBS it is often "dGPU Only Mode", with "iGPU Configuration" hidden until that is Disabled).
- **Controllers**: Xbox controllers -> offer the Xbox Accessories app (winget `9NBLGGH30XJ3` from msstore) for firmware/profiles.
  Wired is lowest latency. Look for phantom virtual gamepads (e.g. leftover AMD/vendor emulation drivers).
- **Network**: wired adapter power saving should be off (tweaks.ps1 does this); note link speed.

## 4. Stability
- Last 30 days: bugchecks (System 1001 WER-SystemErrorReporting), Kernel-Power 41, WHEA-Logger, display driver resets (4101).
- If there are crashes: note the pattern (right after boot vs under load), list kernel drivers installed near those times
  (System 7045), look for leftover anti-cheat/vendor drivers whose files no longer exist, and analyze dumps if present.
- If RAM instability is suspected: offer a stress test (Prime95 blend or OCCT) with the owner's OK; with EXPO/XMP on AM5,
  "Memory Context Restore" Enabled is a common cause of crashes right after boot.

## 5. Bloat and background load
- List startup apps and non-Microsoft services/tasks; flag vendor bloat (Armoury Crate, MSI Center, iCUE, Razer Synapse,
  ASRock APP Shop/Auto Driver Installer, AI Suite...). Ask before removing anything the owner may use (RGB, fan, audio apps).
- Ask which overlays they use; turn off the rest:
  Steam - close Steam (`steam.exe -shutdown`), set `"EnableGameOverlay" "0"` in `Steam\userdata\<id>\config\localconfig.vdf`, restart `-silent`.
  Discord - close it, set `enableHardwareAcceleration` false in `%APPDATA%\discord\settings.json`; the in-game overlay flag is
  in Discord's localStorage `OverlayStore6` (legacyEnabled/oopEnabled) - readable by launching Discord with
  `--remote-debugging-port` and evaluating via the DevTools protocol (Node has WebSocket built in).
  NVIDIA - only if they don't record/use the performance overlay.
- Idle baseline: 30 s of `\Processor(_Total)\% Processor Time`, `% DPC Time`, `% Interrupt Time`, top processes.

## 6. Benchmark
`winsat formal` (then `Get-CimInstance Win32_WinSAT` and the newest `C:\Windows\Performance\WinSAT\DataStore\*Formal*.xml`
for memory bandwidth/disk). Report scores with the idle baseline. Re-run after hardware/BIOS fixes to show the difference.
Save the result as the baseline for future maintenance: append `{date, cpu, memory, d3d, graphics, disk, memBandwidthMBs,
gpuLink, biosVersion, notes}` to `%USERPROFILE%\.claude\benchmarks.json` (a JSON array).

## 7. Guided BIOS work (owner does the clicking)
- BIOS visits happen when the owner chooses: arm the resume request first
  (`& "$env:USERPROFILE\.claude\resume-after-restart.ps1" -Prompt "Verify <what changed> after the BIOS visit"`), then tell
  them to press F2 or Del at the logo the next time they start the PC (never restart it for them). Give numbered steps with
  exact menu paths; the owner can follow on their phone, and add the visit to maint-todo.txt so it isn't forgotten.
- **BIOS update without a USB stick**: download the official ROM from the vendor (ASRock:
  `https://download.asrock.com/BIOS/AM5/<Board>(<ver>)ROM.zip`, probe versions slowly - rapid requests get the IP blocked),
  verify it (size, board name inside), shrink C: by 2 GB, create a FAT32 partition labelled BIOS, copy the ROM, remove its
  drive letter, and optionally copy to the EFI partition (`mountvol S: /S`) as a fallback. The vendor's in-BIOS flasher
  (ASRock Instant Flash, ASUS EZ Flash, MSI M-Flash, Gigabyte Q-Flash) finds it. Internet Flash may not exist on newer BIOS.
  Afterwards delete the ROM copies and the BIOS partition (find it by label) and extend C:.
- After a BIOS update, settings reset: re-enable EXPO/XMP, re-check Resizable BAR/Above 4G, the PCIe slot mode (x16), and
  disable the vendor auto-driver-installer (WPBT) option. fTPM prompt after flashing: press N to keep keys.
- Reading current BIOS settings (read-only, optional deep audit): download the ROM, unpack with UEFIExtract
  (LongSoft/UEFITool releases), extract forms with IFRExtractor-RS (LongSoft), then read the matching NVRAM variables with
  GetFirmwareEnvironmentVariableExW after enabling SeSystemEnvironmentPrivilege (e.g. AMD CBS `AmdSetupRPL`
  {3A997502-647A-4C82-998E-52EF9486A247}, `AMD_PBS_SETUP` {A339D746-F678-49B3-9FC7-54CE0F9DF226}). Map question VarOffset -> value.

## 8. Report
Summarize: what changed, benchmark results, anything the owner must do (BIOS steps, reseating hardware, cables), and what
was intentionally left alone (PBO/Curve Optimizer and manual FCLK only after 1-2 weeks without crashes). If anything needs a
restart (memory-integrity change, drivers, updates), don't restart: say it finishes the next time they turn the PC off, and
arm the resume request so you verify everything after their next start.
Finally mark the scheduled checks as done so the `maintain` skill starts counting from today: set `claude-quarterly`,
`claude-halfyear` and `claude-yearly` to now in `%USERPROFILE%\.claude\maint-state.json` (see the maintain skill).
From then on the owner does no maintenance: background jobs handle routine work and the launcher opens `/maintain` when needed.
