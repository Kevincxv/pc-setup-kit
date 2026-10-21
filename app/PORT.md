# The compiled app (MessiahApp.exe) - porting dashboard.ps1 to C#

Why: the PowerShell window took 2.2 s to open and 1.4 s to build Home (most of it PowerShell creating elements one by
one). Measured 10/12 with the first phase: window on screen in 0.22 s, Home built in 17 ms, data read in the background
(0.3 s, never blocking the window), reopen 41 ms, 112 MB instead of 193 MB.

How: WPF on .NET Framework 4.8 (part of every Windows 10/11 - nothing to install), built with the .NET SDK
(`dotnet build -c Release` in app\Messiah.App; app\nuget.config points at nuget.org for the 4.8 reference assemblies).
Same looks, words and behavior as dashboard.ps1 - the helpers keep its names (Ui.Card = New-Card, Kit.FormatWhen =
Format-When ...). Data is read by Snapshot.Load on a background thread; pages are built from the snapshot; a refresh that
reads the same (Sig) redraws nothing. The maintenance scripts stay PowerShell; the app calls them for actions.

While the port runs, the app runs side by side with dashboard.ps1 under its own names (App.Names: mutex
Local\MessiahApp.Next, app-window-next.txt, app-request-next.txt). `--live` switches to the real names.
`MessiahApp.exe --test` prints every ported page as text (the PowerShell app's -Test format); `--timing` logs the start.

## Phases
1. [x] Foundation: project, theme and styles, building blocks (Ui.cs), data (Data.cs: Get-KitStatus, game check, diag
       modes, RAM test, power log, chat state), status model counts, window shell (tabs, sub-pages, note bar, Mica,
       placement, show/hide, single instance, background start, crash log app-errors.log), Home, --test.
2. [x] Status (10/20; rows and details identical to dashboard.ps1's, built in 38 ms): the full model with details (plain names, tweak catalog, history from change-history.log, keep values),
       rows that open, filters and search, Check now.
3. [x] Activity (10/20; every card and chart identical): Checks, Stability (timeline), Trends (charts), Alerts.
4. [x] Settings (10/20; same switches and cards; the driver date is now the INF's own, not shifted a day by the time zone): General, Windows (tweak switches), Tools (repair, rollback, USB, BIOS, game saves, uninstall).
5. [x] Chat (10/20; same self-test lines as dashboard.ps1; sent end to end through the window to a stand-in Claude via UI Automation; the list of earlier conversations is read in the background): tabs, history, streaming, markdown with links and copy, attachments, edit, find, speed, rename/pin, phone.
6. [x] (10/20; the search card is solid now - the page showed through it) The rest: Welcome page, the tour, search (Ctrl+K), Ask Claude pill, NowBar, keyboard shortcuts, the top-right
       buttons; Get-RamTestNow and every Home card checked against real data in --test.
7. [x] Switch-over (10/20): tools\app\build.ps1 builds PCSetupKit\claude\app\MessiahApp.exe (publish-kit before each
       release, installed on this PC too; tests.yml builds it from source and runs --test); setup.ps1 / kit-update.ps1
       install it to .claude\app (a running copy moved aside; Rollback saves and restores it); the tray (ShowApp,
       PreloadApp) and the Start menu (tray-app.ps1) run it --live, dashboard.ps1 only where it's missing (a hidden
       dashboard.ps1 quits once the exe is there); uninstall stops and removes it. Mutex/show event open to the same
       user (the tray starts it elevated, the Start menu not). Audit: both apps on the same 6 data sets - every text
       the old one shows is in the new one; RAM-test, chat and help-report self-tests identical; tests\unit\app.ps1
       (pages, chat, RAM test, report, diag, Welcome tab, garbage state files in a non-English profile path); fresh
       install and sandbox checks use the exe. Fixed in the audit: screen-change refit, the Documents path
       (%USERPROFILE%\Documents like the scripts, not a OneDrive-moved one).
   [ ] Still to do: signing (SignPath - the owner's account), then remove dashboard.ps1 (+ its tests) one release later.
