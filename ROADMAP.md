# Roadmap

Work goes milestone by milestone. Every change is validated before it can reach anyone:

1. **Tests first**: a bug gets a test that would have caught it, then the fix (`PCSetupKit/tests`).
2. **Release gate**: `publish-kit.ps1` refuses to publish unless the whole suite passes (unit + live on the owner's PC).
3. **CI gate**: GitHub runs the unit suite on a clean Windows machine for every push (`.github/workflows/tests.yml`).
4. **Self-improvement gate**: the daily hidden self-improvement pass is undone completely if any test fails afterwards.
5. **Self-test on every PC**: weekly and after each kit update the suite runs against the PC's installed scripts; a
   failure is a WARNING that the hidden /maintain fixes.

Run the tests: `PCSetupKit\tests\run-tests.ps1 -Suite unit|live|all` (summary in `tests\last-run.txt`).
Unit test files run side by side (`-Jobs`, default up to 8; each gets its own TEMP), live ones one at a time after
them. Speed audit 2026-09-27: unit 210 s -> ~27 s, unit + live (the release gate) ~350 s -> ~115 s, CI once per release
instead of twice. A test that writes to stderr counts as failed (a crash halfway is never a silent pass).

| # | Milestone | Status |
|---|-----------|--------|
| M1 | Permanent test suite: every earlier check turned into tests, one command | Done (2026-09-27) |
| M2 | Gates: release gate, CI on every push, self-improvement rollback on failing tests - each proven with a deliberate bug | Done (2026-09-27) |
| M3 | Coverage gaps: health-check, periodic tasks, driver-check (NVIDIA + Windows Update), crash-analyze, claude-maint, maint-watch, status, tray logic, tweaks.ps1, setup.ps1, autounattend.xml - all with mocked system commands, guarded by a tripwire and mock verification | Done (2026-09-27) |
| M4 | Ongoing self-validation: the suite runs weekly and after every kit update on each PC (self-test.ps1, from the background maintenance after its jobs); failures become a WARNING /maintain fixes; kit updates refresh the installed test suite | Done (2026-09-27) |
| M5 | Fresh-install test: setup.ps1 runs for real on a clean Windows machine for every release (GitHub, Windows Server - fresh-install.yml), then its result is checked and the new install's own self-test must pass. A clean Windows 11 Home/Pro run (Windows Sandbox or a VM) is the owner's decision: it turns on the hypervisor the kit keeps off for gaming | In progress |

Found and fixed by the gates and tests so far:
- end-of-support ignored the Windows edition (CI); resume-after-shutdown trusted an old shutdown record (CI)
- test-suite-in-test-suite loop on installed PCs (while writing the gate test)
- PCs without an NVIDIA card got "NVIDIA: check failed" at every login, which woke /maintain every time (M3)
- the Status window showed an error on a brand-new install (M3); tray tooltip grammar (M3)
- test safety: a mock of a Windows-module command loses to the real one once the module loads - tests now load
  modules first and verify every mock before anything runs (M3; found when a test re-registered real scheduled tasks,
  which were restored immediately)
- installed PCs never got test updates (kit-update skipped tests) - the self-test would have tested new scripts with
  old tests (M4)
- a corrupt health-check.last made health-check error out; its test passed anyway (its error filter missed that kind
  of error), and on CI the error stopped the whole runner, hiding the rest of the suite for two releases (M4)
- the personal-info check scanned installed PCs' own files (setup log) - it now runs only in the repo and CI (M4)
- speed audit: two tests passed while broken - a live test that crashed halfway (its cleanup check still ran) and
  the login rehearsal test (a rehearsal that stopped early still printed its summary); a unit test ran the real
  Windows Update driver search (20 s, and it could hide real updates); a 45 s wait for a hung step

Rules for mocked tests (PowerShell 5.1): variable names ignore case (`$tw` is `$TW`); aliases beat functions
(`H`, `R`, `Rp` are built-in aliases); functions beat module commands only if defined after the module is loaded.
