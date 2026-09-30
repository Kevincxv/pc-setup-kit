# The app window, Messiah (Start menu / desktop "Messiah", the tray icon, its alerts, and at login): what needs
# the owner, what waits for the next shutdown, the maintenance and the scheduled checks - refreshed every few seconds -
# plus everything the tray used to do (sessions, maintenance, reports). One window: starting it again brings the open one
# to the front. Things that need admin rights (sessions, maintenance, optimize) go through the tray, which runs elevated,
# so there's no UAC prompt; without the tray they start directly. If the window can't open, status.ps1 (text) opens instead.
param([switch]$Test, [string]$Page)   # -Test: build and fill every page once, print what they show, don't open (tests); -Page: open on that page (Welcome: after setup)
$cl = "$env:USERPROFILE\.claude"
$ai = if (Test-Path "$cl\ai-enabled.ps1") { & "$cl\ai-enabled.ps1" } else { $true }
$name = 'Messiah'   # one app; the AI assistant (Claude) is a switch in Settings (ai-toggle.ps1)
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
        Title="$name" Width="1100" Height="760" MinWidth="760" MinHeight="520" WindowStartupLocation="CenterScreen"
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
            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="$($c.Accent)"/></Trigger>
            <Trigger Property="IsPressed" Value="True"><Setter TargetName="b" Property="Opacity" Value="0.8"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="SmallBtn" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Padding" Value="10,4"/><Setter Property="FontSize" Value="13"/><Setter Property="Margin" Value="0,0,6,0"/>
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
            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="Background" Value="$($c.NavSel)"/></Trigger>
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
    <Style x:Key="ThinThumb" TargetType="Thumb">
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Thumb"><Border x:Name="t" CornerRadius="3" Background="$($c.Sub)" Opacity="0.35"/>
          <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="t" Property="Opacity" Value="0.6"/></Trigger></ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="10"/><Setter Property="MinWidth" Value="10"/><Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Track x:Name="PART_Track" IsDirectionReversed="True"><Track.Thumb><Thumb Style="{StaticResource ThinThumb}" Margin="2,2"/></Track.Thumb></Track>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="$($c.Bg)"/><Setter Property="Foreground" Value="$($c.Text)"/><Setter Property="BorderBrush" Value="$($c.Border)"/><Setter Property="Padding" Value="8,5"/>
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
      <Button x:Name="AiPill" DockPanel.Dock="Bottom" HorizontalAlignment="Left" Margin="8,0,0,10" Padding="10,5" FontSize="12" ToolTip="The AI assistant (Claude) - on or off in Settings"/>
      <StackPanel x:Name="NavList"/>
    </DockPanel>
    <Grid Grid.Column="1" Margin="8,16,24,12">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <StackPanel Margin="4,0,0,18">
        <TextBlock x:Name="PageTitle" FontSize="28" FontWeight="SemiBold" FontFamily="Segoe UI Variable Display, Segoe UI"/>
        <TextBlock x:Name="PageSub" Foreground="$($c.Sub)" FontSize="13" TextWrapping="Wrap" Margin="0,2,0,0"/>
      </StackPanel>
      <ScrollViewer x:Name="Scroll" Grid.Row="1" VerticalScrollBarVisibility="Auto" Padding="4,0,8,0"><StackPanel x:Name="Content" MaxWidth="1100" HorizontalAlignment="Stretch"/></ScrollViewer>
      <Border x:Name="NoteBar" Grid.Row="2" Visibility="Collapsed" Margin="4,10,8,0" Padding="14,9" CornerRadius="6" Background="$($c.Card)" BorderBrush="$($c.Accent)" BorderThickness="1,1,1,1">
        <DockPanel>
          <TextBlock x:Name="NoteGlyph" DockPanel.Dock="Left" FontFamily="$icons" FontSize="14" Foreground="$($c.Accent)" VerticalAlignment="Center" Margin="0,0,10,0" Text="&#xE946;"/>
          <TextBlock x:Name="Note" FontSize="13" TextWrapping="Wrap" VerticalAlignment="Center"/>
        </DockPanel>
      </Border>
    </Grid>
  </Grid>
