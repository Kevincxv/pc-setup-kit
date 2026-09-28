# The Status window (Start menu "Messiah Status" / "PC Setup Kit Status", the tray's Status and its alerts): what needs
# the owner, what waits for the next shutdown, the last check and the scheduled checks - refreshed every few seconds -
# with buttons for the tray's actions. One window: starting it again brings the open one to the front.
# If the window can't open, the text status (status.ps1) opens instead.
param([switch]$Test)   # -Test: build and fill the window once, print what it shows, don't open it (tests)
$cl = "$env:USERPROFILE\.claude"
$ai = if (Test-Path "$cl\ai-enabled.ps1") { & "$cl\ai-enabled.ps1" } else { $true }
$name = if ($ai) { 'Messiah' } else { 'PC Setup Kit' }
$title = "$name Status"
try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    if (-not ('KitDash.W' -as [type])) {
        Add-Type -Namespace KitDash -Name W -MemberDefinition @'
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern IntPtr FindWindow(string c, string t);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern uint ExtractIconEx(string f, int i, IntPtr[] large, IntPtr[] small, uint n);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
'@
    }
    $mutex = New-Object Threading.Mutex($false, 'Local\PCSetupKitStatusWindow')
    if (-not $Test -and -not $mutex.WaitOne(0)) {
        $h = [KitDash.W]::FindWindow([NullString]::Value, $title)
        if ($h -ne [IntPtr]::Zero) { [void][KitDash.W]::ShowWindow($h, 9); [void][KitDash.W]::SetForegroundWindow($h) }
        exit
    }
    . "$cl\status-lib.ps1"

    # Windows' app theme (Settings > Personalization > Colors)
    $light = try { (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop).AppsUseLightTheme -eq 1 } catch { $false }
    $c = if ($light) { @{ Bg = '#F3F3F3'; Card = '#FFFFFF'; Border = '#E5E5E5'; Text = '#1B1B1B'; Sub = '#5C5C5C'; Accent = '#005FB8'; Ok = '#0F7B0F'; Warn = '#9D5D00'; Btn = '#FBFBFB'; BtnHover = '#F0F0F0' } }
    else { @{ Bg = '#1C1C1C'; Card = '#2B2B2B'; Border = '#3A3A3A'; Text = '#F0F0F0'; Sub = '#A0A0A0'; Accent = '#60CDFF'; Ok = '#6CCB5F'; Warn = '#FCE100'; Btn = '#373737'; BtnHover = '#424242' } }

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$title" Width="720" Height="780" MinWidth="480" MinHeight="400" WindowStartupLocation="CenterScreen"
        Background="$($c.Bg)" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="14" Foreground="$($c.Text)" UseLayoutRounding="True">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Margin" Value="0,0,8,8"/><Setter Property="Padding" Value="14,7"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="$($c.Text)"/><Setter Property="Background" Value="$($c.Btn)"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="$($c.Border)" BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="$($c.BtnHover)"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Grid Margin="24,20,24,16">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel Grid.Row="0" Margin="0,0,0,16">
      <TextBlock Text="$name" FontSize="28" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI"/>
      <StackPanel Orientation="Horizontal" Margin="0,6,0,0">
        <Ellipse x:Name="Dot" Width="10" Height="10" Margin="0,0,8,0" VerticalAlignment="Center"/>
        <TextBlock x:Name="Summary" FontSize="15"/>
      </StackPanel>
      <TextBlock x:Name="Sub" Foreground="$($c.Sub)" FontSize="12" Margin="18,2,0,0"/>
    </StackPanel>
    <ScrollViewer Grid.Row="1" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="Cards"/></ScrollViewer>
    <StackPanel Grid.Row="2" Margin="0,12,0,0">
      <WrapPanel x:Name="Buttons"/>
      <TextBlock x:Name="Note" Foreground="$($c.Sub)" FontSize="12" TextWrapping="Wrap"/>
    </StackPanel>
  </Grid>
