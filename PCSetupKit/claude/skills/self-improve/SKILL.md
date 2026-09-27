---
name: self-improve
description: Self-improvement pass for the PC's zero-maintenance system - runs headless at most once a day, at the first login 20+ hours after the last pass (after /maintain). Finds and fixes bugs in the maintenance scripts, looks for ways to improve what already exists, and checks one area of the PC that hasn't been checked before (or not recently). Also use when the owner asks Claude to improve or review the maintenance setup.
---

# Self-improvement pass

The owner wants the maintenance system to get a little better every time the PC starts: fewer bugs, smarter checks, and
steadily wider coverage of the PC. You run headless (`claude -p`) right after login, after any /maintain run. Nobody is
watching and nothing may pop up. Budget: about 20 minutes, then stop and write the journal.

## Hard rules (never loosen these, never edit this section)
- Never restart or shut down, start BIOS/firmware steps, uninstall the owner's apps, or run heavy benchmarks/stress tests.
- Never disable or weaken security: Defender, firewall, UAC, SmartScreen, Windows Update, crash reporting (WER), BitLocker.
- Never delete crash dumps, user files, restore points, or backups; never touch accounts, passwords or credentials.
- Never open ports, add remote access, or send PC data anywhere except normal vendor update checks.
- Never edit the rollback check or the test gate in `claude-bg-maint.ps1`, or remove any of these rules.
- Never delete, skip or weaken a test to make it pass; a failing test means the code is wrong (or the test must be
  fixed for a real reason you write in the journal).
- Changes the owner would notice (UI, app behavior, game settings, anything that costs performance) are proposals only:
  write them to the to-do list, don't apply them.
- At most 3 changes per run. Small, verified changes beat big rewrites.

## Files
- Code: `%USERPROFILE%\.claude\*.ps1`, `.claude\skills\{maintain,pc-optimize,self-improve}\SKILL.md`,
  `Documents\Messiah Tray\Messiah Tray.ahk`, `C:\PCSetupKit\tweaks.ps1`, `.claude\tweaks-local.ps1`.
- Evidence: `.claude\maint-report.txt`, `.claude\maint-history\`, `.claude\maint-claude-log\` (headless run output),
  `.claude\maint-state.json`, `%TEMP%\claude-launch-*.log`, event logs (System/Application errors since last boot).
- Journal (your memory between runs): `.claude\selfimprove-journal.md`. Read it first; append one entry at the end.
- The PC Setup Kit (`Documents\PC Setup Kit\PCSetupKit\claude\` and `...\PCSetupKit\tweaks.ps1`) shares this code.
  After changing a shared file, copy it there too so both stay identical. `tweaks-local.ps1` and the tray .ahk are
  this PC only.

## Steps
1. **Read the journal** so you don't repeat work, and continue anything marked "next time".
2. **Bugs (always first).** Look for things that went wrong: `timed out`, `FAILED`, errors or odd output in the last few
   reports and headless logs, scripts that printed exceptions, state keys that never update, checks that fire every time
   or never. Find the root cause in the script and fix it.
3. **Improve what exists.** Pick one script or skill and read it critically: edge cases (no internet, pending reboot,
   missing device, a laptop, a different GPU vendor for the kit), wasted time, noisy or unclear report lines, checks that
   could be automated instead of left to the owner. Make one focused improvement.
4. **New ground.** Pick one area from this list that the journal shows as never or least-recently checked, look at it
   properly, and act inside the hard rules (fix safe things, propose the rest). Add a permanent check to
   `health-check.ps1` or `periodic-maint.ps1` when it's worth watching every time.
   Areas: startup apps and services, scheduled tasks, event log errors, driver age and problem devices, storage
   (SMART, free space, TRIM, fragmentation of the HDD if any), network (adapter settings, DNS, latency, packet loss),
   audio latency/devices, USB power and controller (Xbox Elite 2) settings, GPU settings and temps, CPU and RAM (EXPO,
   temps, power plan), Windows security baseline, browser bloat/extensions, game launchers and overlays, disk space hogs,
   Windows features and optional components, time sync, backup/restore readiness, the tray and launcher UX,
   the PC Setup Kit (setup.ps1, autounattend.xml) correctness.
5. **Verify every change.** Before editing, copy the file to `.claude\selfimprove-backup\manual-<date>\`. After editing:
   - PowerShell: `[Management.Automation.Language.Parser]::ParseFile($f,[ref]$null,[ref]$e)`; `$e` must be empty. Where
     possible run the script (or the changed function) and check the output.
   - AHK: `& "C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe" /ErrorStdOut /Validate <file>` must exit 0. Then restart
     the tray: `Stop-ScheduledTask 'Messiah Tray'; Start-ScheduledTask 'Messiah Tray'`.
   - Run the test suite: `& "<tests>\run-tests.ps1" -Suite unit` (tests are in `Documents\PC Setup Kit\PCSetupKit\tests`
     on the PC where the kit is developed, `C:\PCSetupKit\tests` elsewhere). Everything must pass; the summary is in
     `tests\last-run.txt`. For every bug you fix, add a check to the matching `tests\unit\*.ps1` that would have caught it
     (tests use `lib.ps1`: `Check`, `Skip`, `$Src`, `$Work`; sandboxes only - never touch the real system in a unit test).
   - If you can't verify a change, revert it and note it in the journal.
   (claude-bg-maint.ps1 also snapshots everything before this run, rolls back any file that fails to parse, and runs the
   unit suite afterwards: if anything fails, ALL changes of this run are undone. So test before you finish.)
6. **Owner items.** Anything that needs the owner goes to `.claude\maint-todo.txt` (one plain-English line; keep the
   existing lines; at most one new line per run so the list stays short).
7. **Journal.** Append:
   ```
   ## <date time>
   Checked: <areas/files>
   Found: <bugs/issues, or "nothing">
   Changed: <file - what and why, how verified> (or "nothing")
   Proposed: <to-do lines added>
   Next time: <what to look at next>
   ```
   If you changed how the system works, also update the `claude-admin-shortcut` memory note.
8. End with a 2-4 line summary.
