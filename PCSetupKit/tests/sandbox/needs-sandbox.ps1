# Does this round need the Windows Sandbox fresh-install run (about an hour)? Yes when something a new install runs
# changed since the published release: setup, the tweaks, the progress window, the installers, what setup's first
# maintenance does, the install checks themselves. Otherwise the unit tests plus GitHub's two fresh installs (both
# before anyone gets the release) cover it. Prints "yes" or "no" and the files that decide it.
# -Base: compare against this tag or commit (default: the newest published release).
param([string]$Base)
$repo = Split-Path (Split-Path (Split-Path $PSScriptRoot))
if (-not $Base) { $Base = "$(& gh release view -R Kevincxv/pc-setup-kit --json tagName --jq .tagName 2>$null)".Trim() }
if (-not $Base) { 'yes (no published release to compare with)'; return }
$changed = @(& git -C $repo diff --name-only $Base 2>$null) + @(& git -C $repo ls-files --others --exclude-standard 2>$null) | Sort-Object -Unique
# what a fresh install runs, start to end
$install = '^(install\.ps1|autounattend\.xml|PCSetupKit/(setup|tweaks|setup-progress)\.ps1|PCSetupKit/tests/(fresh|sandbox)/|' +
    'PCSetupKit/claude/(optimize|claude-bg-maint|tray-app|ai-toggle|ai-enabled|app-icon|settings-backup|display-refresh|junk-apps|' +
    'driver-check|vendor-updates|health-check|periodic-maint|ensure-schedule|self-test|todo|maint-actions)\.ps1|' +
    'PCSetupKit/claude/tray/|PCSetupKit/claude/(skills|hooks)/|docs/.*\.cmd$)'
$hits = @($changed | Where-Object { $_ -match $install })
if ($hits) { 'yes'; $hits | ForEach-Object { "  $_" } } else { 'no'; "  (changed since $($Base): $(@($changed).Count) file(s), none that a new install runs)" }
