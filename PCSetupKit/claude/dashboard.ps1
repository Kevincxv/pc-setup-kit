# The app window (Start menu / desktop "Messiah" or "PC Setup Kit", the tray icon, its alerts, and at login): what needs
# the owner, what waits for the next shutdown, the maintenance and the scheduled checks - refreshed every few seconds -
# plus everything the tray used to do (sessions, maintenance, reports). One window: starting it again brings the open one
# to the front. Things that need admin rights (sessions, maintenance, optimize) go through the tray, which runs elevated,
# so there's no UAC prompt; without the tray they start directly. If the window can't open, status.ps1 (text) opens instead.
param([switch]$Test, [string]$Page)   # -Test: build and fill every page once, print what they show, don't open (tests)
$cl = "$env:USERPROFILE\.claude"
$ai = if (Test-Path "$cl\ai-enabled.ps1") { & "$cl\ai-enabled.ps1" } else { $true }
$name = if ($ai) { 'Messiah' } else { 'PC Setup Kit' }
$trayDir = "$env:USERPROFILE\Documents\Messiah Tray"
try {
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    if (-not ('KitApp.N' -as [type])) {
        Add-Type -Namespace KitApp -Name N -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern uint RegisterWindowMessage(string s);
[DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
[DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr h, int a, ref int v, int s);
[StructLayout(LayoutKind.Sequential)] public struct MARGINS { public int L, R, T, B; }
[DllImport("dwmapi.dll")] public static extern int DwmExtendFrameIntoClientArea(IntPtr h, ref MARGINS m);
'@
    }
    # one window: a second start hands over to the open one (its handle is in app-window.txt; the title alone isn't
    # unique - Messiah's session consoles are called "Messiah" too)
    $mutex = New-Object Threading.Mutex($false, 'Local\PCSetupKitStatusWindow')
    if (-not $Test -and -not $mutex.WaitOne(0)) {
        $h = [IntPtr][long]("0$(Get-Content "$cl\app-window.txt" -ErrorAction SilentlyContinue)" -replace '\D')
        if ($h -ne [IntPtr]::Zero -and [KitApp.N]::IsWindow($h)) { [void][KitApp.N]::ShowWindow($h, 9); [void][KitApp.N]::SetForegroundWindow($h) }
        exit
    }
    . "$cl\status-lib.ps1"

    # Windows' app theme (Settings > Personalization > Colors). Cards are see-through layers (Windows 11 style), so they
    # work on the Mica backdrop and on the plain background used where Mica isn't available.
    $light = try { (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop).AppsUseLightTheme -eq 1 } catch { $false }
    $c = if ($light) {
        @{ Bg = '#F3F3F3'; Card = '#B3FFFFFF'; CardHover = '#80F9F9F9'; Border = '#0F000000'; Text = '#E4000000'; Sub = '#9E000000'; Accent = '#5B57E8'
            Ok = '#0F7B0F'; Warn = '#9D5D00'; Btn = '#B3FFFFFF'; BtnHover = '#80F9F9F9'; NavSel = '#0A000000'; NavHover = '#06000000'; Grad1 = '#7C5CFF'; Grad2 = '#3E8BF2'; OnAccent = '#FFFFFF'; Chart = '#6D5AE6' }
    } else {
        @{ Bg = '#202020'; Card = '#0DFFFFFF'; CardHover = '#14FFFFFF'; Border = '#19000000'; Text = '#FFFFFF'; Sub = '#C5FFFFFF'; Accent = '#A8A6FF'
            Ok = '#6CCB5F'; Warn = '#FCE100'; Btn = '#0FFFFFFF'; BtnHover = '#15FFFFFF'; NavSel = '#0FFFFFFF'; NavHover = '#0AFFFFFF'; Grad1 = '#7C5CFF'; Grad2 = '#3E8BF2'; OnAccent = '#FFFFFF'; Chart = '#8F7DFF' }   # Chart: validated (dataviz) on each surface
    }
    $icons = "Segoe Fluent Icons, Segoe MDL2 Assets"

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$name" Width="1000" Height="720" MinWidth="720" MinHeight="480" WindowStartupLocation="CenterScreen"
        Background="$($c.Bg)" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="14" Foreground="$($c.Text)"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Margin" Value="0,0,8,8"/><Setter Property="Padding" Value="14,7"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="$($c.Text)"/><Setter Property="Background" Value="$($c.Btn)"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="$($c.Border)" BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="$($c.BtnHover)"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.8"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="AccentBtn" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Foreground" Value="$($c.OnAccent)"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="6" Padding="{TemplateBinding Padding}">
            <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="1,1"><GradientStop Color="$($c.Grad1)" Offset="0"/><GradientStop Color="$($c.Grad2)" Offset="1"/></LinearGradientBrush></Border.Background>
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.9"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.75"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="$($c.Text)"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="0,0,0,4"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="RadioButton">
          <Grid>
            <Border x:Name="b" Background="Transparent" CornerRadius="6" Padding="12,9"><ContentPresenter/></Border>
            <Border x:Name="pip" Width="3" Height="16" CornerRadius="1.5" HorizontalAlignment="Left" Visibility="Collapsed">
              <Border.Background><LinearGradientBrush StartPoint="0,0" EndPoint="0,1"><GradientStop Color="$($c.Grad1)" Offset="0"/><GradientStop Color="$($c.Grad2)" Offset="1"/></LinearGradientBrush></Border.Background>
            </Border>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="$($c.NavHover)"/></Trigger>
            <Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="Background" Value="$($c.NavSel)"/><Setter TargetName="pip" Property="Visibility" Value="Visible"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Switch" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <Grid Width="40" Height="20" Background="Transparent">
            <Border x:Name="track" CornerRadius="10" BorderThickness="1" BorderBrush="$($c.Sub)" Background="Transparent"/>
            <Ellipse x:Name="knob" Width="12" Height="12" Fill="$($c.Sub)" HorizontalAlignment="Left" Margin="4,0,0,0"/>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="track" Property="Background" Value="$($c.Grad1)"/><Setter TargetName="track" Property="BorderBrush" Value="$($c.Grad1)"/>
              <Setter TargetName="knob" Property="Fill" Value="White"/><Setter TargetName="knob" Property="HorizontalAlignment" Value="Right"/><Setter TargetName="knob" Property="Margin" Value="0,0,4,0"/>
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="232"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
    <DockPanel Grid.Column="0" Margin="12,16,8,12">
      <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="10,0,0,22">
        <Image x:Name="Logo" Width="28" Height="28" Margin="0,0,12,0" RenderOptions.BitmapScalingMode="HighQuality"/>
        <TextBlock Text="$name" FontSize="18" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI" VerticalAlignment="Center"/>
      </StackPanel>
      <TextBlock x:Name="Version" DockPanel.Dock="Bottom" Foreground="$($c.Sub)" FontSize="11" Margin="12,0,0,0" TextWrapping="Wrap"/>
      <StackPanel x:Name="NavList"/>
    </DockPanel>
    <Grid Grid.Column="1" Margin="8,16,24,12">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <TextBlock x:Name="PageTitle" FontSize="28" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI" Margin="4,0,0,16"/>
      <ScrollViewer x:Name="Scroll" Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="4,0,8,0"><StackPanel x:Name="Content"/></ScrollViewer>
      <TextBlock x:Name="Note" Grid.Row="2" Foreground="$($c.Sub)" FontSize="12" TextWrapping="Wrap" Margin="4,8,0,0"/>
    </Grid>
  </Grid>
</Window>
"@
    $win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
    $ui = @{}; foreach ($n in 'Logo', 'Version', 'NavList', 'PageTitle', 'Scroll', 'Content', 'Note') { $ui[$n] = $win.FindName($n) }
    $brush = @{}; foreach ($k in $c.Keys) { $brush[$k] = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($c[$k])) }
    $levelBrush = @{ ok = $brush.Ok; info = $brush.Text; warn = $brush.Warn; dim = $brush.Sub }

    # the app's icon (app-icon.ps1 draws it; tray-app.ps1 keeps it up to date) for the window, the taskbar and the logo
    $ico = "$trayDir\app.ico"
    try {
        [void][KitApp.N]::SetCurrentProcessExplicitAppUserModelID("PCSetupKit.App")   # its own taskbar button, not PowerShell's
        if (Test-Path $ico) {
            $dec = New-Object Windows.Media.Imaging.IconBitmapDecoder ([Uri]$ico), 'None', 'OnLoad'
            $win.Icon = $dec.Frames | Where-Object PixelWidth -eq 32 | Select-Object -First 1
            $ui.Logo.Source = $dec.Frames | Sort-Object PixelWidth -Descending | Select-Object -First 1
        }
    } catch {}

    # Windows 11: Mica backdrop and a title bar in the app's theme; elsewhere the plain background stays
    $win.Add_SourceInitialized({
            $h = (New-Object Windows.Interop.WindowInteropHelper $win).Handle
            "$([long]$h)" | Set-Content "$cl\app-window.txt" -Encoding ASCII
            try {
                $v = [int](-not $light); [void][KitApp.N]::DwmSetWindowAttribute($h, 20, [ref]$v, 4)
                if ([Environment]::OSVersion.Version.Build -ge 22621) {
                    $v = 2   # DWMWA_SYSTEMBACKDROP_TYPE = Mica
                    if ([KitApp.N]::DwmSetWindowAttribute($h, 38, [ref]$v, 4) -eq 0) {
                        $m = New-Object KitApp.N+MARGINS; $m.L = $m.R = $m.T = $m.B = -1
                        [void][KitApp.N]::DwmExtendFrameIntoClientArea($h, [ref]$m)
                        [Windows.Interop.HwndSource]::FromHwnd($h).CompositionTarget.BackgroundColor = [Windows.Media.Colors]::Transparent
                        $win.Background = [Windows.Media.Brushes]::Transparent
                    }
                }
            } catch {}
        })

    # --- actions. The tray (elevated) runs what needs admin rights: it listens for this message (tray-hwnd.txt)
    $trayMsg = [KitApp.N]::RegisterWindowMessage('PCSetupKitAppCommand')
    $cmd = @{ NewSession = 1; ShowSessions = 2; HideSessions = 3; RunMaint = 4; Optimize = 5; WatchLive = 6 }
    function Send-Tray([int]$n) {
        $h = [IntPtr][long]("0$(Get-Content "$cl\tray-hwnd.txt" -ErrorAction SilentlyContinue)" -replace '\D')
        $h -ne [IntPtr]::Zero -and [KitApp.N]::IsWindow($h) -and [KitApp.N]::PostMessage($h, $trayMsg, [IntPtr]$n, [IntPtr]::Zero)
    }
    function Say($t) { $ui.Note.Text = $t }
    $psArgs = { param($file, [switch]$Keep) @('-NoProfile', '-ExecutionPolicy', 'Bypass') + @(if ($Keep) { '-NoExit' }) + @('-File', "`"$cl\$file`"") }
    $act = @{
        NewSession   = { if (Send-Tray $cmd.NewSession) { Say 'Opening a new session...' } elseif (Test-Path "$cl\Messiah Session.lnk") { Start-Process "$cl\Messiah Session.lnk" } else { Say 'The session shortcut is missing - run setup again.' } }
        ShowSessions = { if (Send-Tray $cmd.ShowSessions) { Say 'Sessions shown.' } else { Say 'The tray isn''t running - it starts at the next login.'; Start-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue } }
        HideSessions = { if (Send-Tray $cmd.HideSessions) { Say 'Sessions hidden in the tray.' } else { Say 'The tray isn''t running - it starts at the next login.'; Start-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue } }
        RunMaint     = {
            if (-not (Send-Tray $cmd.RunMaint)) { Start-ScheduledTask 'Claude Background Maintenance' -ErrorAction SilentlyContinue }
            Say 'Maintenance started in the background - the result shows here when it finishes.'
        }
        Optimize     = { if (-not (Send-Tray $cmd.Optimize)) { Start-Process powershell -Verb RunAs -ArgumentList (& $psArgs 'optimize.ps1' -Keep) } }
        WatchLive    = { if (-not (Send-Tray $cmd.WatchLive)) { Start-Process powershell -ArgumentList (& $psArgs 'maint-watch.ps1' -Keep) } }
        Report       = { if (Test-Path "$cl\maint-report.txt") { Start-Process notepad.exe "`"$cl\maint-report.txt`"" } else { Say 'No report yet.' } }
        Todo         = { if (Test-Path "$cl\maint-todo.txt") { Start-Process notepad.exe "`"$cl\maint-todo.txt`"" } else { Say 'Nothing needs you right now.' } }
        Journal      = { if (Test-Path "$cl\selfimprove-journal.md") { Start-Process notepad.exe "`"$cl\selfimprove-journal.md`"" } else { Say 'No self-improvement runs yet.' } }
        MakeUsb      = { if (Test-Path "$cl\make-usb.ps1") { Start-Process powershell -Verb RunAs -ArgumentList (& $psArgs 'make-usb.ps1' -Keep); Say 'The install USB maker opened in its own window.' } else { Say 'The USB maker is missing - it comes with the next kit update.' } }
        Logs         = { if (Test-Path "$cl\maint-claude-log") { Start-Process explorer.exe "`"$cl\maint-claude-log`"" } else { Say 'No hidden runs yet.' } }
    }

    # --- building blocks
    function New-Text($t, $brush_ = $brush.Text, $size = 14, $weight = 'Normal', $margin = '0,1,0,1') {
        New-Object Windows.Controls.TextBlock -Property @{ Text = $t; TextWrapping = 'Wrap'; Foreground = $brush_; FontSize = $size; FontWeight = $weight; Margin = $margin }
    }
    function New-Glyph($g, $size = 16, $brush_ = $brush.Text) {
        New-Object Windows.Controls.TextBlock -Property @{ Text = [string][char][int]"0x$g"; FontFamily = $icons; FontSize = $size; Foreground = $brush_; VerticalAlignment = 'Center' }
    }
    function New-Btn($glyph, $text, [scriptblock]$do, [switch]$Accent) {
        $sp = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
        [void]$sp.Children.Add((New-Glyph $glyph 14 $(if ($Accent) { $brush.OnAccent } else { $brush.Text })))
        [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $text; Margin = '8,0,0,0'; VerticalAlignment = 'Center' }))
        $b = New-Object Windows.Controls.Button -Property @{ Content = $sp; Tag = $do; ToolTip = $text }
        $b.Style = $win.FindResource($(if ($Accent) { 'AccentBtn' } else { 'Btn' }))
        $b.Add_Click({ try { & $this.Tag } catch { Say "Couldn't do that: $($_.Exception.Message)" } })
        $b
    }
    function New-Card($title, $glyph, $lines, $buttons, [switch]$Calm) {   # -Calm: warn lines in the normal text color (long text, the header says it)
        $card = New-Object Windows.Controls.Border -Property @{ Background = $brush.Card; BorderBrush = $brush.Border; BorderThickness = 1; CornerRadius = 8; Padding = '18,14'; Margin = '0,0,0,12' }
        $sp = New-Object Windows.Controls.StackPanel
        if ($title) {
            $hd = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal'; Margin = '0,0,0,8' }
            if ($glyph) { [void]$hd.Children.Add((New-Glyph $glyph 16 $brush.Accent)) }
            $t = New-Text $title $brush.Text 15 'SemiBold' '0'; if ($glyph) { $t.Margin = '10,0,0,0' }
            [void]$hd.Children.Add($t); [void]$sp.Children.Add($hd)
        }
        foreach ($l in $lines) {
            if ($l -is [Windows.UIElement]) { [void]$sp.Children.Add($l); continue }
            $t = ($l.Text -replace '^- ', "$([char]0x2022)  ") -replace '\s{2,}', '  '
            [void]$sp.Children.Add((New-Text $t $(if ($Calm -and $l.Level -eq 'warn') { $brush.Text } else { $levelBrush[$l.Level] }) $(if ($l.Level -eq 'dim') { 12 } else { 14 })))
        }
        if ($buttons) {
            $wp = New-Object Windows.Controls.WrapPanel -Property @{ Margin = '0,12,0,-8' }
            foreach ($b in $buttons) { [void]$wp.Children.Add($b) }
            [void]$sp.Children.Add($wp)
        }
        $card.Child = $sp; $card
    }
    function New-Rows($pairs) {   # label | value table (scheduled checks); rows are @(label, value, level)
        if (@($pairs).Count -and @($pairs)[0] -isnot [array]) { $pairs = , @($pairs) }   # one row arrives unrolled by PowerShell
        $g = New-Object Windows.Controls.Grid
        [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' }))
        [void]$g.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
        $i = 0
        foreach ($p in $pairs) {
            [void]$g.RowDefinitions.Add((New-Object Windows.Controls.RowDefinition -Property @{ Height = 'Auto' }))
            $a = New-Text $p[0] $brush.Sub 14 'Normal' '0,4,24,4'; [Windows.Controls.Grid]::SetRow($a, $i)
            $b = New-Text $p[1] $levelBrush[$p[2]] 14 'Normal' '0,4,0,4'; [Windows.Controls.Grid]::SetRow($b, $i); [Windows.Controls.Grid]::SetColumn($b, 1)
            [void]$g.Children.Add($a); [void]$g.Children.Add($b); $i++
        }
        $g
    }
    function Sec($secs, $t) { $secs | Where-Object { $_.Title -like "$t*" } | Select-Object -First 1 }

    # --- History: health over time (health-history.json, written by trends.ps1 at every check). One measure per chart,
    # each with its own scale (never two on one axis); one line, so the title names it (no legend); the current value as
    # the big number; the usual level as a faint dashed line; every point has a tooltip (date and value).
    function Get-HealthHistory([string]$Name = 'health-history.json') { $j = try { Get-Content "$cl\$Name" -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null }; @($j | ForEach-Object { $_ }) }   # (also perf-history.json, net-history.json)
    function Median($v) { $s = @($v | Sort-Object); if (-not $s) { return $null }; $m = [int][Math]::Floor($s.Count / 2); if ($s.Count % 2) { $s[$m] } else { ($s[$m - 1] + $s[$m]) / 2 } }
    function New-Chart($title, $unit, $pts, [int]$decimals = 0, [double]$minSpan = 1) {   # minSpan: the smallest range shown (small wobbles stay small)
        $sp = New-Object Windows.Controls.StackPanel
        $pts = @($pts | Where-Object { $null -ne $_.V } | Sort-Object D | Select-Object -Last 60)
        $fmt = { param($v) "$([Math]::Round([double]$v, $decimals))$unit" }
        if ($pts.Count -lt 2) {
            [void]$sp.Children.Add((New-Text $(if ($pts) { & $fmt $pts[-1].V } else { '-' }) $brush.Text 26 'SemiBold' '0'))
            [void]$sp.Children.Add((New-Text 'Collecting - the chart shows after a few checks.' $brush.Sub 12 'Normal' '0,4,0,0'))
            $sp.Tag = "CHART: $title | $($pts.Count) point(s)"
            return (New-Card $title $null @($sp) $null)
        }
        $vals = @($pts | ForEach-Object { [double]$_.V }); $usual = Median $vals
        $hero = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
        [void]$hero.Children.Add((New-Text (& $fmt $vals[-1]) $brush.Text 26 'SemiBold' '0'))
        [void]$hero.Children.Add((New-Text "   usual $(& $fmt $usual)" $brush.Sub 12 'Normal' '0,0,0,5'))
        $hero.Children[1].VerticalAlignment = 'Bottom'; [void]$sp.Children.Add($hero)
        $W = 270; $H = 84; $lo = ($vals | Measure-Object -Minimum).Minimum; $hi = ($vals | Measure-Object -Maximum).Maximum
        if ($hi - $lo -lt $minSpan) { $mid = ($hi + $lo) / 2; $hi = $mid + $minSpan / 2; $lo = $mid - $minSpan / 2 }
        $pad = ($hi - $lo) * 0.12; $lo -= $pad; $hi += $pad
        $t0 = $pts[0].D.Ticks; $t1 = $pts[-1].D.Ticks; if ($t1 -eq $t0) { $t1 = $t0 + 1 }
        $X = { param($d) ($d.Ticks - $t0) / ($t1 - $t0) * ($W - 12) + 6 }; $Y = { param($v) $H - 4 - ($v - $lo) / ($hi - $lo) * ($H - 8) }
        $cv = New-Object Windows.Controls.Canvas -Property @{ Width = $W; Height = $H; Margin = '0,10,0,0'; HorizontalAlignment = 'Left'; ClipToBounds = $false }
        foreach ($gy in 4, ($H - 4)) {   # recessive frame lines, top and bottom of the range
            [void]$cv.Children.Add((New-Object Windows.Shapes.Line -Property @{ X1 = 0; X2 = $W; Y1 = $gy; Y2 = $gy; Stroke = $brush.Border; StrokeThickness = 1 }))
        }
        $u = & $Y $usual   # the usual level
        [void]$cv.Children.Add((New-Object Windows.Shapes.Line -Property @{ X1 = 0; X2 = $W; Y1 = $u; Y2 = $u; Stroke = $brush.Sub; StrokeThickness = 1; Opacity = 0.5; StrokeDashArray = (New-Object Windows.Media.DoubleCollection (, [double[]](4, 3))) }))
        $line = New-Object Windows.Shapes.Polyline -Property @{ Stroke = $brush.Chart; StrokeThickness = 2; StrokeLineJoin = 'Round'; StrokeStartLineCap = 'Round'; StrokeEndLineCap = 'Round' }
        foreach ($p in $pts) { [void]$line.Points.Add((New-Object Windows.Point (& $X $p.D), (& $Y ([double]$p.V)))) }
        [void]$cv.Children.Add($line)
        $bg = if ($win.Background -is [Windows.Media.SolidColorBrush] -and $win.Background.Color.A -eq 255) { $win.Background } else { New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($c.Bg)) }
        $last = New-Object Windows.Shapes.Ellipse -Property @{ Width = 10; Height = 10; Fill = $brush.Chart; Stroke = $bg; StrokeThickness = 2 }   # the current value, ringed
        [Windows.Controls.Canvas]::SetLeft($last, (& $X $pts[-1].D) - 5); [Windows.Controls.Canvas]::SetTop($last, (& $Y $vals[-1]) - 5); [void]$cv.Children.Add($last)
        foreach ($p in $pts) {   # hover: an invisible target bigger than the point
            $hit = New-Object Windows.Shapes.Ellipse -Property @{ Width = 16; Height = 16; Fill = [Windows.Media.Brushes]::Transparent; ToolTip = "$($p.D.ToString('ddd MMM d, h:mm tt')):  $(& $fmt $p.V)"; Cursor = 'Hand' }
            [Windows.Controls.Canvas]::SetLeft($hit, (& $X $p.D) - 8); [Windows.Controls.Canvas]::SetTop($hit, (& $Y ([double]$p.V)) - 8); [void]$cv.Children.Add($hit)
        }
        [void]$sp.Children.Add($cv)
        $axis = New-Object Windows.Controls.DockPanel -Property @{ Width = $W; HorizontalAlignment = 'Left'; Margin = '0,4,0,0' }
        $r = New-Text $pts[-1].D.ToString('MMM d') $brush.Sub 11 'Normal' '0'; [Windows.Controls.DockPanel]::SetDock($r, 'Right'); [void]$axis.Children.Add($r)
        [void]$axis.Children.Add((New-Text "$($pts[0].D.ToString('MMM d'))   $([char]0xB7)   range $(& $fmt ($vals | Measure-Object -Minimum).Minimum) - $(& $fmt ($vals | Measure-Object -Maximum).Maximum)" $brush.Sub 11 'Normal' '0'))
        [void]$sp.Children.Add($axis)
        $sp.Tag = "CHART: $title | $($pts.Count) points, now $(& $fmt $vals[-1]), usual $(& $fmt $usual)"
        New-Card $title $null @($sp) $null
    }
    # What maintenance changed, newest first (from the last 30 saved reports; routine "all fine" lines left out)
    function Get-MaintTimeline {
        $rx = 'PC Setup Kit updated|went back to|re-applied|Updated app|installed|Driver:|Driver rolled back|re-applied|Removed|Created a monthly|Restore point created|fetched it again|Restart check: .*finished at'
        foreach ($f in Get-ChildItem "$cl\maint-history\report-*.txt" -ErrorAction SilentlyContinue | Sort-Object Name -Descending) {
            $l = @(Get-Content $f.FullName -Encoding UTF8 -ErrorAction SilentlyContinue)
            $when = if ($l -and $l[0] -match '^Checked (.+?) in ') { $Matches[1] } else { $f.LastWriteTime.ToString('g') }
            foreach ($x in $l | Where-Object { $_ -match $rx -and $_ -notmatch 'up to date|all still applied' }) { [pscustomobject]@{ When = $when; Text = $x.Trim() } }
        }
    }
    function Get-Notes { @(Get-Content "$cl\notifications.log" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\d{4}-\d\d-\d\d \d\d:\d\d\|' } | ForEach-Object { $a = $_ -split '\|', 2; [pscustomobject]@{ When = [datetime]$a[0]; Text = $a[1] } }) }

    # --- settings (kit-options.txt next to the scripts; the tray reads "openatlogin")
    function Get-Opt($k, $default) { $l = @(Get-Content "$cl\kit-options.txt" -ErrorAction SilentlyContinue) -match "^\s*$k\s*=" | Select-Object -First 1; if ($l) { ($l -split '=', 2)[1].Trim() } else { $default } }
    function Set-Opt($k, $v) {
        $f = "$cl\kit-options.txt"
        $lines = @(Get-Content $f -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch "^\s*$k\s*=" }) + "$k=$v"
        [IO.File]::WriteAllLines($f, [string[]]$lines)
    }

    # --- pages
    $pages = [ordered]@{ Home = 'E80F' }
    if ($ai) { $pages.Sessions = 'E756' }
    $pages.Maintenance = 'E90F'; $pages.History = 'E81C'; $pages.Schedule = 'E787'; $pages.Notifications = 'EA8F'; $pages.Settings = 'E713'

    function Build-Page($p, $secs) {
        $out = New-Object Collections.ArrayList
        $needs = Sec $secs 'Needs you'; $wait = Sec $secs 'Waiting for'; $last = Sec $secs 'Last background check'
        $hidden = Sec $secs 'Hidden Claude'; $sched = Sec $secs 'Scheduled checks'; $mess = Sec $secs 'Messiah'
        switch ($p) {
            'Home' {
                $todo = @($needs.Lines | Where-Object Level -eq 'warn'); $warn = @($last.Lines | Where-Object Level -eq 'warn')
                $state = if ($todo) { 'warn', 'E7BA', "$($todo.Count) thing$(if ($todo.Count -ne 1) { 's' }) need$(if ($todo.Count -eq 1) { 's' }) you" }
                elseif ($warn) { 'warn', 'E7BA', 'The last check found something - it is being handled' }
                else { 'ok', 'E73E', 'All good - nothing needs you' }
                $when = $last.Lines | Where-Object { $_.Text -match '^(Checked|No report)' } | Select-Object -First 1
                # the status at a glance: colored badge, one line, when it was checked
                $hero = New-Object Windows.Controls.Grid
                [void]$hero.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' }))
                [void]$hero.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
                $badge = New-Object Windows.Controls.Border -Property @{ Width = 48; Height = 48; CornerRadius = 24; Background = $levelBrush[$state[0]]; Margin = '0,0,16,0'; VerticalAlignment = 'Center' }
                $badge.Child = New-Glyph $state[1] 22 $(if ($light) { [Windows.Media.Brushes]::White } else { [Windows.Media.Brushes]::Black }); $badge.Child.HorizontalAlignment = 'Center'
                $txt = New-Object Windows.Controls.StackPanel -Property @{ VerticalAlignment = 'Center' }
                [void]$txt.Children.Add((New-Text $state[2] $brush.Text 20 'SemiBold' '0'))
                [void]$txt.Children.Add((New-Text "$(if ($when) { $when.Text } else { 'No check yet' })  $([char]0xB7)  updates by itself" $brush.Sub 12 'Normal' '0,2,0,0'))
                [Windows.Controls.Grid]::SetColumn($txt, 1); [void]$hero.Children.Add($badge); [void]$hero.Children.Add($txt)
                [void]$out.Add((New-Card $null $null @($hero) @((New-Btn 'E768' 'Run maintenance now' $act.RunMaint -Accent), (New-Btn 'E945' 'Optimize this PC' $act.Optimize))))
                [void]$out.Add((New-Card 'Needs you' 'E7BA' $needs.Lines @(if ($todo) { New-Btn 'E8A5' 'Open the to-do list' $act.Todo }) -Calm))
                [void]$out.Add((New-Card $wait.Title 'E777' $wait.Lines $null))
                if ($ai -and $mess) {
                    $n = @($mess.Lines | Where-Object { $_.Text -like 'Session*' }).Count
                    $line = @{ Text = $(if ($n) { "$n session$(if ($n -ne 1) { 's' }) running - $($mess.Lines[0].Text)" } else { 'No session open' }); Level = $(if ($n) { 'info' } else { 'warn' }) }
                    $btns = @((New-Btn 'E890' 'Show sessions' $act.ShowSessions), (New-Btn 'E710' 'New session' $act.NewSession))
                    [void]$out.Add((New-Card 'Messiah' 'E756' @($line) $btns))
                }
            }
            'Sessions' {
                $lines = @($mess.Lines | Select-Object -Skip 1)
                [void]$out.Add((New-Card 'Sessions' 'E756' $lines @((New-Btn 'E710' 'New session' $act.NewSession -Accent), (New-Btn 'E890' 'Show sessions' $act.ShowSessions), (New-Btn 'ED1A' 'Hide sessions' $act.HideSessions))))
                [void]$out.Add((New-Card 'Claude Code' 'E946' @($mess.Lines[0], @{ Text = 'Updates itself; an idle hidden session is moved onto a new version automatically.'; Level = 'dim' }) $null))
                [void]$out.Add((New-Card 'Minimize = tray' 'E74A' @(@{ Text = 'Minimizing a session window hides it in the tray; the session keeps running. Closing the window ends it.'; Level = 'info' }) $null))
            }
            'Maintenance' {
                [void]$out.Add((New-Card 'Last background check' 'E9D9' $last.Lines @((New-Btn 'E768' 'Run maintenance now' $act.RunMaint -Accent), (New-Btn 'E8A5' 'Full report' $act.Report))))
                if ($hidden) { [void]$out.Add((New-Card 'Hidden Claude maintenance' 'E90F' (@($hidden.Lines) + @(@{ Text = 'About 2 minutes after each login: /maintain when something needs judgment, then /self-improve at most once a day.'; Level = 'dim' })) @((New-Btn 'E890' 'Watch live' $act.WatchLive), (New-Btn 'E8F1' 'Self-improvement journal' $act.Journal), (New-Btn 'E8B7' 'Run logs' $act.Logs)))) }
                [void]$out.Add((New-Card 'Needs you' 'E7BA' $needs.Lines @(New-Btn 'E8A5' 'Open the to-do list' $act.Todo) -Calm))
                [void]$out.Add((New-Card 'Install USB' 'E88E' @(@{ Text = 'Makes a USB stick that installs Windows 11 on a new PC (or reinstalls this one) and sets it up by itself - Windows from Microsoft, the newest kit, and optionally this PC''s settings. The stick is erased; takes 20-40 minutes.'; Level = 'dim' }) @(New-Btn 'E88E' 'Make an install USB' $act.MakeUsb)))
            }
            'History' {
                $hh = Get-HealthHistory
                $pt = { param($field, [switch]$PerBoot)
                    $rows = @($hh | Where-Object { $null -ne $_.$field })
                    if ($PerBoot) { $rows = @($rows | Where-Object bootAt | Group-Object bootAt | ForEach-Object { $_.Group[-1] }); $rows | ForEach-Object { [pscustomobject]@{ D = [datetime]$_.bootAt; V = $_.$field } } }
                    else { $rows | ForEach-Object { [pscustomobject]@{ D = [datetime]$_.date; V = $_.$field } } } }
                $grid = New-Object Windows.Controls.Primitives.UniformGrid -Property @{ Columns = 2 }
                # games (game-perf.ps1, while playing): the most played game's frame rate, and the card's heat under load
                $perf = Get-HealthHistory 'perf-history.json'; $net = Get-HealthHistory 'net-history.json'
                $top = $perf | Group-Object game | Sort-Object Count -Descending | Select-Object -First 1
                $gp = { param($rows, $field) @($rows | Where-Object { $null -ne $_.$field } | ForEach-Object { [pscustomobject]@{ D = [datetime]$_.date; V = $_.$field } }) }
                $charts = @((New-Chart 'Start-up time' ' s' (& $pt boot -PerBoot) 1 10), (New-Chart 'Free space on C:' ' GB' (& $pt freeGB) 0 20),
                    (New-Chart 'Graphics card at idle' ' C' (& $pt gpuIdle) 0 10), (New-Chart 'SSD temperature' ' C' (& $pt ssdTemp) 0 10),
                    (New-Chart "Frame rate$(if ($top) { " - $($top.Name)" })" ' fps' (& $gp $(if ($top) { $top.Group }) fps) 0 20),
                    (New-Chart "1% low frame rate$(if ($top) { " - $($top.Name)" })" ' fps' (& $gp $(if ($top) { $top.Group }) low1) 0 20),
                    (New-Chart 'Graphics card while gaming' ' C' (& $gp $perf gpuTemp) 0 10), (New-Chart 'Internet ping' ' ms' (& $gp $net ping) 0 10))
                foreach ($ch in $charts) {
                    $ch.Margin = '0,0,12,12'; [void]$grid.Children.Add($ch)
                }
                [void]$out.Add($grid)
                # each game: its latest sample next to its usual (the median of its samples)
                $games = @($perf | Group-Object game | Sort-Object { ($_.Group | Select-Object -Last 1).date } -Descending | ForEach-Object {
                        $l = $_.Group | Select-Object -Last 1; $u = Median @($_.Group | ForEach-Object { [double]$_.low1 })
                        , @(([datetime]$l.date).ToString('MMM d'), "$($_.Name): $([int]$l.fps) fps, 1% low $([int]$l.low1) fps (usual $([int]$u))$(if ($null -ne $l.gpuTemp) { ", card $($l.gpuTemp) C" }) - $($_.Count) sample(s)", 'info') })
                if (-not $games) { $games = , @('', 'Nothing recorded yet - a minute of each game is measured while you play (at most every 3 hours).', 'dim') }
                [void]$out.Add((New-Card 'Games' 'E7FC' @(New-Rows $games) $null))
                $tl = @(Get-MaintTimeline | Select-Object -First 40)
                $rows = if ($tl) { $tl | ForEach-Object { , @($_.When, $_.Text, 'info') } } else { , @('', 'Nothing changed yet - the checks found everything in order.', 'dim') }
                [void]$out.Add((New-Card 'What maintenance did' 'E90F' @(New-Rows $rows) @(New-Btn 'E8A5' 'Latest report' $act.Report)))
                [void]$out.Add((New-Card $null $null @(@{ Text = 'Recorded at every check (at each login and once a day); games while you play. Idle temperatures are taken only while the graphics card is idle, so a game never skews them.'; Level = 'dim' }) $null))
            }
            'Notifications' {
                $notes = @(Get-Notes | Sort-Object When -Descending | Select-Object -First 60)
                $rows = if ($notes) { $notes | ForEach-Object { , @($_.When.ToString('ddd MMM d, h:mm tt'), $_.Text, 'info') } } else { , @('', 'No alerts yet.', 'dim') }
                $clear = New-Btn 'E74D' 'Clear' { [IO.File]::WriteAllText("$cl\notifications.log", ''); $script:shown = $null; Update-View -Force }
                [void]$out.Add((New-Card 'Alerts' 'EA8F' @(New-Rows $rows) @(if ($notes) { $clear })))
                [void]$out.Add((New-Card $null $null @(@{ Text = "The small notes $name shows in the corner of the screen (never over a game), kept here because they close by themselves."; Level = 'dim' }) $null))
            }
            'Schedule' {
                $pairs = foreach ($l in $sched.Lines) {
                    if ($l.Text -match '^([^:]+):\s+(.*)$') { , @($Matches[1], $Matches[2], $l.Level) } else { , @('', $l.Text, $l.Level) }
                }
                [void]$out.Add((New-Card 'Scheduled checks' 'E787' @(New-Rows $pairs) $null))
                [void]$out.Add((New-Card $null $null @(@{ Text = 'Everything here runs by itself. Checks wait while a game is running, and anything that needs a restart finishes the next time you turn the PC off.'; Level = 'dim' }) $null))
            }
            'Settings' {
                $row = New-Object Windows.Controls.DockPanel
                $sw = New-Object Windows.Controls.CheckBox -Property @{ IsChecked = ((Get-Opt 'openatlogin' 'off') -eq 'on'); VerticalAlignment = 'Center' }
                $sw.Style = $win.FindResource('Switch'); [Windows.Controls.DockPanel]::SetDock($sw, 'Right')
                $sw.Add_Click({ Set-Opt 'openatlogin' $(if ($this.IsChecked) { 'on' } else { 'off' }); Say "Saved - $(if ($this.IsChecked) { "this window opens at login" } else { "$name starts in the hidden tray at login" })." })
                $lbl = New-Object Windows.Controls.StackPanel
                [void]$lbl.Children.Add((New-Text "Open $name when I log in" $brush.Text 14 'Normal' '0'))
                [void]$lbl.Children.Add((New-Text "Off: $name starts in the hidden tray (^ next to the clock) and works on its own. On: this window also opens once per start-up (not while a game is fullscreen)." $brush.Sub 12 'Normal' '0,2,0,0'))
                [void]$row.Children.Add($sw); [void]$row.Children.Add($lbl)
                [void]$out.Add((New-Card 'Start-up' 'E7E8' @($row) $null))
                # gaming options (kit-options.txt; gaming-check.ps1 / nvidia-settings.ps1 apply them at the next check)
                $opts = @()
                foreach ($o in @(@('defenderexclusions', 'off', 'Microsoft Defender skips my game folders', 'Less stutter while games load and build their shaders. A small security trade-off: files in those folders are no longer scanned. Off by default.'),
                        @('nvidiasettings', 'on', 'NVIDIA driver settings for games', 'Low-latency mode on and an unlimited shader cache (less stutter), set in the driver for every game. Off: no longer applied (the driver keeps the last values until changed in the NVIDIA Control Panel).'))) {
                    $r2 = New-Object Windows.Controls.DockPanel -Property @{ Margin = '0,0,0,10' }
                    $s2 = New-Object Windows.Controls.CheckBox -Property @{ IsChecked = ((Get-Opt $o[0] $o[1]) -eq 'on'); VerticalAlignment = 'Center'; Tag = $o[0] }
                    $s2.Style = $win.FindResource('Switch'); [Windows.Controls.DockPanel]::SetDock($s2, 'Right')
                    $s2.Add_Click({ Set-Opt $this.Tag $(if ($this.IsChecked) { 'on' } else { 'off' }); Say 'Saved - applied at the next check (or click Run maintenance now).' })
                    $l2 = New-Object Windows.Controls.StackPanel
                    [void]$l2.Children.Add((New-Text $o[2] $brush.Text 14 'Normal' '0')); [void]$l2.Children.Add((New-Text $o[3] $brush.Sub 12 'Normal' '0,2,0,0'))
                    [void]$r2.Children.Add($s2); [void]$r2.Children.Add($l2); $opts += $r2
                }
                [void]$out.Add((New-Card 'Gaming' 'E7FC' $opts $null))
                $kv = Get-Content 'C:\PCSetupKit\kit-version.txt' -TotalCount 1 -ErrorAction SilentlyContinue
                [void]$out.Add((New-Card 'About' 'E946' @(
                            @{ Text = "$name - part of the PC Setup Kit$(if ($kv) { " $kv" })"; Level = 'info' },
                            @{ Text = 'Keeps this PC updated, tuned and checked by itself. Updates itself from the published kit.'; Level = 'dim' }) $null))
            }
        }
        $out
    }

    $script:page = if ($Page -and $pages.Contains($Page)) { $Page } else { 'Home' }
    $script:shown = $null; $script:claudeVer = $null; $navItems = @{}
    function Update-View([switch]$Force) {
        $secs = @(Get-KitStatus -ClaudeVersion $script:claudeVer)
        if ($ai -and -not $script:claudeVer) { $m = Sec $secs 'Messiah'; if ($m) { $script:claudeVer = ($m.Lines[0].Text -replace '^Claude Code ', '') } }
        # the nav shows how many things need the owner
        $todo = @((Sec $secs 'Needs you').Lines | Where-Object Level -eq 'warn').Count
        $navItems.Home.Tag.Text = if ($todo) { "$todo" } else { '' }; $navItems.Home.Tag.Parent.Visibility = if ($todo) { 'Visible' } else { 'Collapsed' }
        $ui.Version.Text = @(if ($ai -and $script:claudeVer) { "Claude Code $script:claudeVer" }; Get-Content 'C:\PCSetupKit\kit-version.txt' -TotalCount 1 -ErrorAction SilentlyContinue) -join "`n"
        # redraw only when something changed (no flicker; the scroll position stays while reading)
        $sig = "$script:page`n" + (($secs | ForEach-Object { $_.Title; $_.Lines | ForEach-Object { "$($_.Level)|$($_.Text)" } }) -join "`n") +
            "`n" + ((Get-Item "$cl\health-history.json", "$cl\notifications.log", "$cl\maint-history" -ErrorAction SilentlyContinue | ForEach-Object { $_.LastWriteTime.Ticks }) -join ',')
        if (-not $Force -and $sig -eq $script:shown) { return }
        $script:shown = $sig
        $ui.PageTitle.Text = if ($script:page -eq 'Home') { 'Overview' } else { $script:page }
        $ui.Content.Children.Clear()
        foreach ($el in (Build-Page $script:page $secs)) { [void]$ui.Content.Children.Add($el) }
    }

    foreach ($p in $pages.Keys) {
        $rb = New-Object Windows.Controls.RadioButton -Property @{ GroupName = 'nav'; Tag = $p }
        $rb.Style = $win.FindResource('Nav')
        $row = New-Object Windows.Controls.DockPanel
        $count = New-Object Windows.Controls.Border -Property @{ CornerRadius = 8; Background = $brush.Warn; Padding = '6,0'; MinWidth = 16; Visibility = 'Collapsed'; VerticalAlignment = 'Center' }
        $count.Child = New-Text '' $(if ($light) { [Windows.Media.Brushes]::White } else { [Windows.Media.Brushes]::Black }) 11 'SemiBold' '0'; $count.Child.HorizontalAlignment = 'Center'
        [Windows.Controls.DockPanel]::SetDock($count, 'Right'); [void]$row.Children.Add($count)
        [void]$row.Children.Add((New-Glyph $pages[$p] 16)); $row.Children[1].Margin = '0,0,14,0'
        [void]$row.Children.Add((New-Text $(if ($p -eq 'Home') { 'Overview' } else { $p }) $brush.Text 14 'Normal' '0'))
        $rb.Content = $row
        $navItems[$p] = [pscustomobject]@{ Button = $rb; Tag = $count.Child }
        $rb.Add_Checked({ $script:page = $this.Tag; $ui.Note.Text = ''; $ui.Scroll.ScrollToTop(); Update-View -Force })
        [void]$ui.NavList.Children.Add($rb)
    }

    if ($Test) {
        "WINDOW: $($win.Title)"
        foreach ($p in $pages.Keys) {
            $script:page = $p; Update-View -Force
            "PAGE: $($ui.PageTitle.Text)"
            foreach ($card in @($ui.Content.Children | ForEach-Object { if ($_ -is [Windows.Controls.Primitives.UniformGrid]) { $_.Children } else { $_ } })) {
                $all = @($card.Child.Children)
                $chart = $all | Where-Object { "$($_.Tag)" -like 'CHART:*' } | Select-Object -First 1
                if ($chart) { "  $($chart.Tag)"; continue }
                $head = $all[0]; if ($head -is [Windows.Controls.StackPanel] -and $head.Orientation -eq 'Horizontal') { "CARD: $(@($head.Children)[-1].Text)"; $all = $all | Select-Object -Skip 1 } else { 'CARD: -' }
                foreach ($el in $all) {
                    if ($el -is [Windows.Controls.TextBlock]) { "  $($el.Text)" }
                    elseif ($el -is [Windows.Controls.WrapPanel]) { "  BUTTONS: $(@($el.Children | ForEach-Object { $_.ToolTip }) -join ' | ')" }
                    elseif ($el -is [Windows.Controls.Grid] -and $el.RowDefinitions.Count) { $t = @($el.Children | ForEach-Object Text); for ($i = 0; $i -lt $t.Count; $i += 2) { "  $($t[$i]): $($t[$i + 1])" } }
                    else { $txt = @($el.Children | ForEach-Object { if ($_ -is [Windows.Controls.TextBlock]) { $_.Text } else { $_.Children | Where-Object { $_ -is [Windows.Controls.TextBlock] } | ForEach-Object Text } }) -join ' / '; "  $txt" }
                }
            }
        }
        "NAV: $(@($pages.Keys) -join ' | ')"
        return
    }
    $navItems[$script:page].Button.IsChecked = $true
    $timer = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromSeconds(10) }
    $timer.Add_Tick({ try { Update-View } catch {} })
    $timer.Start()
    [void]$win.ShowDialog()
}
catch {
    if ($Test) { throw }
    Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$cl\status.ps1`""
}