</Window>
"@
    $win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
    $ui = @{}; foreach ($n in 'Logo', 'Version', 'NavList', 'PageTitle', 'PageSub', 'Scroll', 'Content', 'Note', 'NoteBar', 'AiPill') { $ui[$n] = $win.FindName($n) }
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
    $cmd = @{ NewSession = 1; ShowSessions = 2; HideSessions = 3; RunMaint = 4; Optimize = 5; WatchLive = 6; ApplyTweaks = 7; Repair = 8; Rollback = 9; AiOn = 10; AiOff = 11; GpuRollback = 12 }
    function Send-Tray([int]$n) {
        $h = [IntPtr][long]("0$(Get-Content "$cl\tray-hwnd.txt" -ErrorAction SilentlyContinue)" -replace '\D')
        $h -ne [IntPtr]::Zero -and [KitApp.N]::IsWindow($h) -and [KitApp.N]::PostMessage($h, $trayMsg, [IntPtr]$n, [IntPtr]::Zero)
    }
    # a short note in the bar at the bottom; it goes away by itself after 12 seconds
    $noteTimer = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromSeconds(12) }
    $noteTimer.Add_Tick({ $ui.NoteBar.Visibility = 'Collapsed'; $noteTimer.Stop() })
    function Say($t) { $ui.Note.Text = $t; $ui.NoteBar.Visibility = if ($t) { 'Visible' } else { 'Collapsed' }; $noteTimer.Stop(); if ($t) { $noteTimer.Start() } }
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
        Repair       = { if (Send-Tray $cmd.Repair) { Say 'Repairing: the current version installs again (a window shows the result).' } else { Start-Process powershell -Verb RunAs -ArgumentList ((& $psArgs 'kit-update.ps1' -Keep) + '-Reinstall') } }
        Rollback     = { if (-not (Test-Path "$env:ProgramData\PCSetupKit\previous\version.txt")) { Say 'There is no earlier version saved to go back to.'; return }
            if ([Windows.MessageBox]::Show("Go back to $((Get-Content "$env:ProgramData\PCSetupKit\previous\version.txt" -TotalCount 1).Trim())? The current version isn't installed again - the next release is.", 'Undo the last update', 'YesNo', 'Question') -ne 'Yes') { return }
            if (Send-Tray $cmd.Rollback) { Say 'Going back to the version before (a window shows the result).' } else { Start-Process powershell -Verb RunAs -ArgumentList ((& $psArgs 'kit-update.ps1' -Keep) + '-Rollback') } }
        BackupNow    = { $o = @(& "$cl\settings-backup.ps1" -Force); Say "$(if ($o) { $o[-1] } else { 'Backed up.' })" }
        RestoreFrom  = {
            $dlg = New-Object Microsoft.Win32.OpenFileDialog -Property @{ Title = 'Pick a settings backup'; Filter = 'Settings backup (*.zip)|*.zip'; InitialDirectory = "$([Environment]::GetFolderPath('MyDocuments'))\PC Setup Kit Backup" }
            if (-not $dlg.ShowDialog()) { return }
            $o = @(& "$cl\settings-backup.ps1" -Restore -From $dlg.FileName)
            if ("$o" -match 'made on another PC') {
                if ([Windows.MessageBox]::Show("This backup was made on another PC. Put its look and game settings on this one anyway?", 'Restore settings', 'YesNo', 'Question') -ne 'Yes') { return }
                $o = @(& "$cl\settings-backup.ps1" -Restore -From $dlg.FileName -AnyPc)
            }
            Say "$(if ($o) { $o[-1] } else { 'Nothing to restore in that backup.' })" }
        MakeUsb      = { if (Test-Path "$cl\make-usb.ps1") { Start-Process powershell -Verb RunAs -ArgumentList (& $psArgs 'make-usb.ps1' -Keep); Say 'The install USB maker opened in its own window.' } else { Say 'The USB maker is missing - it comes with the next kit update.' } }
        Logs         = { if (Test-Path "$cl\maint-claude-log") { Start-Process explorer.exe "`"$cl\maint-claude-log`"" } else { Say 'No hidden runs yet.' } }
        # the AI assistant switch (ai-toggle.ps1, through the tray: it needs admin rights)
        AiOn         = {
            if ([Windows.MessageBox]::Show("Switch on the AI assistant?`n`nMessiah installs Claude Code (from claude.ai) and opens it so you can sign in with your own Claude account - Claude Code comes with Claude's Pro and Max plans. Then Claude can look after this PC with you (the /maintain and /pc-optimize checks).`n`nEverything else in Messiah works the same without it.", 'AI assistant', 'OKCancel', 'Question') -ne 'OK') { return $false }
            if (-not (Send-Tray $cmd.AiOn)) { Start-Process powershell -Verb RunAs -ArgumentList ((& $psArgs 'ai-toggle.ps1') + '-On') }
            Say 'Switching on the AI assistant - Claude Code installs, then a window opens for signing in (a minute or two).'; $true }
        AiOff        = {
            if (-not (Send-Tray $cmd.AiOff)) { Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList ((& $psArgs 'ai-toggle.ps1') + '-Off') }
            Say 'AI assistant off - its sessions close. Claude Code and your conversations stay for when you switch it on again.' }
        GpuRollback  = { if (Send-Tray $cmd.GpuRollback) { Say 'A window opens with the driver versions - it asks before changing anything.' } else { Start-Process powershell -Verb RunAs -ArgumentList (& $psArgs 'gpu-rollback.ps1' -Keep) } }
        Uninstall    = {
            if ([Windows.MessageBox]::Show("Remove Messiah from this PC?`n`nThe tray icon, the automatic maintenance, updates and the app go away. Your apps, files and games stay. The removed files are kept in a folder in case you want them back.", 'Uninstall Messiah', 'OKCancel', 'Warning') -ne 'OK') { return }
            $rv = [Windows.MessageBox]::Show("Also put back the Windows settings Messiah changed (telemetry, power plan, Game Bar, ...)?`n`nYes: Windows as it was before. No: keep them as they are now.", 'Uninstall Messiah', 'YesNoCancel', 'Question')
            if ($rv -eq 'Cancel') { return }
            $u = 'C:\PCSetupKit\uninstall.ps1'
            if (-not (Test-Path $u)) { Say 'The uninstaller is missing - Repair the kit first (Maintenance page).'; return }
            Start-Process powershell -Verb RunAs -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$u`"", '-Yes') + @(if ($rv -eq 'Yes') { '-RevertTweaks' }))
            $win.Close() }
        FilesBackup  = { Start-Process powershell -WindowStyle Hidden -ArgumentList ((& $psArgs 'files-backup.ps1') + '-Enable'); & "$cl\todo.ps1" -Id 'backup' -Done
            Say 'Backing up your files to that drive now - from now on it happens by itself whenever the drive is connected.'; Update-View -Force }
        Welcomed     = { Set-Opt 'welcome' 'done'; $script:welcomeDone = $true; Update-Nav; $navItems.Home.Button.IsChecked = $true }
    }

    # --- building blocks
    function New-Text($t, $brush_ = $brush.Text, $size = 14, $weight = 'Normal', $margin = '0,1,0,1') {
        New-Object Windows.Controls.TextBlock -Property @{ Text = $t; TextWrapping = 'Wrap'; Foreground = $brush_; FontSize = $size; FontWeight = $weight; Margin = $margin }
    }
    function New-Glyph($g, $size = 16, $brush_ = $brush.Text) {
        New-Object Windows.Controls.TextBlock -Property @{ Text = [string][char][int]"0x$g"; FontFamily = $icons; FontSize = $size; Foreground = $brush_; VerticalAlignment = 'Center' }
    }
    function New-Btn($glyph, $text, [scriptblock]$do, [switch]$Accent, [switch]$Small) {   # -Small: inside a list row
        $sp = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
        [void]$sp.Children.Add((New-Glyph $glyph $(if ($Small) { 12 } else { 14 }) $(if ($Accent) { $brush.OnAccent } else { $brush.Text })))
        [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $text; Margin = '8,0,0,0'; VerticalAlignment = 'Center' }))
        $b = New-Object Windows.Controls.Button -Property @{ Content = $sp; Tag = $do; ToolTip = $text }
        $b.Style = $win.FindResource($(if ($Accent) { 'AccentBtn' } elseif ($Small) { 'SmallBtn' } else { 'Btn' }))
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
    # "today 10:35 AM", "yesterday 9:02 PM", "Mon 8:15 AM" (this week), "Sep 20" (older); -Short: without "today"
    function Format-When([datetime]$d, [switch]$Short) {
        $days = ((Get-Date).Date - $d.Date).Days
        if ($days -eq 0) { if ($Short) { $d.ToString('h:mm tt') } else { "today $($d.ToString('h:mm tt'))" } }
        elseif ($days -eq 1) { "yesterday $($d.ToString('h:mm tt'))" } elseif ($days -lt 7 -and $days -gt 0) { $d.ToString('ddd h:mm tt') } else { $d.ToString('MMM d') }
    }
    function Update-Columns { if ($script:tileGrid -and $ui.Scroll.ActualWidth -gt 0) { $script:tileGrid.Columns = [Math]::Max(2, [Math]::Min(4, [int][Math]::Floor(($ui.Scroll.ActualWidth - 20) / 190))) } }
    function New-Section($t) { New-Text $t $brush.Text 14 'SemiBold' '2,10,0,8' }   # a heading between groups of cards
    # a small status tile (Overview): a label, the value big, one line under it; a click goes to its page
    function New-Tile($glyph, $label, $value, $sub, $level = 'info', $goto) {
        $b = New-Object Windows.Controls.Border -Property @{ Background = $brush.Card; BorderBrush = $brush.Border; BorderThickness = 1; CornerRadius = 8; Padding = '16,12'; Margin = '0,0,12,12' }
        $sp = New-Object Windows.Controls.StackPanel
        $hd = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
        [void]$hd.Children.Add((New-Glyph $glyph 14 $brush.Accent)); $l = New-Text $label $brush.Sub 12 'Normal' '8,0,0,0'; $l.VerticalAlignment = 'Center'; [void]$hd.Children.Add($l)
        [void]$sp.Children.Add($hd)
        [void]$sp.Children.Add((New-Text $value $(if ($level -eq 'info') { $brush.Text } else { $levelBrush[$level] }) 18 'SemiBold' '0,6,0,0'))
        [void]$sp.Children.Add((New-Text $sub $brush.Sub 12 'Normal' '0,2,0,0'))
        $b.Child = $sp
        if ($goto) { $b.Cursor = 'Hand'; $b.Tag = $goto; $b.Add_MouseLeftButtonUp({ if ($navItems.Contains($this.Tag)) { $navItems[$this.Tag].Button.IsChecked = $true } }) }
        $b
    }
    # a setting with a switch on the right; $do gets the switch ($this) when it's clicked
    function New-SwitchRow($title, $sub, [bool]$on, [scriptblock]$do, $tag) {
        $r = New-Object Windows.Controls.DockPanel -Property @{ Margin = '0,0,0,12' }
        $s = New-Object Windows.Controls.CheckBox -Property @{ IsChecked = $on; VerticalAlignment = 'Center'; Tag = $tag; Margin = '16,0,0,0' }
        $s.Style = $win.FindResource('Switch'); [Windows.Controls.DockPanel]::SetDock($s, 'Right')
        $s.Add_Click($do)
        $l = New-Object Windows.Controls.StackPanel
        [void]$l.Children.Add((New-Text $title $brush.Text 14 'Normal' '0')); [void]$l.Children.Add((New-Text $sub $brush.Sub 12 'Normal' '0,2,0,0'))
        [void]$r.Children.Add($s); [void]$r.Children.Add($l); $r
    }
    # to-do items with their own buttons: the place to fix it where there is one, and "Remind me in a week" (todo.ps1
    # -Snooze: off the list, back in 7 days - unless it got fixed meanwhile)
    function Get-TodoFix([string]$t) {
        if ($t -match '(https://[^\s)]+?)[.,;]?(\s|$)') { return @('Open the page', $Matches[1]) }   # an item with its own link (the BIOS page, ...)
        switch -Regex ($t) {
            'previous graphics driver' { return @('Go back to the previous driver', 'kit:gpu-rollback') }
            '^(.+?) is installed - .*the Uninstall button here' { return @("Uninstall $($Matches[1])", "kit:uninstall:$($Matches[1])") }
            'Back up your files to' { return @('Back up to this drive', 'kit:files-backup') }
            'activated' { return @('Activation settings', 'ms-settings:activation') }
            'hypervisor' { return @('Windows features', 'optionalfeatures.exe') }
            'Xbox Game Bar' { return @('Microsoft Store', 'ms-windows-store://pdp/?ProductId=9NZKPSTSNW4P') }
            "chipset driver" { return @('AMD drivers', 'https://www.amd.com/en/support/download/drivers.html') }
            'DNS server' { return @('Network settings', 'ms-settings:network-status') }
            'Wi-Fi' { return @('Wi-Fi settings', 'ms-settings:network-wifi') }
            'nothing is backed up|File History' { return @('File History', 'control.exe /name Microsoft.FileHistory') }
            'Steam game\(s\) are on a hard drive' { return @('Steam storage', 'steam://open/settings/') }
            'Hz|refresh|monitor' { return @('Display settings', 'ms-settings:display-advancedgraphics') }
            'storage|full|free space' { return @('Storage settings', 'ms-settings:storagesense') }
        }
    }
    function New-TodoLines($lines) {
        foreach ($l in @($lines)) {
            if ($l.Level -ne 'warn') { $l; continue }
            $text = ($l.Text -replace '^- ', '').Trim()
            $row = New-Object Windows.Controls.StackPanel -Property @{ Margin = '0,2,0,6' }
            # long items: the first part as the line, the how-to behind "Details" (a wall of steps is hard to scan)
            $head = $text; $more = $null
            if ($text.Length -gt 140 -and $text -match '^(.{30,160}?)(?: - |\. |: )(.+)$') { $head = $Matches[1].TrimEnd('.') + '.'; $more = $Matches[2] }
            [void]$row.Children.Add((New-Text "$([char]0x2022)  $head" $brush.Text 14))
            if ($more) { $mt = New-Text $more $brush.Sub 12 'Normal' '14,4,0,0'; $mt.Visibility = 'Collapsed'; [void]$row.Children.Add($mt) }
            $bp = New-Object Windows.Controls.WrapPanel -Property @{ Margin = '14,6,0,0' }   # (small buttons, no gap under them)
            if ($more) { $db = New-Btn 'E946' 'Details' -Small { $t = $this.DataContext; $t.Visibility = if ($t.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' } }; $db.DataContext = $mt; [void]$bp.Children.Add($db) }
            $fx = Get-TodoFix $text
            if ($fx) { $b = New-Btn 'E8A7' $fx[0] -Small { $c = $this.Uid; if ($c -eq 'kit:gpu-rollback') { & $act.GpuRollback } elseif ($c -like 'kit:uninstall:*') { Start-Process powershell -Verb RunAs -ArgumentList ((& $psArgs 'junk-apps.ps1') + '-Remove', "`"$($c.Substring(14))`""); Say 'Its own uninstaller opens - follow it; the item goes away once it is removed.' } elseif ($c -eq 'kit:files-backup') { & $act.FilesBackup } elseif ($c -match '^(\S+\.exe)( (.+))?$') { if ($Matches[3]) { Start-Process $Matches[1] -ArgumentList $Matches[3] } else { Start-Process $Matches[1] } } else { Start-Process $c } }; $b.Uid = $fx[1]; [void]$bp.Children.Add($b) }   # (Uid: the button's own data)
            $sb = New-Btn 'E823' 'Remind me in a week' -Small { & "$cl\todo.ps1" -Snooze $this.Uid -Days 7; Say 'Snoozed - it comes back in a week if it still needs you.'; Update-View -Force }
            $sb.Uid = $text; [void]$bp.Children.Add($sb)
            [void]$row.Children.Add($bp); $row
        }
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
    # (a damaged file - a power cut mid-write, an old format - must never stop the window from opening: rows that aren't
    # objects or have no readable date are dropped, and a "number" that isn't one counts as missing)
    function Test-When($v) { $d = [datetime]::MinValue; [bool]("$v" -and [datetime]::TryParse("$v", [ref]$d)) }
    function Get-HealthHistory([string]$Name = 'health-history.json') {
        $j = try { Get-Content "$cl\$Name" -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null }
        @($j | ForEach-Object { $_ } | Where-Object { $_ -is [Management.Automation.PSCustomObject] -and (Test-When $_.date) } | ForEach-Object {
                foreach ($pr in @($_.PSObject.Properties)) {
                    if ($pr.Name -in 'date', 'game' -or $null -eq $pr.Value) { continue }
                    if ($pr.Name -eq 'bootAt') { if (-not (Test-When $pr.Value)) { $pr.Value = $null }; continue }
                    if ($pr.Value -isnot [ValueType] -or $pr.Value -is [bool]) { $n = 0.0; $pr.Value = if ($pr.Value -isnot [bool] -and [double]::TryParse("$($pr.Value)", [ref]$n)) { $n } else { $null } }
                }
                $_ })
    }   # (also perf-history.json, net-history.json)
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
        # the tray (Pause) and the AI switch write this file too: a moment's clash is retried, never an error in a click
        for ($i = 0; $i -lt 10; $i++) {
            try {
                $lines = @(Get-Content $f -ErrorAction Stop | Where-Object { $_ -notmatch "^\s*$k\s*=" }) + "$k=$v"
                [IO.File]::WriteAllLines($f, [string[]]$lines); return
            } catch [Management.Automation.ItemNotFoundException] { [IO.File]::WriteAllLines($f, [string[]]@("$k=$v")); return }
            catch { Start-Sleep -Milliseconds 100 }
        }
        Say "Couldn't save that setting (the file is busy) - try again in a moment."
    }

    # --- pages
    # (Welcome: after a new install, until "Got it"; Sessions: with the AI assistant on) - Get-Pages again when either changes
    function Get-Pages {
        $p = [ordered]@{}
        if ((Get-Opt 'welcome' '') -eq 'pending' -or ($Page -eq 'Welcome' -and -not $script:welcomeDone)) { $p.Welcome = 'E8E1' }
        $p.Home = 'E80F'
        if ($script:ai) { $p.Sessions = 'E756' }
        $p.Maintenance = 'E90F'; $p.History = 'E81C'; $p.Schedule = 'E787'; $p.Notifications = 'EA8F'; $p.Settings = 'E713'
        $p
    }
    $pages = Get-Pages
    $subs = @{ Welcome = 'Your PC is set up. Here is what happened and what happens from now on.'
        Home = 'How this PC is doing, and anything that needs you.'; Sessions = 'Claude Code with admin rights - the AI assistant.'
        Maintenance = 'The checks, updates and repairs Messiah runs by itself.'; History = 'How this PC has been doing over time.'
        Schedule = 'When each check runs next.'; Notifications = 'The small notes Messiah showed in the corner of the screen.'
        Settings = 'Everything Messiah does is yours to switch on or off.' }

    function Build-Page($p, $secs) {
        $out = New-Object Collections.ArrayList
        $needs = Sec $secs 'Needs you'; $wait = Sec $secs 'Waiting for'; $last = Sec $secs 'Last background check'
        $hidden = Sec $secs 'Hidden Claude'; $sched = Sec $secs 'Scheduled checks'; $mess = Sec $secs 'Messiah'
        switch ($p) {
            'Welcome' {
                $hero = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
                $badge = New-Object Windows.Controls.Border -Property @{ Width = 56; Height = 56; CornerRadius = 28; Margin = '0,0,18,0'; VerticalAlignment = 'Center' }
                $badge.Background = New-Object Windows.Media.LinearGradientBrush ([Windows.Media.ColorConverter]::ConvertFromString($c.Grad1)), ([Windows.Media.ColorConverter]::ConvertFromString($c.Grad2)), 45
                $badge.Child = New-Glyph 'E73E' 26 $brush.OnAccent; $badge.Child.HorizontalAlignment = 'Center'
                $txt = New-Object Windows.Controls.StackPanel -Property @{ VerticalAlignment = 'Center' }
                [void]$txt.Children.Add((New-Text 'This PC is ready' $brush.Text 22 'SemiBold' '0'))
                [void]$txt.Children.Add((New-Text 'Windows is updated, tuned for games and set up to look after itself - nothing else to do.' $brush.Sub 13 'Normal' '0,2,0,0'))
                [void]$hero.Children.Add($badge); [void]$hero.Children.Add($txt)
                # Chrome installed, Edge still the browser: Windows' own Chrome page, one "Set default" click (no program may switch it)
                $https = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice' -ErrorAction SilentlyContinue).ProgId
                $chromeReg = @('HKLM:\SOFTWARE\RegisteredApplications', 'HKCU:\SOFTWARE\RegisteredApplications' | Where-Object { (Get-ItemProperty $_ -ErrorAction SilentlyContinue).'Google Chrome' })
                $toChrome = if ($chromeReg -and (-not $https -or $https -like 'MSEdge*')) { $u = if ($chromeReg[0] -like 'HKLM*') { 'registeredAppMachine' } else { 'registeredAppUser' }
                    New-Btn 'E774' 'Make Chrome your browser' ([scriptblock]::Create("Start-Process 'ms-settings:defaultapps?$u=Google%20Chrome'")) }
                [void]$out.Add((New-Card $null $null @($hero) @(@(New-Btn 'E73E' 'Got it' $act.Welcomed -Accent) + @($toChrome | Where-Object { $_ }))))
                # what setup did: the report's "WHAT WAS DONE" (optimize.ps1), the main lines
                $rep = @(Get-Content "$env:USERPROFILE\Documents\PC Setup Kit report.txt" -Encoding UTF8 -ErrorAction SilentlyContinue)
                $i = [array]::IndexOf($rep, 'WHAT WAS DONE'); $j = [array]::IndexOf($rep, 'WHAT NEEDS YOU')
                $did = @(if ($i -ge 0 -and $j -gt $i) { $rep[($i + 1)..($j - 1)] | ForEach-Object { $_.Trim() } | Where-Object { $_ -and $_ -notmatch '^(WARNING|Reminder|Restore point|Next:|Checked|\[|Apps: \d|Crashes: none|Tweaks: all|Maintenance: running|Maintenance \(|Other drivers: all up to date|Next:)|FAILED|timed out|could not run' } | Select-Object -Unique -First 10 | ForEach-Object { @{ Text = "- $_"; Level = 'info' } } })
                if (-not $did) { $did = @(@{ Text = '- Windows updated, drivers and apps installed, the screen at its best resolution and refresh rate'; Level = 'info' }, @{ Text = '- Telemetry, ads and bloat off; the best power plan; games tuned (each change is yours to switch off in Settings)'; Level = 'info' }) }
                [void]$out.Add((New-Card 'What was done' 'E9D5' $did @(if ($rep) { New-Btn 'E8A5' 'The full report' { Start-Process notepad.exe "`"$env:USERPROFILE\Documents\PC Setup Kit report.txt`"" } })))
                [void]$out.Add((New-Card 'From now on' 'E823' @(
                            @{ Text = '- At every login Messiah checks for updates, drivers, crashes, temperatures and disk space in the background, and waits while you play.'; Level = 'info' },
                            @{ Text = '- It never restarts the PC: what needs a restart finishes the next time you turn it off.'; Level = 'info' },
                            @{ Text = '- It updates itself, and puts your settings back after Windows updates.'; Level = 'info' },
                            @{ Text = "- It lives in the hidden tray (^ next to the clock). Ctrl+Alt+M opens this window; Overview says when something needs you."; Level = 'info' }) $null))
                $opt = @()
                if (-not $ai) { $opt += New-Btn 'E99A' 'Switch on the AI assistant' { [void](& $act.AiOn) } }
                $opt += New-Btn 'E771' 'Review what Messiah changes' { $navItems.Settings.Button.IsChecked = $true }
                $opt += New-Btn 'E88E' 'Make an install USB' $act.MakeUsb
                [void]$out.Add((New-Card 'Optional' 'E734' @(@{ Text = 'None of this is needed. The AI assistant (Claude, with your own account) can look after the PC with you; an install USB sets up another PC - or this one again - the same way.'; Level = 'dim' }) $opt))
            }
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
                $whenAt = if ($when -and $when.Text -match '^Checked (.+?)( in |$)') { $d = [datetime]::MinValue; if ([datetime]::TryParse($Matches[1], [ref]$d)) { $d } }
                [void]$txt.Children.Add((New-Text "$(if ($whenAt) { "Last check $(Format-When $whenAt)" } elseif ($when) { $when.Text } else { 'No check yet - the first one runs a few minutes after login' })$(if ($v = ("$(Get-Content 'C:\PCSetupKit\kit-version.txt' -TotalCount 1 -ErrorAction SilentlyContinue)").Trim()) { "  $([char]0xB7)  Messiah $v, updates by itself" })" $brush.Sub 12 'Normal' '0,2,0,0'))
                [Windows.Controls.Grid]::SetColumn($txt, 1); [void]$hero.Children.Add($badge); [void]$hero.Children.Add($txt)
                [void]$out.Add((New-Card $null $null @($hero) @((New-Btn 'E768' 'Run maintenance now' $act.RunMaint -Accent), (New-Btn 'E945' 'Optimize this PC' $act.Optimize))))
                # the tiles: the main facts at a glance, each a way into its page
                $tiles = New-Object Windows.Controls.Primitives.UniformGrid -Property @{ Columns = 4; Margin = '0,0,-12,0' }; $script:tileGrid = $tiles
                $lastPerf = Get-HealthHistory 'perf-history.json' | Select-Object -Last 1
                $hh1 = Get-HealthHistory | Select-Object -Last 1
                $tileDefs = @(
                    @('E9D9', 'Last check', $(if ($whenAt) { Format-When $whenAt -Short } else { 'Not yet' }), 'At every login and once a day', 'info', 'Maintenance'),
                    @('E7FC', 'Last game', $(if ($lastPerf) { "$([int]$lastPerf.fps) fps" } else { 'Nothing yet' }), $(if ($lastPerf) { "$($lastPerf.game), 1% low $([int]$lastPerf.low1) fps" } else { 'Measured while you play' }), 'info', 'History'),
                    @('EDA2', 'Free space on C:', $(if ($hh1 -and $null -ne $hh1.freeGB) { "$([int]$hh1.freeGB) GB" } else { '-' }), 'Cleaned up every week', $(if ($hh1 -and $null -ne $hh1.freeGB -and $hh1.freeGB -lt 30) { 'warn' } else { 'info' }), 'History'),
                    @('E99A', 'AI assistant', $(if ($ai) { 'On' } else { 'Off' }), $(if ($ai) { 'Claude, signed in with your account' } else { 'Optional - switch on in Settings' }), 'info', $(if ($ai) { 'Sessions' } else { 'Settings' })))
                foreach ($t in $tileDefs) { [void]$tiles.Children.Add((New-Tile @t)) }
                Update-Columns; [void]$out.Add($tiles)
                $pz = if (Test-Path "$cl\paused.ps1") { & "$cl\paused.ps1" }
                if ($pz) { [void]$out.Add((New-Card 'Maintenance paused' 'E769' @(@{ Text = "Until $($pz.ToString('ddd h:mm tt')) - updates, checks and cleanup wait (the tray's Pause maintenance)."; Level = 'warn' }) @(New-Btn 'E768' 'Resume now' { Set-Opt 'pause-until' ''; Say 'Maintenance runs again as usual.'; Update-View -Force }) -Calm)) }
                if ($todo) { [void]$out.Add((New-Card 'Needs you' 'E7BA' @(New-TodoLines $needs.Lines) @(New-Btn 'E8A5' 'Open the to-do list' $act.Todo) -Calm)) }
                if (@($wait.Lines | Where-Object { $_.Text -notmatch '^Nothing' })) { [void]$out.Add((New-Card $wait.Title 'E777' $wait.Lines $null)) }
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
                [void]$out.Add((New-Card 'Needs you' 'E7BA' @(New-TodoLines $needs.Lines) @(New-Btn 'E8A5' 'Open the to-do list' $act.Todo) -Calm))
                $kvf = Get-Item 'C:\PCSetupKit\kit-version.txt' -ErrorAction SilentlyContinue
                $prev = Get-Content "$env:ProgramData\PCSetupKit\previous\version.txt" -TotalCount 1 -ErrorAction SilentlyContinue
                $kl = @(@{ Text = "$(if ($kvf) { "Version $((Get-Content $kvf.FullName -TotalCount 1).Trim()), since $($kvf.LastWriteTime.ToString('MMM d')). " })It updates itself (checks every 4 hours) and tests itself after each update."; Level = 'info' })
                if ($prev) { $kl += @{ Text = "The version before ($("$prev".Trim())) is kept: Undo goes back to it."; Level = 'dim' } }
                [void]$out.Add((New-Card 'Messiah updates' 'E895' $kl @((New-Btn 'E90F' 'Repair Messiah' $act.Repair), (New-Btn 'E7A7' 'Undo the last update' $act.Rollback))))
                # the graphics driver, with the one-click way back to the one before (gpu-rollback.ps1, through the tray)
                if (-not $script:gd -and -not $env:PCKIT_IN_TESTS) { $script:gd =Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'" -ErrorAction SilentlyContinue | Where-Object { $_.InfName -match '^oem\d+\.inf$' } |
                    Sort-Object { if ($_.DeviceName -match 'NVIDIA') { 0 } elseif ($_.DeviceName -match 'Radeon|AMD') { 1 } else { 2 } } | Select-Object -First 1 }   # (slow: read once per window)
                $gd = $script:gd
                if ($gd) {
                    $held = "$(Get-Content "$cl\gpu-hold.txt" -TotalCount 1 -ErrorAction SilentlyContinue)".Trim()
                    $gl = @(@{ Text = "$($gd.DeviceName) - driver $($gd.DriverVersion)$(if ($gd.DriverDate) { " from $($gd.DriverDate.ToString('MMM d, yyyy'))" })"; Level = 'info' },
                        @{ Text = 'Updated by itself. If games crash, freeze or run worse since the last update, go back to the driver before it - a restore point is made first, and the newer one isn''t installed again (a later version is).'; Level = 'dim' })
                    if ($held) { $gl += @{ Text = "You went back from $held - versions up to it are skipped."; Level = 'dim' } }
                    [void]$out.Add((New-Card 'Graphics driver' 'E7F4' $gl @(New-Btn 'E7A7' 'Go back to the previous driver' $act.GpuRollback)))
                }
                $bi = if (Test-Path "$cl\bios-info.ps1") { & "$cl\bios-info.ps1" }
                if ($bi -and $bi.Maker) {
                    $bb = New-Btn 'E774' 'Open its BIOS page' { Start-Process $this.Uid }; $bb.Uid = $bi.Url
                    [void]$out.Add((New-Card 'Motherboard and BIOS' 'E950' @(@{ Text = "$($bi.Maker) $($bi.Model) - BIOS $($bi.Version) from $($bi.Date)"; Level = 'info' }, @{ Text = "A newer BIOS fixes stability and security problems; the kit reminds you when this one is over a year old. Updating it: $($bi.Steps)"; Level = 'dim' }) @($bb)))
                }
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
                # --- General: the AI assistant, start-up
                [void]$out.Add((New-Section 'General'))
                $aiRow = New-SwitchRow 'AI assistant (Claude)' $(if ($ai) { 'On: Messiah sessions (Claude Code with admin rights) with your Claude account, and Claude''s own maintenance checks. Off: its sessions close; Claude Code and your conversations stay.' } else { 'Sign in with your own Claude account (Claude Code comes with Claude''s Pro and Max plans) and Claude looks after the PC with you. Everything else works without it.' }) ([bool]$ai) {
                    if ($this.IsChecked) { if (-not (& $act.AiOn)) { $this.IsChecked = $false } } else { & $act.AiOff }
                }
                $openRow = New-SwitchRow "Open $name when I log in" "Off: $name starts in the hidden tray (^ next to the clock) and works on its own. On: this window also opens once per start-up (not while a game is fullscreen)." ((Get-Opt 'openatlogin' 'off') -eq 'on') {
                    Set-Opt 'openatlogin' $(if ($this.IsChecked) { 'on' } else { 'off' }); Say "Saved - $(if ($this.IsChecked) { "this window opens at login" } else { "$name starts in the hidden tray at login" })."
                }
                # (restart-night.ps1: on by default, except on the PC the kit is made on)
                $nightRow = New-SwitchRow 'Restart at night to finish updates' 'When an update waits for a restart, the PC restarts between 3:30 and 5:30 AM - only if nobody has used it for an hour, no game is running and it is plugged in. A 5-minute warning first (the tray''s Cancel restart stops it). Off: updates finish whenever you restart.' ((Get-Opt 'nightrestart' $(if (Test-Path "$cl\publish-kit.ps1") { 'off' } else { 'on' })) -eq 'on') {
                    Set-Opt 'nightrestart' $(if ($this.IsChecked) { 'on' } else { 'off' }); Say "Saved - $(if ($this.IsChecked) { 'pending updates finish with a restart at night while the PC is unused' } else { 'updates finish whenever you restart' })."
                }
                [void]$out.Add((New-Card 'AI assistant, start-up and restarts' 'E713' @($aiRow, $openRow, $nightRow) $null))
                # --- Gaming options (kit-options.txt; gaming-check.ps1 / nvidia-settings.ps1 apply them at the next check)
                [void]$out.Add((New-Section 'Gaming'))
                $opts = foreach ($o in @(@('defenderexclusions', 'off', 'Microsoft Defender skips my game folders', 'Less stutter while games load and build their shaders. A small security trade-off: files in those folders are no longer scanned. Off by default.'),
                        @('nvidiasettings', 'on', 'NVIDIA driver settings for games', 'Low-latency mode on and an unlimited shader cache (less stutter), set in the driver for every game. Off: no longer applied (the driver keeps the last values until changed in the NVIDIA Control Panel).'))) {
                    New-SwitchRow $o[2] $o[3] ((Get-Opt $o[0] $o[1]) -eq 'on') { Set-Opt $this.Tag $(if ($this.IsChecked) { 'on' } else { 'off' }); Say 'Saved - applied at the next check (or click Run maintenance now).' } $o[0]
                }
                [void]$out.Add((New-Card 'Games' 'E7FC' @($opts) $null))
                # every change the kit makes, each one the owner's to keep or not (tweaks.ps1 reads "tweak.<id>=off", puts
                # back what it had changed, and keeps to the choice after updates) - in groups
                $tw = [ordered]@{
                    'Speed and games'     = @(
                        @('memory-integrity', 'Memory integrity off', 'Core isolation (VBS) costs 5-10% in many games. On: extra protection against malicious drivers, a bit less speed.'),
                        @('game-bar', 'Xbox Game Bar removed', 'Its overlay and background capture cost frame rate. Off: it comes back. (Always kept on AMD dual-CCD X3D CPUs, which need it.)'),
                        @('game-recording', 'Background game recording off', 'Game DVR records every game in the background. Off: recording and clips work again.'),
                        @('windowed-games', 'Optimizations for windowed games and VRR', 'Lower input lag in borderless-window games, variable refresh rate where supported.'),
                        @('mouse-acceleration', 'Mouse acceleration off', 'The same hand movement always moves the cursor the same distance - better aim.'),
                        @('sticky-keys', 'Sticky Keys pop-up off', 'Pressing Shift five times in a game no longer opens the Sticky Keys prompt and throws you out of fullscreen. The feature itself stays in Accessibility.'),
                        @('power-plan', 'Best power plan', 'Desktops: Ultimate Performance. Laptops: Balanced, full speed when plugged in. Off: your own plan.'),
                        @('hibernation', 'Hibernation off (desktops)', 'Frees disk space and gives a clean start every time. Laptops always keep it.'))
                    'Privacy and clutter' = @(
                        @('telemetry', 'Telemetry, ads and Windows AI off', 'No diagnostic data, ads, suggestions, Bing in search, Copilot or Recall.'),
                        @('bloat-apps', 'Preinstalled apps removed', 'News, Weather, Teams, Clipchamp, Solitaire, TikTok and the like. Off: Messiah stops removing them (reinstall any from the Microsoft Store).'),
                        @('onedrive', 'OneDrive removed', 'Off: OneDrive comes back and can sync again.'),
                        @('edge', 'Edge kept out of the way', 'Edge stays installed (Windows and many apps need it), but no desktop icon, no taskbar pin, no prompts, and Chrome is your browser. Off: its icon and prompts come back.'),
                        @('start-menu', 'Start menu recommendations and Task View off', 'A cleaner Start menu and taskbar.'),
                        @('legacy', 'Old Windows parts removed', 'Internet Explorer''s engine, the old Media Player, WordPad, Steps Recorder and the like; PowerShell 2.0 and Recall off; reserved storage (about 7 GB) freed. Never what updates need. Off: they come back.'),
                        @('startup-clutter', 'Start-up clutter off', 'Vendor updaters and promo tools don''t start with Windows. Off: they start again.'),
                        @('transparency', 'Transparency effects off', 'Slightly less work for the graphics card. Off: see-through Start menu and windows again.'))
                    'Windows Update'      = @(
                        @('restart-block', 'No Windows Update restarts while you''re signed in', 'Updates still install; the restart waits for yours.'),
                        @('feature-delay', 'Big Windows upgrades wait 45 days', 'The yearly new Windows version comes once its first problems are fixed; security and monthly updates still come right away. (Windows Pro and up; Home ignores it.)'))
                }
                [void]$out.Add((New-Section 'What Messiah changes in Windows'))
                foreach ($g in $tw.Keys) {
                    $rows2 = foreach ($o in $tw[$g]) {
                        New-SwitchRow $o[1] $o[2] ((Get-Opt "tweak.$($o[0])" 'on') -ne 'off') {
                            Set-Opt "tweak.$($this.Tag)" $(if ($this.IsChecked) { 'on' } else { 'off' })
                            if (Send-Tray $cmd.ApplyTweaks) { Say 'Saved - applying it now (a few seconds; some changes need a restart).' } else { Say 'Saved - applied at the next check (or click Run maintenance now).' } } $o[0]
                    }
                    [void]$out.Add((New-Card $g $(switch ($g) { 'Speed and games' { 'E945' } 'Privacy and clutter' { 'E72E' } default { 'E895' } }) @($rows2) $null))
                }
                # --- Backup
                [void]$out.Add((New-Section 'Backup'))
                $bks = @(@("$([Environment]::GetFolderPath('MyDocuments'))\PC Setup Kit Backup") + @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { "$($_.Root)PC Setup Kit Backup" }) | Where-Object { Test-Path $_ } | ForEach-Object { Get-ChildItem "$_\*.zip" -ErrorAction SilentlyContinue } | Sort-Object LastWriteTime -Descending)
                $bl = @(if ($bks) { @(@{ Text = "Last backup: $($bks[0].LastWriteTime.ToString('ddd MMM d, h:mm tt')) in $(Split-Path $bks[0].FullName)"; Level = 'info' }) } else { @(@{ Text = 'No backup yet - the first one is made at the next weekly maintenance.'; Level = 'dim' }) })
                $bl += @{ Text = 'Weekly: wallpaper, dark mode, colours, taskbar, mouse, Start pins, game settings and Messiah''s memory. Reinstalling Windows with the install USB brings them back by itself; plug in the USB once in a while and a copy goes onto it too.'; Level = 'dim' }
                [void]$out.Add((New-Card 'Settings backup' 'E777' $bl @((New-Btn 'E777' 'Back up now' $act.BackupNow), (New-Btn 'E896' 'Restore from a backup...' $act.RestoreFrom))))
                # --- About, and uninstall
                [void]$out.Add((New-Section 'About'))
                $kv = Get-Content 'C:\PCSetupKit\kit-version.txt' -TotalCount 1 -ErrorAction SilentlyContinue
                [void]$out.Add((New-Card 'About' 'E946' @(
                            @{ Text = "$name$(if ($kv) { " $kv" })"; Level = 'info' },
                            @{ Text = 'Keeps this PC updated, tuned and checked by itself, and updates itself.'; Level = 'dim' },
                            @{ Text = 'Tip: Ctrl+Alt+M opens this window from anywhere.'; Level = 'dim' }) $null))
                [void]$out.Add((New-Card 'Uninstall' 'E74D' @(@{ Text = 'Removes Messiah - the tray icon, the automatic maintenance and this app. Your apps, files and games stay; it asks whether to put back the Windows settings it changed.'; Level = 'dim' }) @(New-Btn 'E74D' 'Uninstall Messiah...' $act.Uninstall)))
            }
        }
        $out
    }

    $script:onPage = if ($Page -and $pages.Contains($Page)) { $Page } else { 'Home' }
    $script:shown = $null; $script:claudeVer = $null; $navItems = @{}
    function Update-View([switch]$Force) {
        # the AI assistant switched on or off (ai-toggle.ps1, a minute after the switch): the pages change with it
        $nowAi = if (Test-Path "$cl\ai-enabled.ps1") { [bool](& "$cl\ai-enabled.ps1") } else { $true }
        if ($nowAi -ne [bool]$script:ai) { $script:ai = $nowAi; $script:claudeVer = $null; Update-Nav; $Force = $true }
        $secs = @(Get-KitStatus -ClaudeVersion $script:claudeVer)
        if ($ai -and -not $script:claudeVer) { $m = Sec $secs 'Messiah'; if ($m) { $script:claudeVer = ($m.Lines[0].Text -replace '^Claude Code ', '') } }
        # the nav shows how many things need the owner
        $todo = @((Sec $secs 'Needs you').Lines | Where-Object Level -eq 'warn').Count
        $navItems.Home.Tag.Text = if ($todo) { "$todo" } else { '' }; $navItems.Home.Tag.Parent.Visibility = if ($todo) { 'Visible' } else { 'Collapsed' }
        $ui.Version.Text = @(Get-Content 'C:\PCSetupKit\kit-version.txt' -TotalCount 1 -ErrorAction SilentlyContinue; if ($ai -and $script:claudeVer) { "Claude Code $script:claudeVer" }) -join "`n"
        $ui.AiPill.Content = "$([char]0x25CF)  AI assistant $(if ($ai) { 'on' } else { 'off' })"
        $ui.AiPill.Foreground = if ($ai) { $brush.Ok } else { $brush.Sub }
        # redraw only when something changed (no flicker; the scroll position stays while reading)
        $sig = "$script:onPage`n" + (($secs | ForEach-Object { $_.Title; $_.Lines | ForEach-Object { "$($_.Level)|$($_.Text)" } }) -join "`n") +
            "`n" + ((Get-Item "$cl\health-history.json", "$cl\notifications.log", "$cl\maint-history", "$cl\kit-options.txt" -ErrorAction SilentlyContinue | ForEach-Object { $_.LastWriteTime.Ticks }) -join ',')
        if (-not $Force -and $sig -eq $script:shown) { return }
        $script:shown = $sig
        $ui.PageTitle.Text = switch ($script:onPage) { 'Home' { 'Overview' } 'Welcome' { 'Welcome to Messiah' } default { $script:onPage } }
        $ui.PageSub.Text = $subs[$script:onPage]
        $ui.Content.Children.Clear()
        # one page failing to build never takes the window down: it says so (the tests look for PAGE ERROR)
        $script:pageError = $null
        $els = try { @(Build-Page $script:onPage $secs) } catch {
            $script:pageError = "$($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))"
            @(New-Card "This page couldn't be shown" 'E783' @(@{ Text = 'Something in its data is damaged. The other pages work; the next maintenance usually repairs it.'; Level = 'warn' }, @{ Text = $script:pageError; Level = 'dim' }) $null)
        }
        foreach ($el in $els) { [void]$ui.Content.Children.Add($el) }
    }

    # the nav (built again when its pages change: the welcome page done, the AI assistant on or off)
    function Update-Nav {
        $script:pages = Get-Pages
        $ui.NavList.Children.Clear(); $navItems.Clear()
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
            $rb.Add_Checked({ $script:onPage = $this.Tag; Say ''; $ui.Scroll.ScrollToTop(); Update-View -Force })
            [void]$ui.NavList.Children.Add($rb)
        }
        if (-not $pages.Contains($script:onPage)) { $script:onPage = 'Home' }
        if (-not $Test) { $navItems[$script:onPage].Button.IsChecked = $true }
    }
    $ui.AiPill.Style = $win.FindResource('Btn'); $ui.AiPill.Margin = '8,0,0,10'
    $ui.AiPill.Add_Click({ $navItems[$(if ($ai) { 'Sessions' } else { 'Settings' })].Button.IsChecked = $true })
    $script:ai = [bool]$ai
    Update-Nav

    if ($Test) {
        "WINDOW: $($win.Title)"
        foreach ($p in @($pages.Keys)) {
            $script:onPage = $p; Update-View -Force
            "PAGE: $($ui.PageTitle.Text)"; if ($script:pageError) { "PAGE ERROR: $script:pageError" }
            foreach ($card in @($ui.Content.Children | ForEach-Object { if ($_ -is [Windows.Controls.Primitives.UniformGrid] -or $_ -is [Windows.Controls.WrapPanel]) { $_.Children } else { $_ } })) {
                if ($card -is [Windows.Controls.TextBlock]) { "SECTION: $($card.Text)"; continue }
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
    $ui.Scroll.Add_SizeChanged({ Update-Columns })
    $timer = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromSeconds(10) }
    $timer.Add_Tick({ try { Update-View } catch {} })
    $timer.Start()
    [void]$win.ShowDialog()
}
catch {
    if ($Test) { throw }
    Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$cl\status.ps1`""
}