</Window>
"@
    $win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
    $ui = @{}; foreach ($n in 'Dot', 'Summary', 'Sub', 'Cards', 'Buttons', 'Note') { $ui[$n] = $win.FindName($n) }
    $brush = @{}; foreach ($k in $c.Keys) { $brush[$k] = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($c[$k])) }
    $levelBrush = @{ ok = $brush.Ok; info = $brush.Text; warn = $brush.Warn; dim = $brush.Sub }

    # its own taskbar button and icon (not grouped with PowerShell windows)
    try {
        [void][KitDash.W]::SetCurrentProcessExplicitAppUserModelID("PCSetupKit.Status")
        $src = if ($ai -and (Test-Path "$env:USERPROFILE\.local\bin\claude.exe")) { "$env:USERPROFILE\.local\bin\claude.exe", 0 } else { "$env:SystemRoot\System32\imageres.dll", 110 }
        $big = New-Object IntPtr[] 1
        if ([KitDash.W]::ExtractIconEx($src[0], $src[1], $big, $null, 1) -and $big[0] -ne [IntPtr]::Zero) {
            $win.Icon = [Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon($big[0], [Windows.Int32Rect]::Empty, [Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
        }
    } catch {}

    # title bar in the same theme (Windows 11)
    if (-not $light) { $win.Add_SourceInitialized({ $v = 1; try { [void][KitDash.W]::DwmSetWindowAttribute((New-Object Windows.Interop.WindowInteropHelper $win).Handle, 20, [ref]$v, 4) } catch {} }) }

    $script:claudeVer = $null
    function Update-View {
        $secs = @(Get-KitStatus -ClaudeVersion $script:claudeVer)
        if ($ai -and -not $script:claudeVer) { $m = $secs | Where-Object Title -eq 'Messiah'; if ($m) { $script:claudeVer = ($m.Lines[0].Text -replace '^Claude Code ', '') } }
        # the owner's part first
        $secs = @($secs | Where-Object Title -eq 'Needs you') + @($secs | Where-Object Title -ne 'Needs you')
        $todo = @(($secs | Where-Object Title -eq 'Needs you').Lines | Where-Object Level -eq 'warn')
        $warn = @(($secs | Where-Object Title -eq 'Last background check').Lines | Where-Object Level -eq 'warn')
        if ($todo) { $ui.Summary.Text = "$($todo.Count) thing$(if ($todo.Count -ne 1) { 's' }) need$(if ($todo.Count -eq 1) { 's' }) you"; $ui.Dot.Fill = $brush.Warn }
        elseif ($warn) { $ui.Summary.Text = 'The last check found something - it is being handled'; $ui.Dot.Fill = $brush.Warn }
        else { $ui.Summary.Text = 'All good - nothing needs you'; $ui.Dot.Fill = $brush.Ok }
        $last = ($secs | Where-Object Title -eq 'Last background check').Lines | Where-Object { $_.Text -match '^(Checked|No report)' } | Select-Object -First 1
        $ui.Sub.Text = "$(if ($last) { $last.Text } else { 'No check yet' })  $([char]0xB7)  updates by itself"
        $ui.Cards.Children.Clear()
        foreach ($s in $secs) {
            $card = New-Object Windows.Controls.Border -Property @{ Background = $brush.Card; BorderBrush = $brush.Border; BorderThickness = 1; CornerRadius = 8; Padding = '16,12'; Margin = '0,0,0,10' }
            $sp = New-Object Windows.Controls.StackPanel
            [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $s.Title; FontWeight = 'SemiBold'; Foreground = $brush.Accent; Margin = '0,0,0,6' }))
            foreach ($l in $s.Lines) {
                $t = ($l.Text -replace '^- ', "$([char]0x2022) ") -replace '\s{2,}', '  '
                [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $t; TextWrapping = 'Wrap'; Foreground = $levelBrush[$l.Level]; Margin = '0,1,0,1'; FontSize = $(if ($l.Level -eq 'dim') { 12 } else { 14 }) }))
            }
            $card.Child = $sp
            [void]$ui.Cards.Children.Add($card)
        }
    }

    function Add-Btn($text, [scriptblock]$do) {
        $b = New-Object Windows.Controls.Button -Property @{ Content = $text }
        $b.Add_Click($do); [void]$ui.Buttons.Children.Add($b)
    }
    $ps = { param($file, [switch]$Keep) Start-Process powershell -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass') + @(if ($Keep) { '-NoExit' }) + @('-File', "`"$cl\$file`"")) }
    Add-Btn 'Run maintenance now' {
        Start-Process "$env:SystemRoot\System32\conhost.exe" -ArgumentList "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$cl\claude-bg-maint.ps1`" -Force -Unattended" -WindowStyle Hidden
        $ui.Note.Text = 'Maintenance started in the background - this window shows the result when it finishes.'
    }
    Add-Btn 'Optimize this PC' { & $ps 'optimize.ps1' -Keep }
    if ($ai) { Add-Btn 'Watch maintenance live' { & $ps 'maint-watch.ps1' -Keep } }
    Add-Btn 'Full report' { if (Test-Path "$cl\maint-report.txt") { Start-Process notepad.exe "`"$cl\maint-report.txt`"" } else { $ui.Note.Text = 'No report yet.' } }

    Update-View
    if ($Test) {
        "WINDOW: $($win.Title)"
        "SUMMARY: $($ui.Summary.Text)"
        foreach ($card in $ui.Cards.Children) { $tb = @($card.Child.Children); "CARD: $($tb[0].Text)"; $tb | Select-Object -Skip 1 | ForEach-Object { "  $($_.Text)" } }
        "BUTTONS: $(@($ui.Buttons.Children | ForEach-Object Content) -join ' | ')"
        return
    }
    $timer = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromSeconds(10) }
    $timer.Add_Tick({ try { Update-View } catch {} })
    $timer.Start()
    [void]$win.ShowDialog()
}
catch {
    if ($Test) { throw }
    Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$cl\status.ps1`""
}
