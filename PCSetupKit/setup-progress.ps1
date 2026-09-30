# PC Setup Kit - the progress window while setup.ps1 runs (10-40 minutes on a new PC): every step with a check mark
# once done, the one running now, a progress bar weighted by how long each step usually takes, time so far and about
# how long is left. setup.ps1 starts it and writes each step to setup-progress.txt ("time|step"); "Done" finishes it.
# If setup stops without finishing, it says so and where the log is. Light or dark like Windows.
# -ProgressFile / -SetupPid: which progress file and setup process to follow; -Test: build the window once, print it, close.
param([string]$ProgressFile = "$PSScriptRoot\setup-progress.txt", [int]$SetupPid, [switch]$WithClaude, [switch]$Test)
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName PresentationFramework
# the steps in order, with their usual minutes on a new PC (the bar moves by these, not by step count)
$steps = @(@('Waiting for internet', 0.3), @('Applying Windows tweaks', 1.5),
    @('Getting winget ready', 2), @('Installing apps', 8), @('Setting up the maintenance', 1), @('Installing Claude Code', 2), @('Optimizing this PC', 3))   # (the full maintenance continues in the background after setup)
$dark = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize').AppsUseLightTheme -eq 0
$c = if ($dark) { @{ Bg = '#202020'; Card = '#2B2B2B'; Text = '#FFFFFF'; Sub = '#A8A8A8'; Accent = '#8F7DFF'; Done = '#6CCB5F'; Bad = '#FF99A4' } }
else { @{ Bg = '#F3F3F3'; Card = '#FFFFFF'; Text = '#1B1B1B'; Sub = '#5F5F5F'; Accent = '#6D5AE6'; Done = '#0F7B0F'; Bad = '#C42B1C' } }
$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" Title="Messiah" Width="460" SizeToContent="Height"
        WindowStartupLocation="CenterScreen" ResizeMode="CanMinimize" Background="$($c.Bg)" FontFamily="Segoe UI Variable Text, Segoe UI">
  <StackPanel Margin="24">
    <TextBlock Text="Setting up this PC" FontSize="22" FontWeight="SemiBold" Foreground="$($c.Text)"/>
    <TextBlock Name="Sub" Text="You can keep using it - just don't turn it off." FontSize="13" Foreground="$($c.Sub)" Margin="0,4,0,16" TextWrapping="Wrap"/>
    <ProgressBar Name="Bar" Height="6" Minimum="0" Maximum="100" Foreground="$($c.Accent)" Background="$($c.Card)" BorderThickness="0"/>
    <DockPanel Margin="0,6,0,14">
      <TextBlock Name="Left" DockPanel.Dock="Right" FontSize="12" Foreground="$($c.Sub)"/>
      <TextBlock Name="Elapsed" FontSize="12" Foreground="$($c.Sub)"/>
    </DockPanel>
    <Border Background="$($c.Card)" CornerRadius="8" Padding="14,10"><StackPanel Name="List"/></Border>
  </StackPanel>
