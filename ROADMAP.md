# Roadmap

Work goes milestone by milestone. Every change is validated before it can reach anyone:

1. **Tests first**: a bug gets a test that would have caught it, then the fix (`PCSetupKit/tests`).
2. **Release gate**: `publish-kit.ps1` refuses to publish unless the whole suite passes (unit + live on the owner's PC).
3. **CI gate**: GitHub runs the unit suite on a clean Windows machine for every push (`.github/workflows/tests.yml`).
4. **Self-improvement gate**: the daily hidden self-improvement pass is undone completely if any test fails afterwards.
5. **Self-test on every PC**: weekly and after each kit update the suite runs against the PC's installed scripts; a
   failure is a WARNING that the hidden /maintain fixes.

Run the tests: `PCSetupKit\tests\run-tests.ps1 -Suite unit|live|all` (summary in `tests\last-run.txt`).

| # | Milestone | Status |
|---|-----------|--------|
| M1 | Permanent test suite: every earlier check turned into tests, one command | Done (2026-09-27) |
| M2 | Gates: release gate, CI on every push, self-improvement rollback on failing tests - each proven with a deliberate bug | Done (2026-09-27) |
| M3 | Coverage gaps: health-check, periodic tasks, driver-check (NVIDIA + Windows Update), crash-analyze, claude-maint, maint-watch, status, tray logic, tweaks.ps1, setup.ps1, autounattend.xml - all with mocked system commands, guarded by a tripwire and mock verification | Done (2026-09-27) |
| M4 | Ongoing self-validation: the suite runs weekly and after every kit update on each PC (self-test.ps1, from the background maintenance after its jobs); failures become a WARNING /maintain fixes; kit updates refresh the installed test suite | Done (2026-09-27) |
| M5 | Fresh-install test of setup.ps1 on a clean Windows 11 (needs a VM - owner's decision) | Planned |

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

Rules for mocked tests (PowerShell 5.1): variable names ignore case (`$tw` is `$TW`); aliases beat functions
(`H`, `Rp` are built-in aliases); functions beat module commands only if defined after the module is loaded.
