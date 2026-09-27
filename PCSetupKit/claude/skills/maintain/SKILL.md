---
name: maintain
description: Scheduled PC maintenance that needs judgment - handles WARNING items from the background maintenance report (crash dumps, leftovers, failed updates, Windows version end of support) and the quarterly / half-year / yearly checks (BIOS, chipset and SSD firmware, re-benchmark, physical cleaning reminder, full re-audit). The Claude (Admin) launcher starts this automatically when something is due; also use it when the user asks for maintenance.
---

# Scheduled maintenance

The owner wants zero maintenance work: you do everything, they only do physical things (and BIOS clicks) you ask for.
Be brief: one status line per step, a short report at the end, then hand back to whatever they want to do.
Follow the ground rules in the `pc-optimize` skill (ask before BIOS steps or uninstalling the owner's apps;
never write BIOS NVRAM; never delete crash dumps; say when you couldn't read something).
**Never shut down or restart the PC** (a hook blocks it). Finish every fix now; restart-only work stays pending and
completes whenever the owner turns the PC off themselves. Arm `resume-after-restart.ps1 -Prompt "Verify <what>"` so the
tray reopens the conversation after their next start. If they turn the PC off in the middle of your work, the next login
resumes it (the tray for interactive sessions, maint-requests.txt for hidden runs).

## Inputs
- `%USERPROFILE%\.claude\maint-report.txt` - latest background run (drivers, Claude Code, PC health, periodic tasks).
- `%USERPROFILE%\.claude\maint-history\` - the last 30 reports (look for trends: repeated failures, SSD wear rising).
- `%USERPROFILE%\.claude\maint-state.json` - when each task last ran. Keys you own: `claude-quarterly` (90 days),
  `claude-halfyear` (180 days), `claude-yearly` (365 days), `claude-winver-due` (set by the background job).
- `%USERPROFILE%\.claude\benchmarks.json` - baseline benchmark results to compare against.

## 1. Anything flagged WARNING in the report (always)
- **Crash dump / blue screen**: `& "$env:USERPROFILE\.claude\crash-analyze.ps1" -Dump <path> -Full`; identify the driver or
  hardware cause, check it against recent driver/app installs (System event 7045), fix what you can (update/roll back the
  driver, remove leftover anti-cheat/vendor drivers), and explain the rest.
- **Repeat crashes with no clear cause** (inconclusive dumps, same code again, no WHEA): don't stop at "unknown". Work
  down this ladder, one step per new crash, and keep the current step on the to-do list so the owner knows what's next:
  1. Remove leftover/unneeded kernel drivers (vendor utilities, anti-cheat of uninstalled games, old filter drivers).
  2. EXPO/XMP test: RAM at its rated speed is the most common cause of 0x109/0x1A/0x50 crashes shortly after boot.
     Ask the owner to disable EXPO/XMP in the BIOS (guided, pc-optimize section 7) and run a few days at JEDEC speed.
     No crashes then = RAM overclock unstable: offer a BIOS update, then EXPO with a small SoC/VDD bump or one speed
     step lower. Crashes continue = RAM speed is not the cause; turn EXPO back on.
     **Verdict** (maint-due lists "EXPO-off test verdict" 4 days after `expo-off-test` in maint-state.json, or at
     `expo-off-test-review`): count blue screens (System event 1001 from WER-SystemErrorReporting, plus minidumps) and
     cold boots (event 6005) since the test started.
     - RAM already back above JEDEC speed (EXPO on again): the test is over - record the result, remove `expo-off-test`
       and `expo-off-test-review`, drop its to-do line.
     - Fewer than 6 boots so far: not enough evidence - set `expo-off-test-review` to 2 days from now and keep one
       to-do line saying the test continues (with the boot count).
     - No crashes: the RAM overclock was the cause. Rewrite the to-do line as the result plus the next BIOS step in
       plain words: turn EXPO back on with a small SoC voltage bump (e.g. VSOC 1.25 V) - or, simpler, EXPO with the
       RAM one step slower (5600) - and say Claude walks them through it (pc-optimize section 7) when they open Claude.
       Set `expo-off-test-review` 30 days out so this isn't raised again before they act.
     - Crashes happened: RAM speed isn't the cause. To-do: turn EXPO back on (normal speed again); the ladder moves
       to step 3. Remove `expo-off-test` once the RAM runs at EXPO speed again.
     Record the verdict in the maintenance memory note. The tray shows the owner an alert for the new to-do line.
  3. Overnight memory test (Windows Memory Diagnostic extended, or TestMem5/OCCT if installed) - Windows Memory
     Diagnostic runs at the owner's next restart (schedule it with `bcdedit /bootsequence {memdiag}` and extended mode,
     never trigger the restart yourself); ask them to restart at a time they don't need the PC for a few hours.
  4. Driver Verifier on non-Microsoft drivers (`verifier /standard /all` style, only with the owner present, and tell
     them how to turn it off from Safe Mode) - catches the driver that corrupts memory.
  5. Hardware: reseat RAM/GPU, check PSU; test one RAM stick at a time.
  Record which step each crash reached in the maintenance memory note so the ladder continues across runs.
- **Leftovers pointing at deleted programs** (services/tasks): confirm the program is really gone, then remove the
  service (`sc.exe delete`) / task (`Unregister-ScheduledTask`). Leave anything owned by Microsoft alone.
- **App or driver update failed / timed out**: find out why (logs, winget output) and fix or hide it.
- **Windows version near end of support**: web-search Microsoft's Windows 11 release information for the newest version
  that is generally available; set `HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate` `ProductVersion`="Windows 11",
  `TargetReleaseVersion`=1, `TargetReleaseVersionInfo`=<that version>; scan Windows Update and install it (usually a small
  enablement package); tell the owner it finishes the next time they turn the PC off (never restart for them). Remove `claude-winver-due` afterwards.
- **Hardware errors (WHEA)**: check which component; suggest a RAM/CPU stability test if they repeat.

## 2. Quarterly (claude-quarterly older than 90 days)
- BIOS: board model (Win32_BaseBoard) + version/date (Win32_BIOS); web-search the vendor support page for a newer
  version. If there is one, summarize what it fixes and offer the guided update (pc-optimize section 7).
- Chipset driver (AMD/Intel) and SSD firmware (Get-PhysicalDisk FirmwareVersion vs the vendor's latest): update if safe
  (vendor tools only), otherwise tell the owner what's available.
- Controller firmware: if an Xbox controller is connected, remind them to open Xbox Accessories once to update it.
- Re-benchmark: `winsat formal` (tell the owner it takes ~2 minutes and loads the PC), compare with `benchmarks.json`;
  investigate drops of more than ~10% (thermal throttling, power plan changed, driver regression). Append the result.
- Review maint-history for trends. Then set `claude-quarterly` to now.

## 3. Half-year (claude-halfyear older than 180 days) - physical reminders
- Ask the owner to dust the PC: shut down, unplug, clean dust filters and fans with compressed air (hold fans still).
- Check GPU temperature under a short load (`nvidia-smi --query-gpu=temperature.gpu,clocks.gr --format=csv -l 1` during
  winsat); warn if it runs above ~83 C.
- Remind them to back up anything irreplaceable if they have no backup set up (File History to an external drive or a
  cloud drive). Then set `claude-halfyear` to now.

## 4. Yearly (claude-yearly older than 365 days)
Run the full `pc-optimize` playbook as a re-audit (skip what was done this session), then set `claude-yearly` to now.

## Updating the state file
```powershell
$f = "$env:USERPROFILE\.claude\maint-state.json"; $s = Get-Content $f -Raw | ConvertFrom-Json
$s | Add-Member -NotePropertyName 'claude-quarterly' -NotePropertyValue (Get-Date).ToString('o') -Force
$s | ConvertTo-Json | Set-Content $f -Encoding utf8
```
To mark the report's warnings as handled, run `& "$env:USERPROFILE\.claude\maint-due.ps1" -MarkHandled` (don't write
`claude-handled-report` yourself: a raw `Get-Content` line serializes as an object, not text).

## Unattended runs and the to-do list
At login this skill may run headless (`claude -p`, no window): then never ask questions, restart, or start anything heavy -
write what needs the owner to `%USERPROFILE%\.claude\maint-todo.txt` (one plain-English line each; rewrite the whole list;
delete the file when empty). Logs of headless runs are in `.claude\maint-claude-log\`. When the owner opens Claude (Admin)
with open items, go through them together; remove each line once it's done. One-off requests for the next login run can be
left in `.claude\maint-requests.txt`.

## Report
End with: what you did, anything the owner must do (physical steps, BIOS), anything that finishes at their next
shutdown/restart (whenever suits them), and when the next check is due.