</Window>
"@
$win = [Windows.Markup.XamlReader]::Parse($xaml)
$ui = @{}; foreach ($n in 'Sub', 'Bar', 'Left', 'Elapsed', 'List') { $ui[$n] = $win.FindName($n) }
$brush = @{}; foreach ($k in $c.Keys) { $brush[$k] = [Windows.Media.BrushConverter]::new().ConvertFromString($c[$k]) }
$start = Get-Date
function Update-View {
    $lines = @(Get-Content $ProgressFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '\|' } | ForEach-Object { $a = $_ -split '\|', 2; [pscustomobject]@{ At = [datetime]$a[0]; Step = $a[1] } })
    if ($lines) { $script:start = $lines[0].At }
    $seen = @($lines | ForEach-Object { $s = $_.Step; [array]::FindIndex($steps, [Predicate[object]] { param($x) $s -like "$($x[0])*" }) } | Where-Object { $_ -ge 0 })
    $cur = if ($seen) { ($seen | Measure-Object -Maximum).Maximum } else { -1 }
    $done = [bool]($lines | Where-Object { $_.Step -like 'Done*' })
    $withClaude = $WithClaude -or [bool]($lines | Where-Object { $_.Step -like 'Installing Claude Code*' })
    $show = @(for ($i = 0; $i -lt $steps.Count; $i++) { if ($steps[$i][0] -like 'Installing Claude Code*' -and -not $withClaude) { continue }; $i })
    $ui.List.Children.Clear()
    $total = ($show | ForEach-Object { $steps[$_][1] } | Measure-Object -Sum).Sum; $got = 0.0
    foreach ($i in $show) {
        $state = if ($done -or $i -lt $cur) { 'done' } elseif ($i -eq $cur) { 'now' } else { 'next' }
        if ($state -eq 'done') { $got += $steps[$i][1] }
        $row = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal'; Margin = '0,3' }
        $mark = New-Object Windows.Controls.TextBlock -Property @{ FontFamily = 'Segoe Fluent Icons, Segoe MDL2 Assets'; FontSize = 13; Width = 26; VerticalAlignment = 'Center'
            Text = $(switch ($state) { 'done' { [char]0xE73E } 'now' { [char]0xE768 } default { [char]0xE91F } }); Foreground = $(switch ($state) { 'done' { $brush.Done } 'now' { $brush.Accent } default { $brush.Sub } }) }
        $txt = New-Object Windows.Controls.TextBlock -Property @{ Text = $steps[$i][0]; FontSize = 14; Foreground = $(if ($state -eq 'next') { $brush.Sub } else { $brush.Text }); FontWeight = $(if ($state -eq 'now') { 'SemiBold' } else { 'Normal' }) }
        [void]$row.Children.Add($mark); [void]$row.Children.Add($txt); [void]$ui.List.Children.Add($row)
    }
    # the running step fills its share as it runs (up to 90% of it: it may take longer than usual)
    if (-not $done -and $cur -ge 0) { $since = ((Get-Date) - @($lines)[-1].At).TotalMinutes; $got += [Math]::Min($steps[$cur][1] * 0.9, $since) }
    $pct = if ($done) { 100 } elseif ($total) { [Math]::Min(99, 100 * $got / $total) } else { 0 }
    $ui.Bar.Value = $pct
    $mins = [int]((Get-Date) - $script:start).TotalMinutes
    $ui.Elapsed.Text = "$mins min so far"
    $ui.Left.Text = if ($done) { 'Finished' } else { $l = [Math]::Max(1, [int][Math]::Ceiling($total - $got)); "about $l min left" }
    if ($done) {
        $ui.Sub.Text = 'All done. The PC now looks after itself - updates, drivers, cleanup and checks run on their own. The report is in Documents (PC Setup Kit report.txt).'
        $ui.Sub.Foreground = $brush.Done
    }
    elseif ($SetupPid -and -not (Get-Process -Id $SetupPid)) {
        $ui.Sub.Text = "Setup stopped before it finished. Run it again (C:\PCSetupKit\setup.ps1), or look at C:\PCSetupKit\setup.log."
        $ui.Sub.Foreground = $brush.Bad; $ui.Left.Text = 'Stopped'
    }
    $done
}
if ($Test) {
    [void](Update-View)
    "BAR: $([int]$ui.Bar.Value)"; "TIME: $($ui.Elapsed.Text) | $($ui.Left.Text)"; "SUB: $($ui.Sub.Text)"
    foreach ($r in $ui.List.Children) { "STEP: $([int][char]$r.Children[0].Text) $($r.Children[1].Text) $($r.Children[1].FontWeight)" }
    return
}
$timer = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromSeconds(2) }
$timer.Add_Tick({ if (Update-View) { $timer.Stop(); $close = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromMinutes(2) }; $close.Add_Tick({ $win.Close() }); $close.Start() } })
[void](Update-View); $timer.Start()
if ($dark) {   # a dark title bar to match (DWMWA_USE_IMMERSIVE_DARK_MODE)
    Add-Type -Namespace KitProg -Name Dwm -MemberDefinition '[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);'
    $win.Add_SourceInitialized({ $v = 1; [void][KitProg.Dwm]::DwmSetWindowAttribute((New-Object Windows.Interop.WindowInteropHelper $win).Handle, 20, [ref]$v, 4) })
}
[void]$win.ShowDialog()
