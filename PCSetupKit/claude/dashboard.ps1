# The app window, Messiah (Start menu / desktop "Messiah", the tray icon, Ctrl+Alt+M): how the PC is doing at one
# glance, what needs the owner, what the maintenance did and when it runs next, and every setting - refreshed every few
# seconds. Three tabs (the 10/10 redesign: one-glance home): Home, Activity (Checks / Trends / Alerts) and Settings
# (General / Windows / Tools). One window: starting it again brings the open one to the front. Things that need admin
# rights (sessions, maintenance, optimize) go through the tray, which runs elevated, so there's no UAC prompt; without
# the tray they start directly. If the window can't open, status.ps1 (text) opens instead.
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
        @{ Bg = '#F3F3F3'; Card = '#CCFFFFFF'; CardHover = '#F2FFFFFF'; Border = '#12000000'; Text = '#E4000000'; Sub = '#9E000000'; Accent = '#5B57E8'
            Ok = '#0F7B0F'; Warn = '#9D5D00'; Btn = '#CCFFFFFF'; BtnHover = '#F5FFFFFF'; Seg = '#0C000000'; SegSel = '#FFFFFFFF'; NavHover = '#08000000'
            Grad1 = '#7C5CFF'; Grad2 = '#3E8BF2'; OnAccent = '#FFFFFF'; Chart = '#6D5AE6'; Divider = '#0F000000'; Toast = '#FFFBFBFB' }
    } else {
        @{ Bg = '#202020'; Card = '#0FFFFFFF'; CardHover = '#16FFFFFF'; Border = '#14FFFFFF'; Text = '#FFFFFF'; Sub = '#C5FFFFFF'; Accent = '#A8A6FF'
            Ok = '#6CCB5F'; Warn = '#FFC83D'; Btn = '#12FFFFFF'; BtnHover = '#1CFFFFFF'; Seg = '#0CFFFFFF'; SegSel = '#1FFFFFFF'; NavHover = '#0AFFFFFF'
            Grad1 = '#7C5CFF'; Grad2 = '#3E8BF2'; OnAccent = '#FFFFFF'; Chart = '#8F7DFF'; Divider = '#10FFFFFF'; Toast = '#FF2C2C2C' }   # Chart: validated (dataviz) on each surface
    }
    $icons = "Segoe Fluent Icons, Segoe MDL2 Assets"
    $display = 'Segoe UI Variable Display, Segoe UI'

    [xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$name" Width="1040" Height="780" MinWidth="480" MinHeight="440" WindowStartupLocation="Manual"
        Background="$($c.Bg)" FontFamily="Segoe UI Variable Text, Segoe UI" FontSize="14" Foreground="$($c.Text)"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
  <Window.Resources>
    <Style x:Key="Btn" TargetType="Button">
      <Setter Property="Margin" Value="0,0,8,8"/><Setter Property="Padding" Value="16,8"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Foreground" Value="$($c.Text)"/><Setter Property="Background" Value="$($c.Btn)"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="$($c.Border)" BorderThickness="1" CornerRadius="8" Padding="{TemplateBinding Padding}">
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
      <Setter Property="Padding" Value="11,5"/><Setter Property="FontSize" Value="13"/><Setter Property="Margin" Value="0,0,6,0"/>
    </Style>
    <Style x:Key="AccentBtn" TargetType="Button" BasedOn="{StaticResource Btn}">
      <Setter Property="Foreground" Value="$($c.OnAccent)"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="b" CornerRadius="8" Padding="{TemplateBinding Padding}">
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
    <Style x:Key="Tab" TargetType="RadioButton">
      <Setter Property="Foreground" Value="$($c.Text)"/><Setter Property="Cursor" Value="Hand"/><Setter Property="Margin" Value="0"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="RadioButton">
          <Border x:Name="b" Background="Transparent" CornerRadius="7" Padding="18,6"><ContentPresenter VerticalAlignment="Center"/></Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="$($c.NavHover)"/></Trigger>
            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="Background" Value="$($c.NavHover)"/></Trigger>
            <Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="Background" Value="$($c.SegSel)"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style x:Key="Pill" TargetType="RadioButton" BasedOn="{StaticResource Tab}">
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="RadioButton">
          <Border x:Name="b" Background="Transparent" CornerRadius="6" Padding="13,4"><ContentPresenter VerticalAlignment="Center"/></Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="$($c.NavHover)"/></Trigger>
            <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="Background" Value="$($c.NavHover)"/></Trigger>
            <Trigger Property="IsChecked" Value="True"><Setter TargetName="b" Property="Background" Value="$($c.SegSel)"/></Trigger>
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
    <Style x:Key="Splitter" TargetType="GridSplitter">
      <Setter Property="Template"><Setter.Value>
        <ControlTemplate TargetType="GridSplitter">
          <Border x:Name="s" Background="Transparent"><Border x:Name="line" Width="2" HorizontalAlignment="Center" Background="Transparent" CornerRadius="1"/></Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="line" Property="Background" Value="$($c.Accent)"/></Trigger>
            <Trigger Property="IsDragging" Value="True"><Setter TargetName="line" Property="Background" Value="$($c.Accent)"/></Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value></Setter>
    </Style>
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="$($c.Bg)"/><Setter Property="Foreground" Value="$($c.Text)"/><Setter Property="BorderBrush" Value="$($c.Border)"/><Setter Property="Padding" Value="8,5"/>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition x:Name="MainCol" Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition x:Name="ChatCol" Width="0"/></Grid.ColumnDefinitions>
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
    <Grid x:Name="TopBar" Margin="24,14,24,4">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
      <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
        <Image x:Name="Logo" Width="26" Height="26" Margin="0,0,10,0" RenderOptions.BitmapScalingMode="HighQuality"/>
        <TextBlock x:Name="AppName" Text="$name" FontSize="17" FontWeight="SemiBold" FontFamily="$display" VerticalAlignment="Center"/>
      </StackPanel>
      <Border Grid.Column="1" Background="$($c.Seg)" CornerRadius="10" Padding="4" VerticalAlignment="Center"><StackPanel x:Name="NavList" Orientation="Horizontal"/></Border>
      <Button x:Name="AiPill" Grid.Column="2" HorizontalAlignment="Right" VerticalAlignment="Center" Visibility="Collapsed"/>
    </Grid>
    <Border x:Name="NowBar" Grid.Row="1" Visibility="Collapsed" Margin="24,8,24,0" Padding="14,8" CornerRadius="10" Background="$($c.Seg)" Cursor="Hand" HorizontalAlignment="Center" MaxWidth="1100">
      <StackPanel Orientation="Horizontal">
        <Ellipse x:Name="NowDot" Width="8" Height="8" Fill="$($c.Accent)" VerticalAlignment="Center" Margin="0,0,10,0"/>
        <TextBlock x:Name="NowText" FontSize="13" VerticalAlignment="Center" TextTrimming="CharacterEllipsis"/>
      </StackPanel>
    </Border>
    <ScrollViewer x:Name="Scroll" Grid.Row="2" VerticalScrollBarVisibility="Auto">
      <StackPanel x:Name="Body" MaxWidth="1100" Margin="24,14,24,28">
        <DockPanel x:Name="Header" Margin="2,4,0,18">
          <Border x:Name="SubBox" DockPanel.Dock="Right" Background="$($c.Seg)" CornerRadius="8" Padding="3" VerticalAlignment="Center" Margin="16,0,0,0"><StackPanel x:Name="SubNav" Orientation="Horizontal"/></Border>
          <StackPanel VerticalAlignment="Center">
            <TextBlock x:Name="PageTitle" FontSize="26" FontWeight="SemiBold" FontFamily="$display"/>
            <TextBlock x:Name="PageSub" Foreground="$($c.Sub)" FontSize="13" TextWrapping="Wrap" Margin="0,2,0,0"/>
          </StackPanel>
        </DockPanel>
        <StackPanel x:Name="Content"/>
      </StackPanel>
    </ScrollViewer>
    <Border x:Name="NoteBar" Grid.Row="2" Visibility="Collapsed" HorizontalAlignment="Center" VerticalAlignment="Bottom" MaxWidth="640" Margin="24,0,24,20" Padding="16,10" CornerRadius="10" Background="$($c.Toast)" BorderBrush="$($c.Border)" BorderThickness="1">
      <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="4" Opacity="0.35" Color="Black"/></Border.Effect>
      <DockPanel>
        <TextBlock x:Name="NoteGlyph" DockPanel.Dock="Left" FontFamily="$icons" FontSize="14" Foreground="$($c.Accent)" VerticalAlignment="Center" Margin="0,0,10,0" Text="&#xE946;"/>
        <TextBlock x:Name="Note" FontSize="13" TextWrapping="Wrap" VerticalAlignment="Center"/>
      </DockPanel>
    </Border>
    <GridSplitter x:Name="ChatSplit" Grid.Column="1" Grid.RowSpan="3" Width="7" Margin="0,0,-4,0" Panel.ZIndex="5" Style="{StaticResource Splitter}" ResizeBehavior="PreviousAndNext" ResizeDirection="Columns" Cursor="SizeWE" Focusable="False" Visibility="Collapsed" ToolTip="Drag to make the chat wider or narrower"/>
    <Border x:Name="ChatPanel" Grid.Column="2" Grid.RowSpan="3" Visibility="Collapsed" AllowDrop="True" Background="$($c.Card)" BorderBrush="$($c.Border)" BorderThickness="1,0,0,0">
      <DockPanel>
        <DockPanel DockPanel.Dock="Top" Margin="12,16,12,10">
          <Button x:Name="ChatMenu" DockPanel.Dock="Left" ToolTip="Chats and earlier conversations"/>
          <Button x:Name="ChatClose" DockPanel.Dock="Right" ToolTip="Close the chat (Claude keeps working)"/>
          <Button x:Name="ChatNew" DockPanel.Dock="Right" ToolTip="New conversation in a new tab"/>
          <Button x:Name="ChatMode" DockPanel.Dock="Right"/>
          <Button x:Name="ChatRemote" DockPanel.Dock="Right" Visibility="Collapsed"/>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center" Margin="10,0,0,0">
            <TextBlock FontFamily="$icons" FontSize="16" Foreground="$($c.Accent)" VerticalAlignment="Center" Text="&#xE99A;" Margin="0,0,10,0"/>
            <StackPanel>
              <TextBlock x:Name="ChatTitle" Text="Claude" FontSize="16" FontWeight="SemiBold" FontFamily="$display" TextTrimming="CharacterEllipsis"/>
              <TextBlock x:Name="ChatStatus" FontSize="12" Foreground="$($c.Sub)" TextTrimming="CharacterEllipsis"/>
            </StackPanel>
          </StackPanel>
        </DockPanel>
        <WrapPanel x:Name="ChatTabs" DockPanel.Dock="Top" Margin="14,0,14,6" Visibility="Collapsed"/>
        <Border x:Name="ChatFind" DockPanel.Dock="Top" Visibility="Collapsed" Margin="14,0,14,6" CornerRadius="8" Background="$($c.Btn)" BorderBrush="$($c.Accent)" BorderThickness="1" Padding="10,1,3,1">
          <DockPanel>
            <Button x:Name="ChatFindClose" DockPanel.Dock="Right"/>
            <Button x:Name="ChatFindNext" DockPanel.Dock="Right"/>
            <Button x:Name="ChatFindPrev" DockPanel.Dock="Right"/>
            <TextBlock x:Name="ChatFindCount" DockPanel.Dock="Right" FontSize="12" Foreground="$($c.Sub)" VerticalAlignment="Center" Margin="8,0,4,0"/>
            <TextBox x:Name="ChatFindBox" FontSize="13" Background="Transparent" BorderThickness="0" Foreground="$($c.Text)" CaretBrush="$($c.Text)" VerticalAlignment="Center" Padding="0,5"/>
          </DockPanel>
        </Border>
        <Border DockPanel.Dock="Bottom" Margin="14,6,14,14" CornerRadius="12" Background="$($c.Btn)" BorderBrush="$($c.Border)" BorderThickness="1" Padding="12,6,6,6">
          <DockPanel>
            <WrapPanel x:Name="ChatAttach" DockPanel.Dock="Top" Visibility="Collapsed" Margin="0,2,0,4"/>
            <Button x:Name="ChatSend" DockPanel.Dock="Right" VerticalAlignment="Bottom"/>
            <Grid>
              <TextBlock x:Name="ChatHint" Text="Ask Claude anything - paste or drop screenshots and files" Foreground="$($c.Sub)" FontSize="14" Margin="3,6,0,0" IsHitTestVisible="False"/>
              <TextBox x:Name="ChatInput" AcceptsReturn="True" TextWrapping="Wrap" MaxHeight="150" MinHeight="30" FontSize="14" Background="Transparent" BorderThickness="0" Foreground="$($c.Text)" CaretBrush="$($c.Text)" VerticalScrollBarVisibility="Auto" Padding="0,5,0,0"/>
            </Grid>
          </DockPanel>
        </Border>
        <TextBlock x:Name="ChatEditing" DockPanel.Dock="Bottom" Margin="22,4,16,0" FontSize="12" Foreground="$($c.Accent)" TextTrimming="CharacterEllipsis" Visibility="Collapsed" Text="Editing your last message - Enter sends it in its place, Esc cancels"/>
        <TextBlock x:Name="ChatWorking" DockPanel.Dock="Bottom" Margin="22,4,16,0" FontSize="12" Foreground="$($c.Accent)" TextTrimming="CharacterEllipsis" Visibility="Collapsed"/>
        <Grid>
          <ScrollViewer x:Name="ChatScroll" VerticalScrollBarVisibility="Auto"><StackPanel x:Name="ChatList" Margin="18,4,16,8"/></ScrollViewer>
          <Border x:Name="ChatMenuPanel" Visibility="Collapsed" Background="$($c.Toast)" BorderBrush="$($c.Border)" BorderThickness="0,1,0,1">
            <DockPanel>
              <Border DockPanel.Dock="Top" Margin="14,12,14,6" CornerRadius="8" Background="$($c.Btn)" BorderBrush="$($c.Border)" BorderThickness="1" Padding="10,4">
                <Grid>
                  <TextBlock x:Name="ChatSearchHint" Text="Search conversations..." Foreground="$($c.Sub)" FontSize="13" Margin="2,4,0,0" IsHitTestVisible="False"/>
                  <TextBox x:Name="ChatSearch" FontSize="13" Background="Transparent" BorderThickness="0" Foreground="$($c.Text)" CaretBrush="$($c.Text)" Padding="0,4,0,4"/>
                </Grid>
              </Border>
              <ScrollViewer VerticalScrollBarVisibility="Auto"><StackPanel x:Name="ChatMenuList" Margin="10,2,10,12"/></ScrollViewer>
            </DockPanel>
          </Border>
        </Grid>
      </DockPanel>
    </Border>
  </Grid>
</Window>
"@
    $win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $xaml))
    $ui = @{}; foreach ($n in 'MainCol', 'ChatCol', 'ChatSplit', 'TopBar', 'AppName', 'Body', 'ChatMenu', 'ChatRemote', 'ChatTitle', 'ChatMenuPanel', 'ChatMenuList', 'ChatSearch', 'ChatSearchHint', 'Logo', 'NavList', 'Header', 'SubBox', 'SubNav', 'PageTitle', 'PageSub', 'Scroll', 'Content', 'Note', 'NoteBar', 'AiPill', 'NowBar', 'NowDot', 'NowText', 'ChatPanel', 'ChatClose', 'ChatNew', 'ChatStatus', 'ChatSend', 'ChatHint', 'ChatInput', 'ChatWorking', 'ChatEditing', 'ChatTabs', 'ChatMode', 'ChatFind', 'ChatFindBox', 'ChatFindCount', 'ChatFindPrev', 'ChatFindNext', 'ChatFindClose', 'ChatAttach', 'ChatScroll', 'ChatList') { $ui[$n] = $win.FindName($n) }
    $brush = @{}; foreach ($k in $c.Keys) { $brush[$k] = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString($c[$k])) }
    $levelBrush = @{ ok = $brush.Ok; info = $brush.Text; warn = $brush.Warn; dim = $brush.Sub }
    $onColor = if ($light) { [Windows.Media.Brushes]::White } else { [Windows.Media.Brushes]::Black }   # text on an Ok/Warn badge

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
    # a short note floating at the bottom; it goes away by itself after 12 seconds
    $noteTimer = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromSeconds(12) }
    $noteTimer.Add_Tick({ $ui.NoteBar.Visibility = 'Collapsed'; $noteTimer.Stop() })
    function Say($t) { $ui.Note.Text = $t; $ui.NoteBar.Visibility = if ($t) { 'Visible' } else { 'Collapsed' }; $noteTimer.Stop(); if ($t) { $noteTimer.Start() } }
    $psArgs = { param($file, [switch]$Keep) @('-NoProfile', '-ExecutionPolicy', 'Bypass') + @(if ($Keep) { '-NoExit' }) + @('-File', "`"$cl\$file`"") }
    $act = @{
        NewSession   = { if (Send-Tray $cmd.NewSession) { Say 'Opening Claude...' } elseif (Test-Path "$cl\Messiah Session.lnk") { Start-Process "$cl\Messiah Session.lnk" } else { Say 'The session shortcut is missing - run setup again.' } }
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
        # the preview of tweaks.ps1 (-Audit): what Messiah would change right now, in a window of its own - nothing is changed
        PreviewTweaks = { if (-not (Test-Path 'C:\PCSetupKit\tweaks.ps1')) { Say 'The tweaks script is missing - Repair Messiah first (Settings > Tools).'; return }
            Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-Command', "& 'C:\PCSetupKit\tweaks.ps1' -Audit"
            Say 'The preview opens in its own window (about 10 seconds) - it lists what would change and changes nothing.' }
        GpuRollback  = { if (Send-Tray $cmd.GpuRollback) { Say 'A window opens with the driver versions - it asks before changing anything.' } else { Start-Process powershell -Verb RunAs -ArgumentList (& $psArgs 'gpu-rollback.ps1' -Keep) } }
        Uninstall    = {
            if ([Windows.MessageBox]::Show("Remove Messiah from this PC?`n`nThe tray icon, the automatic maintenance, updates and the app go away. Your apps, files and games stay. The removed files are kept in a folder in case you want them back.", 'Uninstall Messiah', 'OKCancel', 'Warning') -ne 'OK') { return }
            $rv = [Windows.MessageBox]::Show("Also put back the Windows settings Messiah changed (telemetry, power plan, Game Bar, ...)?`n`nYes: Windows as it was before. No: keep them as they are now.", 'Uninstall Messiah', 'YesNoCancel', 'Question')
            if ($rv -eq 'Cancel') { return }
            $u = 'C:\PCSetupKit\uninstall.ps1'
            if (-not (Test-Path $u)) { Say 'The uninstaller is missing - Repair the kit first (Settings > Tools).'; return }
            Start-Process powershell -Verb RunAs -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$u`"", '-Yes') + @(if ($rv -eq 'Yes') { '-RevertTweaks' }))
            $win.Close() }
        FilesBackup  = { Start-Process powershell -WindowStyle Hidden -ArgumentList ((& $psArgs 'files-backup.ps1') + '-Enable'); & "$cl\todo.ps1" -Id 'backup' -Done
            Say 'Backing up your files to that drive now - from now on it happens by itself whenever the drive is connected.'; Update-View -Force }
        Welcomed     = { Set-Opt 'welcome' 'done'; $script:welcomeDone = $true; Update-Nav; Show-Page 'Home'; if ((Get-Opt 'tour' '') -ne 'done') { Show-Tour 0 } }
        # the Status tab's Check now: the tray runs the guard (after-update.ps1 -Now) - the page shows it checking until the
        # guard's new status arrives (3 minutes at most), then says how it went
        CheckNow     = { if (Send-Tray $cmd.ApplyTweaks) { $script:checkingSince = (Get-Date).AddSeconds(-2); $script:stCache.Remove('tasks'); $script:stCache.Remove('diag'); Update-View -Force }
            else { Say 'The tray isn''t running - it starts at the next login.'; Start-ScheduledTask 'Messiah Tray' -ErrorAction SilentlyContinue } }
        # a crash-hunting mode switched off (the Status tab's button): asked first; Windows' own tool, with admin rights (a
        # prompt); it stops at the next restart
        DiagOff      = { param($id)
            $what = switch ($id) { 'verifier' { 'Driver Verifier' } 'debug' { 'kernel debugging' } default { 'test signing' } }
            if ([Windows.MessageBox]::Show("Turn off $what?`n`nIt stops at the next restart (Messiah never restarts the PC). Do this once you're done hunting the crash - if blue screens come back later, it can be turned on again.", 'Crash-hunting mode', 'OKCancel', 'Question') -ne 'OK') { return }
            $exe, $a_ = switch ($id) { 'verifier' { 'verifier.exe', '/reset' } 'debug' { 'bcdedit.exe', '/debug off' } default { 'bcdedit.exe', '/set testsigning off' } }
            try { Start-Process $exe -ArgumentList $a_ -Verb RunAs -WindowStyle Hidden -Wait -ErrorAction Stop; $script:stCache.Remove('diag'); Say "$((Get-Culture).TextInfo.ToTitleCase($what)) is off from the next restart."; Update-View -Force }
            catch { Say "Not turned off - $($_.Exception.Message)" } }
    }

    # --- building blocks
    function New-Text($t, $brush_ = $brush.Text, $size = 14, $weight = 'Normal', $margin = '0,1,0,1') {
        New-Object Windows.Controls.TextBlock -Property @{ Text = $t; TextWrapping = 'Wrap'; Foreground = $brush_; FontSize = $size; FontWeight = $weight; Margin = $margin }
    }
    function New-Glyph($g, $size = 16, $brush_ = $brush.Text) {
        New-Object Windows.Controls.TextBlock -Property @{ Text = [string][char][int]"0x$g"; FontFamily = $icons; FontSize = $size; Foreground = $brush_; VerticalAlignment = 'Center'; Tag = 'icon' }
    }
    function New-Tint($b, [byte]$alpha) { $col = $b.Color; $col.A = $alpha; New-Object Windows.Media.SolidColorBrush $col }   # a status color, faint
    # report lines in plain words: "10/10/2026 9:01 AM" -> "today 9:01 AM", "in 48s" -> "(took 48 s)"
    function Format-Line([string]$t) {
        $t = [regex]::Replace($t, '\b\d{1,2}/\d{1,2}/\d{4}(?: \d{1,2}:\d\d(?::\d\d)?(?: [AP]M)?)?', {
                param($m) $d = [datetime]::MinValue
                if ([datetime]::TryParse($m.Value, [ref]$d)) { if ($m.Value -match ':') { Format-When $d } else { Format-When $d -DateOnly } } else { $m.Value } })
        $t -replace ' in (\d+)s\b', ' (took $1 s)'
    }
    # a line with its status as an icon (warning, reminder, all fine) instead of colored text: easier to read, the
    # "WARNING:" / "Reminder:" words become the icon
    function New-Line($text, $level) {
        $text = Format-Line (($text -replace '^- ', "$([char]0x2022)  ") -replace '\s{2,}', '  ')
        $glyph = $null; $gb = $null
        if ($text -match '^(WARNING|FAILED)\b:?\s*' -or $level -eq 'warn') { $glyph = 'E7BA'; $gb = $brush.Warn; $text = $text -replace '^WARNING:\s*', '' }
        elseif ($text -match '^Reminder:\s*') { $glyph = 'E946'; $gb = $brush.Accent; $text = $text -replace '^Reminder:\s*', '' }
        elseif ($level -eq 'ok') { $glyph = 'E73E'; $gb = $brush.Ok }
        if ($text.Length) { $text = $text.Substring(0, 1).ToUpper() + $text.Substring(1) }
        $size = if ($level -eq 'dim') { 12 } else { 14 }
        $tb = New-Text $text $(if ($level -eq 'dim') { $brush.Sub } else { $brush.Text }) $size 'Normal' '0'
        if (-not $glyph) { $tb.Margin = '0,3,0,3'; return $tb }
        $row = New-Object Windows.Controls.DockPanel -Property @{ Margin = '0,4,0,4' }
        $g = New-Glyph $glyph 14 $gb; $g.VerticalAlignment = 'Top'; $g.Margin = '0,2,10,0'; [Windows.Controls.DockPanel]::SetDock($g, 'Left')
        [void]$row.Children.Add($g); [void]$row.Children.Add($tb); $row
    }
    function New-Btn($glyph, $text, [scriptblock]$do, [switch]$Accent, [switch]$Small) {   # -Small: inside a list row
        $sp = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
        [void]$sp.Children.Add((New-Glyph $glyph $(if ($Small) { 12 } else { 14 }) $(if ($Accent) { $brush.OnAccent } else { $brush.Text })))
        [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $text; Margin = '8,0,0,0'; VerticalAlignment = 'Center' }))
        $b = New-Object Windows.Controls.Button -Property @{ Content = $sp; Tag = $do; ToolTip = $text }
        [Windows.Automation.AutomationProperties]::SetName($b, $text)   # (Narrator reads the words, not the icon)
        $b.Style = $win.FindResource($(if ($Accent) { 'AccentBtn' } elseif ($Small) { 'SmallBtn' } else { 'Btn' }))
        $b.Add_Click({ try { & $this.Tag } catch { Say "Couldn't do that: $($_.Exception.Message)" } })
        $b
    }
    function New-Card($title, $glyph, $lines, $buttons, [switch]$Calm) {   # -Calm: warn lines in the normal text color (long text, the header says it)
        $card = New-Object Windows.Controls.Border -Property @{ Background = $brush.Card; BorderBrush = $brush.Border; BorderThickness = 1; CornerRadius = 12; Padding = '22,18'; Margin = '0,0,0,14' }
        $sp = New-Object Windows.Controls.StackPanel
        if ($title) {
            $hd = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal'; Margin = '0,0,0,10' }
            if ($glyph) {
                $chip = New-Object Windows.Controls.Border -Property @{ Width = 28; Height = 28; CornerRadius = 8; Background = (New-Tint $brush.Accent 0x26); VerticalAlignment = 'Center' }
                $chip.Child = New-Glyph $glyph 14 $brush.Accent; $chip.Child.HorizontalAlignment = 'Center'
                [void]$hd.Children.Add($chip)
            }
            $t = New-Text $title $brush.Text 16 'SemiBold' '0'; $t.VerticalAlignment = 'Center'; $t.FontFamily = $display; if ($glyph) { $t.Margin = '12,0,0,0' }
            [void]$hd.Children.Add($t); [void]$sp.Children.Add($hd)
        }
        foreach ($l in $lines) {
            if ($l -is [Windows.UIElement]) { [void]$sp.Children.Add($l); continue }
            [void]$sp.Children.Add((New-Line $l.Text $(if ($Calm -and $l.Level -eq 'warn') { 'info' } else { $l.Level })))
        }
        if ($buttons) {
            $wp = New-Object Windows.Controls.WrapPanel -Property @{ Margin = '0,14,0,-8' }
            foreach ($b in $buttons) { [void]$wp.Children.Add($b) }
            [void]$sp.Children.Add($wp)
        }
        $card.Child = $sp; $card
    }
    # "today 10:35 AM", "yesterday 9:02 PM", "Mon 8:15 AM" (this week), "Sep 20" (older); -Short: without "today"
    # -DateOnly: a day without a time ("today", "tomorrow", "Mon", "Sep 20")
    function Format-When([datetime]$d, [switch]$Short, [switch]$DateOnly) {
        $days = ((Get-Date).Date - $d.Date).Days
        $at = if ($DateOnly) { '' } else { " $($d.ToString('h:mm tt'))" }
        if ($days -eq 0) { if ($Short -and -not $DateOnly) { $d.ToString('h:mm tt') } else { "today$at" } }
        elseif ($days -eq 1) { "yesterday$at" } elseif ($days -eq -1) { "tomorrow$at" }
        elseif ($days -lt 7 -and $days -gt 0) { "$($d.ToString('ddd'))$at" } else { $d.ToString('MMM d') }
    }
    function Update-Columns { if ($script:tileGrid -and $ui.Scroll.ActualWidth -gt 0) { $script:tileGrid.Columns = [Math]::Max(1, [Math]::Min([Math]::Max(1, [Math]::Min(5, $script:tileGrid.Children.Count)), [int][Math]::Floor(([Math]::Min(1100, $ui.Scroll.ActualWidth - 2 * $ui.Body.Margin.Left)) / 200))) } }
    function New-Section($t) { New-Text $t $brush.Sub 13 'SemiBold' '4,14,0,10' }   # a heading between groups of cards
    # a small status tile (Home): a label, the value big, one line under it; a click goes to its page ("Page/Sub")
    function New-Tile($glyph, $label, $value, $sub, $level = 'info', $goto) {
        $b = New-Object Windows.Controls.Border -Property @{ Background = $brush.Card; BorderBrush = $brush.Border; BorderThickness = 1; CornerRadius = 12; Padding = '18,14'; Margin = '0,0,12,12' }
        $sp = New-Object Windows.Controls.StackPanel
        $hd = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
        [void]$hd.Children.Add((New-Glyph $glyph 14 $brush.Accent)); $l = New-Text $label $brush.Sub 12 'Normal' '8,0,0,0'; $l.VerticalAlignment = 'Center'; [void]$hd.Children.Add($l)
        [void]$sp.Children.Add($hd)
        $v = New-Text $value $(if ($level -eq 'info') { $brush.Text } else { $levelBrush[$level] }) 22 'SemiBold' '0,8,0,0'; $v.FontFamily = $display
        [void]$sp.Children.Add($v)
        [void]$sp.Children.Add((New-Text $sub $brush.Sub 12 'Normal' '0,2,0,0'))
        $b.Child = $sp
        if ($goto) {
            $b.Cursor = 'Hand'; $b.Tag = $goto; $b.ToolTip = 'Open'
            $b.Focusable = $true; $b.FocusVisualStyle = $null; [Windows.Automation.AutomationProperties]::SetName($b, "$label - $value. $sub")
            $b.Add_GotKeyboardFocus({ $this.Background = $brush.CardHover }); $b.Add_LostKeyboardFocus({ $this.Background = $brush.Card })
            $b.Add_KeyDown({ param($s_, $e_) if ($e_.Key -in 'Return', 'Space') { $pg, $sb = "$($s_.Tag)" -split '/', 2; Show-Page $pg $sb; $e_.Handled = $true } })
            $b.Add_MouseEnter({ $this.Background = $brush.CardHover }); $b.Add_MouseLeave({ $this.Background = $brush.Card })
            $b.Add_MouseLeftButtonUp({ $pg, $sb = "$($this.Tag)" -split '/', 2; Show-Page $pg $sb })
        }
        $b
    }
    # a setting with a switch on the right; $do gets the switch ($this) when it's clicked
    function New-SwitchRow($title, $sub, [bool]$on, [scriptblock]$do, $tag) {
        $r = New-Object Windows.Controls.DockPanel -Property @{ Margin = '0,0,0,16' }
        $s = New-Object Windows.Controls.CheckBox -Property @{ IsChecked = $on; VerticalAlignment = 'Center'; Tag = $tag; Margin = '20,0,0,0' }
        $s.Style = $win.FindResource('Switch'); [Windows.Controls.DockPanel]::SetDock($s, 'Right')
        [Windows.Automation.AutomationProperties]::SetName($s, $title); [Windows.Automation.AutomationProperties]::SetHelpText($s, $sub)
        $s.Add_Click($do)
        $l = New-Object Windows.Controls.StackPanel
        [void]$l.Children.Add((New-Text $title $brush.Text 14 'Normal' '0'))
        # what it does, then what "off" means on a line of its own (one long sentence is hard to scan)
        $parts = $sub -split '(?<=\.|\))\s+(?=Off(?: again)?: |Off \(default\): )', 2
        [void]$l.Children.Add((New-Text $parts[0] $brush.Sub 12 'Normal' '0,2,0,0'))
        if ($parts.Count -gt 1) { [void]$l.Children.Add((New-Text $parts[1] $brush.Sub 12 'Normal' '0,1,0,0')) }
        [void]$r.Children.Add($s); [void]$r.Children.Add($l); $r
    }
    # to-do items with their own buttons: the place to fix it where there is one, and "Snooze a week" (todo.ps1
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
    # each item: a row of its own - a status dot, the item in a sentence, its buttons under it; thin lines between rows
    function New-TodoLines($lines) {
        $first = $true
        foreach ($l in @($lines)) {
            if ($l.Level -ne 'warn') { $l; continue }
            $text = ($l.Text -replace '^- ', '').Trim()
            $row = New-Object Windows.Controls.DockPanel -Property @{ Margin = $(if ($first) { '0,2,0,0' } else { '0,12,0,0' }) }
            if (-not $first) { $row.Children.Add((New-Object Windows.Controls.Border -Property @{ Height = 1; Background = $brush.Divider; Margin = '0,0,0,12' })) | Out-Null; [Windows.Controls.DockPanel]::SetDock($row.Children[0], 'Top') }
            $first = $false
            $dot = New-Object Windows.Shapes.Ellipse -Property @{ Width = 10; Height = 10; Fill = $brush.Warn; VerticalAlignment = 'Top'; Margin = '0,6,14,0' }
            [Windows.Controls.DockPanel]::SetDock($dot, 'Left'); [void]$row.Children.Add($dot)
            $body = New-Object Windows.Controls.StackPanel
            # long items: the first part as the line, the how-to behind "Details" (a wall of steps is hard to scan)
            $head = $text; $more = $null
            if ($text.Length -gt 140 -and $text -match '^(.{30,160}?)(?: - |\. |: )(.+)$') { $head = $Matches[1].TrimEnd('.') + '.'; $more = $Matches[2] }
            [void]$body.Children.Add((New-Text $head $brush.Text 14 'Normal' '0'))
            if ($more) { $mt = New-Text $more $brush.Sub 13 'Normal' '0,6,0,0'; $mt.Visibility = 'Collapsed'; [void]$body.Children.Add($mt) }
            $bp = New-Object Windows.Controls.WrapPanel -Property @{ Margin = '0,8,0,0' }   # (small buttons, no gap under them)
            if ($more) { $db = New-Btn 'E946' 'How to' -Small { $t = $this.DataContext; $t.Visibility = if ($t.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' } }; $db.DataContext = $mt; [void]$bp.Children.Add($db) }
            $fx = Get-TodoFix $text
            if ($fx) { $b = New-Btn 'E8A7' $fx[0] -Small { $c = $this.Uid; if ($c -eq 'kit:gpu-rollback') { & $act.GpuRollback } elseif ($c -like 'kit:uninstall:*') { Start-Process powershell -Verb RunAs -ArgumentList ((& $psArgs 'junk-apps.ps1') + '-Remove', "`"$($c.Substring(14))`""); Say 'Its own uninstaller opens - follow it; the item goes away once it is removed.' } elseif ($c -eq 'kit:files-backup') { & $act.FilesBackup } elseif ($c -match '^(\S+\.exe)( (.+))?$') { if ($Matches[3]) { Start-Process $Matches[1] -ArgumentList $Matches[3] } else { Start-Process $Matches[1] } } else { Start-Process $c } }; $b.Uid = $fx[1]; [void]$bp.Children.Add($b) }   # (Uid: the button's own data)
            $sb = New-Btn 'E823' 'Snooze a week' -Small { & "$cl\todo.ps1" -Snooze $this.Uid -Days 7; Say 'Snoozed - it comes back in a week if it still needs you.'; Update-View -Force }
            $sb.Uid = $text; [void]$bp.Children.Add($sb)
            # (todo.ps1 -Dismiss: gone for 90 days, like deleting the line - Claude doesn't write the same line again)
            $xb = New-Btn 'E711' 'Dismiss' -Small { & "$cl\todo.ps1" -Dismiss $this.Uid; Say 'Dismissed - it stays off the list for 90 days (Claude won''t add the same item again).'; Update-View -Force }
            $xb.Uid = $text; [void]$bp.Children.Add($xb)
            [void]$body.Children.Add($bp); [void]$row.Children.Add($body); $row
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
            $a = New-Text $p[0] $brush.Sub 13 'Normal' '0,5,24,5'; [Windows.Controls.Grid]::SetRow($a, $i)
            $b = New-Text (Format-Line $p[1]) $levelBrush[$p[2]] 14 'Normal' '0,5,0,5'; [Windows.Controls.Grid]::SetRow($b, $i); [Windows.Controls.Grid]::SetColumn($b, 1)
            [void]$g.Children.Add($a); [void]$g.Children.Add($b); $i++
        }
        $g
    }
    function Sec($secs, $t) { $secs | Where-Object { $_.Title -like "$t*" } | Select-Object -First 1 }
    # every change the kit makes, by group: id, title, what it does (and what "off" means), the default for opt-in ones -
    # the Settings > Windows switches and the Status tab's details
    function Get-TweakCatalog {
        [ordered]@{
            'Speed and games'     = @(
                @('memory-integrity', 'Memory integrity off', 'Core isolation (VBS) costs 0-15% frame rate, mostly in games limited by the processor (little when the graphics card is the limit). Some anti-cheats check it. Off: extra protection against malicious drivers, a bit less speed.'),
                @('game-bar', 'Xbox Game Bar removed', 'Its overlay and background capture cost frame rate. Off: it comes back. (Always kept on AMD dual-CCD X3D CPUs, which need it.)'),
                @('game-recording', 'Background game recording off', 'Game DVR records every game in the background. Off: recording and clips work again.'),
                @('windowed-games', 'Optimizations for windowed games and VRR', 'Lower input lag in borderless-window games, variable refresh rate where supported.'),
                @('mouse-acceleration', 'Mouse acceleration off', 'The same hand movement always moves the cursor the same distance - better aim.'),
                @('end-task', '"End task" in the taskbar menu', 'Right-click a frozen game on the taskbar and close it - no Task Manager needed.'),
                @('sticky-keys', 'Sticky Keys pop-up off','Pressing Shift five times in a game no longer opens the Sticky Keys prompt and throws you out of fullscreen. The feature itself stays in Accessibility.'),
                @('power-plan', 'Best power plan', 'Desktops: Ultimate Performance (Balanced on AMD''s dual-CCD X3D processors, as AMD recommends). Laptops: Balanced, full speed when plugged in. Off: your own plan.'),
                @('network-defaults', 'Network kept at Windows'' defaults', 'Some "gaming tweak" tools turn off network throttling and Nagle''s algorithm - tests show that adds lag rather than removing it. Messiah puts Windows'' own values back if a tool changes them. Off: left as other tools set them.'),
                @('sysmain-off', 'SysMain (app prefetch) off', 'Off unless you turn it on. No measured gain on an SSD - Windows'' default is to keep it. Off again: back as it was.', 'off'),
                @('hibernation', 'Hibernation off (desktops)', 'Frees disk space and gives a clean start every time. Laptops always keep it.'))
            'Privacy and clutter' = @(
                @('telemetry', 'Telemetry, ads and Windows AI off', 'No diagnostic data, ads, suggestions, Bing in search, Copilot, Recall or the AI parts of Notepad, Paint and Edge. May break: Xbox achievements in some games and the Feedback Hub (they need the diagnostics service). Off: all of it back as it was.'),
                @('bloat-apps', 'Preinstalled apps removed', 'News, Weather, Teams, Clipchamp, Solitaire, TikTok and the like. Off: Messiah stops removing them (reinstall any from the Microsoft Store).'),
                @('onedrive', 'OneDrive removed', 'Off: OneDrive comes back and can sync again.'),
                @('edge-remove', 'Remove Edge completely', 'Off unless you turn it on. Uninstalls the Edge browser and keeps it from coming back; WebView2 - the part apps and game launchers need - stays. Your Edge bookmarks stay on the PC. Off again: Edge is reinstalled.', 'off'),
                @('edge', 'Edge kept out of the way','Edge stays installed (Windows and many apps need it), but no desktop icon, no taskbar pin, no prompts, and Chrome is your browser. Off: its icon and prompts come back.'),
                @('notifications-off', 'All app notifications off', 'Off unless you turn it on. Silences every app''s pop-ups (Discord, calendar, mail) - Windows'' own suggestions are off either way. Off again: they come back.', 'off'),
                @('start-menu', 'Start menu recommendations and Task View off', 'A cleaner Start menu and taskbar.'),
                @('legacy', 'Old Windows parts removed', 'Internet Explorer''s engine, the old Media Player, WordPad, Steps Recorder and the like; PowerShell 2.0 and Recall off; reserved storage (about 7 GB) freed. Never what updates need. Off: they come back.'),
                @('vendor-installers', 'Razer and Logitech apps don''t install by themselves', 'Plugging in one of their mice or headsets no longer makes Windows install Razer Synapse or Logitech''s download assistant (drivers still come). Off: they can install again.'),
                @('folder-types', 'File Explorer doesn''t guess folder types', 'Every folder opens the same way instead of Explorer reading the files first to pick a layout - big folders open faster. Off: the guessing (Pictures, Music views) comes back.'),
                @('startup-clutter', 'Start-up clutter off','Vendor updaters and promo tools don''t start with Windows. Off: they start again.'),
                @('transparency', 'Transparency effects off', 'Slightly less work for the graphics card. Off: see-through Start menu and windows again.'))
            'Windows Update'      = @(
                @('restart-block', 'No Windows Update restarts while you''re signed in', 'Updates still install; the restart waits for yours.'),
                @('feature-delay', 'Big Windows upgrades wait 45 days', 'The yearly new Windows version comes once its first problems are fixed; security and monthly updates still come right away. (Windows Pro and up; Home ignores it.)'))
        }
    }
    # --- the settings in plain words (the Status tab's "Checks N settings"): by registry name, or "<key>\<name>" where a name
    # means different things in different places. Settings > General > "Show technical names" shows the registry names instead.
    $plain = @{
        NetworkThrottlingIndex = 'Network throttling (Windows default)'; DirectXUserGlobalSettings = 'Windowed-games optimizations and VRR'; ToastEnabled = 'App notifications'
        AllowGameDVR = 'Game DVR (policy)'; GameDVR_Enabled = 'Background game recording'; AppCaptureEnabled = 'Game capture'
        EnableVirtualizationBasedSecurity = 'Virtualization-based security'; 'HypervisorEnforcedCodeIntegrity\Enabled' = 'Memory integrity'
        'Windows.SystemToast.Suggested\Enabled' = 'Windows'' "suggested" pop-ups'
        DeferFeatureUpdates = 'Hold back big upgrades'; DeferFeatureUpdatesPeriodInDays = 'Days to hold them (45)'; IsContinuousInnovationOptedIn = '"Get the latest updates first"'
        EnableTransparency = 'Transparency effects'; NoAutoRebootWithLoggedOnUsers = 'No update restart while signed in'; SetActiveHours = 'Active hours on'
        ActiveHoursStart = 'Active hours start (8:00)'; ActiveHoursEnd = 'Active hours end (2:00)'; TaskbarEndTask = '"End task" in the taskbar'
        EnablePeriodicBackup = 'Registry backups'; 'StickyKeys\Flags' = 'Sticky Keys shortcut'; 'ToggleKeys\Flags' = 'Toggle Keys shortcut'; 'Keyboard Response\Flags' = 'Filter Keys shortcut'
        DisableFileSyncNGSC = 'OneDrive sync (policy)'; FolderType = 'Folder type guessing'; AutoGameModeEnabled = 'Game Mode'; HwSchMode = 'Hardware GPU scheduling'
        DisableWpbtExecution = 'Motherboard auto-installer (WPBT)'; PreventDeviceMetadataFromNetwork = 'Device companion-app downloads'; CrashDumpEnabled = 'Crash dumps'
        AlwaysKeepMemoryDump = 'Keep the crash dump'; DisplayParameters = 'Blue screen names its cause'; LongPathsEnabled = 'Long file paths'
        'Application\MaxSize' = 'Application log size'; 'System\MaxSize' = 'System log size'; 'Windows PowerShell\MaxSize' = 'PowerShell log size'
        'Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' = 'Edge may not reinstall'; MouseSpeed = 'Mouse acceleration'; MouseThreshold1 = 'Acceleration threshold 1'; MouseThreshold2 = 'Acceleration threshold 2'
        HideFirstRunExperience = 'Edge first-run pages'; DefaultBrowserSettingEnabled = 'Edge "make me default" prompts'; CopilotPageContext = 'Copilot reading pages'
        CopilotCDPPageContext = 'Copilot page context'; EdgeEntraCopilotPageContext = 'Copilot page context (work)'; EdgeHistoryAISearchEnabled = 'AI history search'
        ComposeInlineEnabled = 'Edge "compose" AI'; NewTabPageBingChatEnabled = 'Bing chat on new tab'; NewTabPageContentEnabled = 'News on new tab'
        EdgeShoppingAssistantEnabled = 'Shopping assistant'; ShowRecommendationsEnabled = 'Edge recommendations'; SpotlightExperiencesAndRecommendationsEnabled = 'Edge spotlight suggestions'
        WalletDonationEnabled = 'Donation upsell'; ShowAcrobatSubscriptionButton = 'Acrobat upsell'; CreateDesktopShortcutDefault = 'Edge desktop icon on update'
        'CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}' = 'Edge desktop icon (Edge)'; ShowCopilotButton = 'Copilot button'; ShowTaskViewButton = 'Task View button'
        Start_IrisRecommendations = 'Start recommendations'; Start_TrackDocs = 'Recent files in Start'; Start_AccountNotifications = 'Account nags in Start'
        AllowTelemetry = 'Telemetry level'; DoNotShowFeedbackNotifications = 'Feedback prompts'; DisableWindowsConsumerFeatures = 'Auto-installed promo apps'
        DisableSoftLanding = 'Windows tips'; DisableCloudOptimizedContent = 'Cloud promo content'; DisableTailoredExperiencesWithDiagnosticData = 'Ads from diagnostic data (policy)'
        EnableActivityFeed = 'Activity history'; PublishUserActivities = 'Publish activity'; UploadUserActivities = 'Upload activity'; DisabledByGroupPolicy = 'Advertising ID (policy)'
        AllowCortana = 'Cortana'; DisableWebSearch = 'Web results in search'; ConnectedSearchUseWeb = 'Bing in search'; TurnOffWindowsCopilot = 'Copilot'
        DisableAIDataAnalysis = 'Recall snapshots analysis'; DisableClickToDo = 'Click to Do'; TurnOffSavingSnapshots = 'Recall snapshots'; AllowRecallEnablement = 'Recall'
        DisableAIFeatures = 'Notepad AI'; DisableCocreator = 'Paint Cocreator'; DisableGenerativeFill = 'Paint generative fill'; DisableImageCreator = 'Paint image creator'
        DisableGenerativeErase = 'Paint generative erase'; DisableRemoveBackground = 'Paint background removal'; DisableConsumerAccountStateContent = 'Microsoft 365 ads in Settings'
        DODownloadMode = 'Update sharing (home network only)'; AllowNewsAndInterests = 'Widgets'; StartupBoostEnabled = 'Edge startup boost'; BackgroundModeEnabled = 'Edge in the background'
        HubsSidebarEnabled = 'Edge sidebar'; DontSendAdditionalData = 'Extra crash data to Microsoft'; DisableSearchBoxSuggestions = 'Search box suggestions'
        ContentDeliveryAllowed = 'Promo content'; OemPreInstalledAppsEnabled = 'PC-maker promo apps'; PreInstalledAppsEnabled = 'Preinstalled promo apps'
        PreInstalledAppsEverEnabled = 'Promo apps ever'; SilentInstalledAppsEnabled = 'Silently installed apps'; SoftLandingEnabled = 'Tips and tricks'
        SystemPaneSuggestionsEnabled = 'Start suggestions'; RotatingLockScreenOverlayEnabled = 'Lock screen fun facts'; 'SubscribedContent-310093Enabled' = 'Welcome experience'
        'SubscribedContent-338388Enabled' = 'Start suggestions (2)'; 'SubscribedContent-338389Enabled' = 'Tips about Windows'; 'SubscribedContent-353694Enabled' = 'Suggested content in Settings'
        'SubscribedContent-353696Enabled' = 'Suggested content in Settings (2)'; 'SubscribedContent-338393Enabled' = 'Suggested content in Settings (3)'
        'SubscribedContent-353698Enabled' = 'Timeline suggestions'; 'SubscribedContent-338387Enabled' = 'Lock screen tips'; ShowSyncProviderNotifications = 'OneDrive / 365 ads in Explorer'
        ScoobeSystemSettingEnabled = '"Finish setting up" prompts'; TailoredExperiencesWithDiagnosticDataEnabled = 'Ads from diagnostic data'; BingSearchEnabled = 'Bing in Start search'
        'AdvertisingInfo\Enabled' = 'Advertising ID'
    }
    function Get-PlainName([string]$Full) {
        $p_ = $Full -split '\\'; $leaf = $p_[-1]; $two = if ($p_.Count -ge 2) { "$($p_[-2])\$leaf" }
        if ((Get-Opt 'technames' 'off') -eq 'on') { return $leaf }
        if ($two -and $plain.ContainsKey($two)) { $plain[$two] } elseif ($plain.ContainsKey($leaf)) { $plain[$leaf] } else { $leaf }
    }
    # --- the Status tab's model, shared with Home's Guarded tile: every optimization Messiah keeps, one row each, with what
    # the last guard pass found - ok (in place, or put back by that pass), warn (needs a look), dim (off by the owner's
    # choice, or not checked yet). The guard runs at login, every 4 hours and 2 minutes after each Windows or driver update
    # (tweak-status.json from tweaks.ps1 -StatusFile, guard-state.json, diag-state.json; a few live reads for the rest).
    # -Details: each row's details too (what it does, what it checks, its history) and its fix-it button - Home needs only
    # the counts. Slow reads (scheduled tasks, screen modes, crash-hunting modes, the change history) are kept a minute.
    if (-not $script:stCache) { $script:stCache = @{} }
    function Get-Cached([string]$Key, [int]$Seconds, [scriptblock]$Read) {
        $c_ = $script:stCache[$Key]
        if ($c_ -and $c_.At -gt (Get-Date).AddSeconds(-$Seconds)) { return $c_.Value }   # (items one by one: callers wrap lists in @())
        $v_ = & $Read; $script:stCache[$Key] = @{ At = Get-Date; Value = $v_ }; $v_
    }
    function Read-Json([string]$File) { $j_ = try { Get-Content $File -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { $null }; if ($j_ -is [Management.Automation.PSCustomObject]) { $j_ } }
    function Get-StatusModel([switch]$Details) {
        $ts = Read-Json "$cl\tweak-status.json"; $gs = Read-Json "$cl\guard-state.json"
        $tsAt = $null; if ($ts -and $ts.at) { $tmp = [datetime]::MinValue; if ([datetime]::TryParse("$($ts.at)", [ref]$tmp)) { $tsAt = $tmp } }
        $optInL = if ($ts -and $ts.optIn) { @($ts.optIn) } else { @('edge-remove', 'notifications-off', 'sysmain-off') }
        $cause = if ($ts -and $ts.cause) { "$($ts.cause)" }
        $rows = New-Object Collections.ArrayList
        $addRow = { param($card, $title, $lv, $st, $dt, $more, $fix) [void]$rows.Add(@{ Card = $card; Title = $title; Level = $lv; State = $st; Detail = $dt; More = $more; Fix = $fix }) }
        $checkNow = @('E72C', 'Put it back now', { & $act.CheckNow })
        $rowState = { param($keys, $g)
            if ($g -and (Get-Opt "tweak.$g" $(if ($g -in $optInL) { 'off' } else { 'on' })) -eq 'off') { return 'dim', $(if ($g -in $optInL) { 'Not turned on' } else { 'Off - your choice' }), $null }
            if (-not $tsAt) { return 'dim', 'Not checked yet', $null }
            $same = 0; $blk = 0; $kept = 0; $fx = @()
            foreach ($k in $keys) { $e = $ts.keys.$k; if ($e) { $same += [int]$e.same; $blk += [int]$e.blocked; $kept += [int]$e.kept; $fx += @($e.fixed | Where-Object { $_ }) } }
            $note = (@(if ($blk) { "$blk protected by Windows itself (left as they are)" }) + @(if ($kept) { "$kept kept the way you chose" })) -join '; '; if (-not $note) { $note = $null }
            if ($fx) {
                $what = ($fx | Select-Object -Unique -First 4 | ForEach-Object { Get-PlainName $_ }) -join ', '
                if ($ts.preview) { return 'warn', 'Changed - put back at the next check', $what }
                return 'ok', "Put back $(Format-When $tsAt -Short)", "Something had changed it: $what$(if ($cause) { " - after $cause" })" }
            'ok', $(if ($same) { "In place ($same)" } else { 'In place' }), $note
        }
        if ($Details) {
            $desc = @{}; $twc = Get-TweakCatalog; foreach ($g_ in $twc.Keys) { foreach ($o in $twc[$g_]) { $desc[$o[0]] = $o[2] } }
            $hf = Get-Item 'C:\PCSetupKit\change-history.log' -ErrorAction SilentlyContinue
            $hist = if ($hf) { Get-Cached "hist|$($hf.LastWriteTime.Ticks)" 3600 { @(Get-Content $hf.FullName -Tail 3000 -Encoding UTF8 -ErrorAction SilentlyContinue) } } else { @() }
            $keeps = Get-Keeps
        }
        # its history (C:\PCSetupKit\change-history.log: tweaks.ps1's before -> after, with what changed it back): the last 3,
        # each with the setting (Full) and the value it had before Messiah put its own back (Old) - for "keep that value"
        $histOf = { param($names, $rx)
            $pat = @(@($names | Where-Object { $_ } | ForEach-Object { if ($_ -match '\\') { "^$([regex]::Escape($_)) '" } else { "\\$([regex]::Escape($_)) '" } }) + @($rx | Where-Object { $_ })) -join '|'
            if (-not $pat) { return }
            @($hist | Where-Object { $_ -match "^(\d{4}-\d\d-\d\d \d\d:\d\d)\s+(.+)$" -and $Matches[2] -match $pat } | Select-Object -Last 3 | ForEach-Object {
                    $null = $_ -match '^(\d{4}-\d\d-\d\d \d\d:\d\d)\s+(.+)$'; $at_ = $Matches[1]; $w = $Matches[2]; $full = $null; $old = $null
                    if ($w -match "^(.+?) '(.*)' -> '(.*?)'(.*)$") {
                        $full = $Matches[1]; $old = if ($Matches[2] -eq '' -or $Matches[2] -eq '(not set)') { '(not set)' } else { $Matches[2] }
                        $w = "$(Get-PlainName $full): $old -> $($Matches[3])$($Matches[4])" }
                    elseif ($w -match "^(.+?) '(.*)' -> \(not set\)(.*)$") { $full = $Matches[1]; $old = $Matches[2]; $w = "$(Get-PlainName $full): $old -> (not set)$($Matches[3])" }
                    if ($w -match '\(your choice\)') { $full = $null }   # (the owner's own change: nothing to keep)
                    [pscustomobject]@{ Text = "$(Format-When ([datetime]::ParseExact($at_, 'yyyy-MM-dd HH:mm', $null))) - $($w -replace ' \[after (.+)\]$', ' (after $1)')"; Full = $full; Old = $old } })
        }
        $moreOf = { param($keys, $g, $about, $rx)
            if (-not $Details) { return }
            $m = New-Object Collections.ArrayList
            $d_ = if ($about) { $about } elseif ($g) { $desc[$g] }
            if ($d_) { [void]$m.Add(@('What it does', $d_)) }
            $names = @(foreach ($k in $keys) { $e = $ts.keys.$k; if ($e) { @($e.names) } }) | Where-Object { $_ } | Select-Object -Unique
            $leaf = @($names | ForEach-Object { Get-PlainName $_ } | Select-Object -Unique)   # (in plain words; their full place in the registry is what history is matched by)
            if ($names) { [void]$m.Add(@("Checks $(@($names).Count) setting$(if (@($names).Count -ne 1) { 's' })", "$(($leaf | Select-Object -First 14) -join ', ')$(if ($leaf.Count -gt 14) { " and $($leaf.Count - 14) more" })")) }
            if ($tsAt) { [void]$m.Add(@('Last check', "$(Format-When $tsAt) - $(if ($ts.preview) { 'a preview' } else { 'at login, every 4 hours and after each update' })")) }
            $h = @(& $histOf $names $rx)
            if (-not $h) { [void]$m.Add(@('History', 'Never had to be put back')) }
            $first = $true; $offered = @{}
            foreach ($x in @($h | Sort-Object { $h.IndexOf($_) } -Descending)) {
                [void]$m.Add(@($(if ($first) { 'History' } else { '' }), $x.Text)); $first = $false
                # the newest change of a setting: its earlier value can be kept instead (once per setting, not one already kept)
                if ($x.Full -and -not $offered[$x.Full] -and -not $keeps.ContainsKey($x.Full)) {
                    $offered[$x.Full] = $true
                    $kb = New-Btn 'E7A7' "Keep $(if ($x.Old -eq '(not set)') { 'Windows'' default' } else { "'$($x.Old)'" }) for $(Get-PlainName $x.Full)" -Small { $f_, $o_ = $this.Uid -split "`t", 2; & $act.KeepValue $f_ $o_ }
                    $kb.Uid = "$($x.Full)`t$($x.Old)"; $kb.Margin = '0,2,0,4'; $kb.HorizontalAlignment = 'Left'; [void]$m.Add($kb)
                }
            }
            # settings the owner keeps their own way (Keep, above): said, with the way back
            foreach ($kf in @($names | Where-Object { $keeps.ContainsKey($_) })) {
                [void]$m.Add(@('Kept by you', "$(Get-PlainName $kf) stays at $(if ($keeps[$kf] -eq '(not set)') { 'Windows'' default' } else { "'$($keeps[$kf])'" })"))
                $mb_ = New-Btn 'E72C' "Let Messiah manage $(Get-PlainName $kf) again" -Small { & $act.ManageAgain $this.Uid }; $mb_.Uid = $kf; $mb_.HorizontalAlignment = 'Left'; [void]$m.Add($mb_)
            }
            if ($g) { $b = New-Btn 'E713' 'Change in Settings' -Small { Show-Page 'Settings' 'Windows' }; $b.Margin = '0,6,0,0'; $b.HorizontalAlignment = 'Left'; [void]$m.Add($b) }
            , $m.ToArray()
        }
        # title, the status keys (a switch, or "#<section>" of tweaks.ps1), the switch, what it does when it has no switch of
        # its own (or shares one), and what its history lines look like besides its settings
        $cat = [ordered]@{
            'Speed and games'     = @(
                @('Game Mode, hardware GPU scheduling, crash diagnostics', @('#Gaming / performance'), $null, 'Game Mode on and hardware-accelerated GPU scheduling; crash dumps kept and blue screens that name their cause; long file paths; bigger event logs; no motherboard "auto driver installer" (WPBT) and no device companion-app downloads; the page file managed by Windows.', 'page file'),
                @('Memory integrity (VBS) off', @('memory-integrity'), 'memory-integrity'),
                @('Background game recording off', @('game-recording'), 'game-recording'),
                @('Optimizations for windowed games and VRR', @('windowed-games'), 'windowed-games'),
                @('Mouse acceleration off', @('mouse-acceleration'), 'mouse-acceleration'),
                @('Sticky Keys pop-ups off', @('sticky-keys'), 'sticky-keys'),
                @('"End task" in the taskbar menu', @('end-task'), 'end-task'),
                @('Best power plan, USB sleep off', @('power-plan', 'hibernation', '#Power'), 'power-plan', $null, 'power plan|USB sleep|hibernation|processor at full'),
                @('No power-saving on controllers and network adapters', @('#Devices'), $null, 'Power-saving off on game controllers (Xbox, PlayStation, Nintendo, 8BitDo and more), the wired network adapter (Energy-Efficient / Green Ethernet) and, on a desktop, Wi-Fi - no input drops or lag spikes when they "wake up".', 'power-saving|ethernet'),
                @('Network at Windows'' defaults (no lag-adding tweaks)', @('network-defaults', '#Network'), 'network-defaults', $null, 'Nagle setting'))
            'Privacy and clutter' = @(
                @('Telemetry, ads, suggestions and Windows AI off', @('telemetry'), 'telemetry'),
                @('Unneeded services off', @('#Services'), $null, 'Diagnostic tracking, WAP push, the Windows AI fabric, Maps, location, link tracking, the compatibility assistant and the retail demo off; the scanner, phone and diagnostics services (and printing, without a real printer) start only when needed.', '^service '),
                @('Telemetry and feedback tasks off', @('#Scheduled tasks'), 'telemetry', 'Windows'' telemetry, feedback, compatibility-appraiser, usage-data and "sustainability" tasks off, plus Chrome''s "tips" task and motherboard installer tasks. A few are protected by Windows itself and stay as they are.', '^task |installer task'),
                @('All app notifications off', @('notifications-off'), 'notifications-off'),
                @('Start menu recommendations and Task View off', @('start-menu'), 'start-menu'),
                @('Preinstalled apps removed', @('#Preinstalled apps'), 'bloat-apps', $null, '^app '),
                @('OneDrive removed', @('onedrive', '#OneDrive'), 'onedrive', $null, 'OneDrive'),
                @('Edge kept out of the way', @('edge', '#Edge'), 'edge', $null, '^Edge (desktop|unpinned)'),
                @('Edge removed completely', @('edge-remove'), 'edge-remove', $null, '^Edge (removed|installed)'),
                @('Old Windows parts removed', @('#Old Windows parts'), 'legacy', $null, 'old Windows part|Windows feature|reserved storage'),
                @('Start-up clutter off', @('#Start-up clutter'), 'startup-clutter', 'Vendor updaters, promo tools and "assistants" don''t start with Windows, nor the helpers of hardware that is switched off (an unused integrated GPU''s, onboard audio''s). Turned off the Task Manager way - still installed. Off: they start again.', 'start-up item'),
                @('Razer and Logitech auto-installers blocked', @('#Vendor auto-installers'), 'vendor-installers', $null, 'auto-installer'),
                @('File Explorer doesn''t guess folder types', @('folder-types'), 'folder-types'),
                @('Transparency effects off', @('transparency'), 'transparency'),
                @('Windows keeps registry backups', @('#Registry backup'), $null, 'Windows saves copies of the registry again (it stopped in 2018) - a way back if a bad driver or update stops the PC from starting.'))
            'Windows Update'      = @(
                @('No update restarts while you''re signed in', @('restart-block'), 'restart-block'),
                @('Big Windows upgrades wait 45 days', @('feature-delay'), 'feature-delay'))
        }
        foreach ($g in $cat.Keys) {
            foreach ($o in $cat[$g]) { $s = & $rowState $o[1] $o[2]; & $addRow $g $o[0] $s[0] $s[1] $s[2] (& $moreOf $o[1] $o[2] $o[3] $o[4]) $(if ($s[0] -eq 'warn') { $checkNow }) }
        }
        # --- this PC: its own extras, crash-hunting modes, the NVIDIA settings, the monitors, the drivers, Messiah's own tasks
        $pcC = 'This PC'
        if ($gs -and $gs.hasLocal) {
            $gAt2 = $null; $tmp = [datetime]::MinValue; if ([datetime]::TryParse("$($gs.at)", [ref]$tmp)) { $gAt2 = $tmp }
            $ll = @($gs.local | Where-Object { $_ })
            & $addRow $pcC 'This PC''s own extras (unused devices off, power)' 'ok' $(if ($ll -and $gAt2) { "Put back $(Format-When $gAt2 -Short)" } else { 'In place' }) $(if ($ll) { ($ll | Select-Object -First 3) -join ', ' }) $(if ($Details) { , @(
                        @('What it does', 'Extras only this PC has (tweaks-local.ps1 next to Messiah''s scripts), checked and put back with everything else.'),
                        @('Last check', $(if ($gAt2) { "$(Format-When $gAt2) - $(if ($ll) { "put back: $($ll -join ', ')$(if ($gs.cause) { " (after $($gs.cause))" })" } else { 'all in place' })" } else { 'Not yet' }))) })
        }
        # crash-hunting modes (diag-modes.ps1): a real cost in games while on - amber from the start; once turned off they keep
        # running until the next restart (diag-state.json "<id>-off", kept by diag-modes.ps1)
        if (-not $env:PCKIT_IN_TESTS -or $env:PCKIT_DIAG_TEST) {
            $dms = @(Get-Cached 'diag' 60 { @(if (Test-Path "$cl\diag-modes.ps1") { & "$cl\diag-modes.ps1" }) })
            $dsj = Read-Json "$cl\diag-state.json"
            $boot = Get-Cached 'boot' 3600 { (Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue).LastBootUpTime }
            $offPending = @(if ($dsj) { $dsj.PSObject.Properties | Where-Object { $_.Name -like '*-off' } | ForEach-Object { $t_ = [datetime]::MinValue; if ([datetime]::TryParse("$($_.Value)", [ref]$t_) -and $boot -and $t_ -gt $boot) { $_.Name -replace '-off$', '' } } })
            $dmAbout = @('What it does', 'Modes for hunting crashes: Driver Verifier checks every call of the drivers it watches, kernel debugging and test signing change how Windows starts. Right while a crash is being tracked down - after that they cost frame rate and smoothness in every game. Messiah never turns one on or off by itself.')
            if ($dms) {
                $dm = $dms[0]
                $fix = switch ($dm.Id) { 'verifier' { @('E7E8', 'Turn off Driver Verifier', { & $act.DiagOff 'verifier' }) } 'debug' { @('E7E8', 'Turn off kernel debugging', { & $act.DiagOff 'debug' }) } default { @('E7E8', 'Turn off test signing', { & $act.DiagOff 'testsigning' }) } }
                & $addRow $pcC 'Crash-hunting modes off' 'warn' "$($dm.Name) on" "On for $($dm.Days) day$(if ($dm.Days -ne 1) { 's' }) (since $($dm.Since.ToString('MMM d'))) - it slows games; turn it off once the crash hunt is over$(if ($dms.Count -gt 1) { "; also: $((@($dms | Select-Object -Skip 1 | ForEach-Object Name)) -join ', ')" })" $(if ($Details) { , @($dmAbout, @('On now', (@($dms | ForEach-Object { "$($_.Name) - since $($_.Since.ToString('MMM d'))" }) -join '   |   ')), @('Turning it off', 'Takes effect at the next restart (Messiah never restarts the PC). If blue screens come back afterwards, the crash notes in Messiah still have what was found.')) }) $fix
            } elseif ($offPending) { & $addRow $pcC 'Crash-hunting modes off' 'ok' 'Off from the next restart' "$(($offPending | ForEach-Object { switch ($_) { 'verifier' { 'Driver Verifier' } 'debug' { 'Kernel debugging' } default { 'Test signing' } } }) -join ', ') switched off - still running until Windows restarts" $(if ($Details) { , @(, $dmAbout) }) }
            else { & $addRow $pcC 'Crash-hunting modes off' 'ok' 'Off' $null $(if ($Details) { , @(, $dmAbout) }) }
        }
        if (Test-Path "$cl\nvidia-settings.txt") {
            $nvFor = "$(Get-Content "$cl\nvidia-settings.txt" -TotalCount 1 -ErrorAction SilentlyContinue)".Trim()
            $gpuNow = "$((Read-Json "$cl\gpu-state.json").driver)".Trim()
            $nvMore = if ($Details) { , @(@('What it does', 'Low latency mode "On" (one pre-rendered frame: less input lag - games with NVIDIA Reflex use their own) and an unlimited shader cache (games don''t recompile shaders and stutter because an old 4 GB cache filled up), on the driver''s global profile. Every other NVIDIA setting stays yours.'),
                    @('Driver', "Set for $(if ($nvFor) { $nvFor } else { '-' })$(if ($gpuNow) { "; installed now: $gpuNow" }) - read back from the driver at every pass and set again after driver updates"),
                    (New-Btn 'E713' 'Change in Settings' -Small { Show-Page 'Settings' 'General' })) }
            $nvT = 'NVIDIA low latency and unlimited shader cache'
            if ((Get-Opt 'nvidiasettings' 'on') -eq 'off') { & $addRow $pcC $nvT 'dim' 'Off - your choice' $null $nvMore }
            elseif ($gpuNow -and $nvFor -ne $gpuNow) { & $addRow $pcC $nvT 'warn' 'New driver - set at the next check' "Last set for driver $nvFor" $nvMore @('E72C', 'Set it now', { & $act.CheckNow }) }
            else { & $addRow $pcC $nvT 'ok' 'In place' "Driver $nvFor - checked at every pass" $nvMore }
        }
        $rep = @(Get-Content "$cl\maint-report.txt" -Encoding UTF8 -ErrorAction SilentlyContinue)
        if ($rep) {
            $mon = @($rep | Where-Object { $_ -match '^(Reminder|WARNING):.*(Hz|refresh rate|resolution)' })
            # (the modes right now: read live - each graphics card with a screen on it)
            $modes = if ($Details -and -not $env:PCKIT_IN_TESTS) { @(Get-Cached 'modes' 60 { @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object { $_.CurrentRefreshRate -gt 1 -and $_.Status -eq 'OK' } | ForEach-Object { "$($_.Name): $($_.CurrentHorizontalResolution) x $($_.CurrentVerticalResolution) at $($_.CurrentRefreshRate) Hz" }) }) }
            $monMore = if ($Details) { , @(@(, @('What it does', 'Each monitor at its native resolution and the highest refresh rate it supports - set by itself once per monitor, also for one plugged in later; a cable or port that can''t carry the full rate is said.')) + @(if ($modes) { , @('Right now', ($modes -join '   |   ')) }) + @(if ($mon) { , @('Found', ($mon -join '   |   ')) })) }
            & $addRow $pcC 'Monitors at their best resolution and refresh rate' $(if ($mon) { 'warn' } else { 'ok' }) $(if ($mon) { 'Needs a look' } else { 'In place' }) $(if ($mon) { ($mon[0] -replace '^(Reminder|WARNING):\s*', '') }) $monMore $(if ($mon) { @('E7F4', 'Display settings', { Start-Process 'ms-settings:display' }) })
            $i = [array]::IndexOf($rep, '[Drivers]'); $dl = @(if ($i -ge 0) { $rep[($i + 1)..($rep.Count - 1)] | ForEach-Object -Begin { $go = $true } -Process { if ($_ -match '^\[') { $go = $false }; if ($go -and $_.Trim()) { $_.Trim() } } })
            if ($dl) {
                $bad = @($dl | Where-Object { $_ -match 'FAILED|WARNING|could not' })
                & $addRow $pcC 'Drivers up to date' $(if ($bad) { 'warn' } else { 'ok' }) $(if ($bad) { 'Needs a look' } else { 'Up to date' }) $(if ($bad) { $bad[0] } else { ($dl | Select-Object -First 1) }) $(if ($Details) { , @(
                            @('What it does', 'The graphics driver from its maker (checked against the NVIDIA app; AMD Radeon too), everything else from Windows Update - installed by itself, never while you play, with a restore point first. A driver that keeps failing is hidden; one that crashes the PC is rolled back.'),
                            @('Last check', ($dl -join '   |   '))) }) $(if ($bad) { @('E768', 'Run maintenance now', { & $act.RunMaint }) })
            }
        }
        if (-not $env:PCKIT_IN_TESTS) {
            $kt = 'Claude Background Maintenance', 'PC Setup Kit Update Guard', 'PC Setup Kit Update Check', 'Messiah Tray'
            $tk = @(Get-Cached 'tasks' 60 { @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -in $kt } | ForEach-Object {
                            $lr = @($_ | Get-ScheduledTaskInfo -ErrorAction SilentlyContinue | ForEach-Object { $_.LastRunTime } | Where-Object { $_ -and $_.Year -gt 2000 } | Sort-Object -Descending) | Select-Object -First 1
                            [pscustomobject]@{ TaskName = $_.TaskName; State = "$($_.State)"; LastRun = $lr } }) })
            if ($tk) {
                $badT = @($kt | Where-Object { $n_ = $_; -not ($tk | Where-Object { $_.TaskName -eq $n_ -and $_.State -ne 'Disabled' }) })
                $tkMore = if ($Details) { , (@(, @('What it does', 'The scheduled tasks that keep all of this going: the maintenance at login, the check every 4 hours, the guard 2 minutes after each Windows or driver update, and the tray. Each one switches the others back on if something turns it off.')) +
                        @($tk | ForEach-Object { , @($_.TaskName, "$(if ($_.State -eq 'Disabled') { 'switched off' } else { $_.State.ToLower() })$(if ($_.LastRun) { " - last ran $(Format-When $_.LastRun)" })") })) }
                & $addRow $pcC 'Messiah''s own checks scheduled (login, every 4 hours, after updates)' $(if ($badT) { 'warn' } else { 'ok' }) $(if ($badT) { 'Switched off' } else { 'On' }) $(if ($badT) { "$($badT -join ', ') - turned back on at the next maintenance" }) $tkMore $(if ($badT) { @('E768', 'Switch them back on', { & $act.RunMaint }) })
            }
        }
        # a check the owner started (Check now): running until the guard's next status, 3 minutes at most
        $checking = $script:checkingSince -and (-not $tsAt -or $tsAt -lt $script:checkingSince) -and $script:checkingSince -gt (Get-Date).AddMinutes(-3)
        @{ At = $tsAt; Preview = [bool]($ts -and $ts.preview); Cause = $cause; Rows = $rows.ToArray(); Checking = $checking
            Warn = @($rows | Where-Object { $_.Level -eq 'warn' }).Count; Ok = @($rows | Where-Object { $_.Level -eq 'ok' }).Count
            Stale = (-not $tsAt -or $tsAt -lt (Get-Date).AddDays(-2)) }
    }
    # one line of the Status tab: a status dot, the optimization, what the last check found on the right (and a line under it).
    # -More: a click opens the details under it (what it does, what it checks, when it was last put back) - a chevron says
    # so; what's open stays open when the page redraws ($script:openRows, by title)
    # (which rows were open last time: app-last.txt, written when the window closes - see Save-AppLast)
    if (-not $script:openRows) { $script:openRows = @{}; if (-not $Test) { foreach ($t_ in @("$((Get-Content "$cl\app-last.txt" -ErrorAction SilentlyContinue) -match '^open=' -replace '^open=', '')" -split '\|' | Where-Object { $_ })) { $script:openRows[$t_] = $true } } }
    # the Status tab's filter and search (Set-StatusFilter: rows and cards hidden in place)
    function Set-StatusFilter {
        $f = "$script:stFilter"; $q = "$script:stSearch".Trim()
        foreach ($r in @($script:stRows)) {
            $show = switch ($f) { 'warn' { $r.Level -eq 'warn' } 'back' { $r.State -like 'Put back*' } 'off' { $r.Level -eq 'dim' } default { $true } }
            if ($show -and $q) { $show = $r.Text.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0 }
            $r.El.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }
        }
        foreach ($g in @($script:stCardEls.Keys)) { $script:stCardEls[$g].Visibility = if (@($script:stRows | Where-Object { $_.Card -eq $g -and $_.El.Visibility -eq 'Visible' }).Count) { 'Visible' } else { 'Collapsed' } }
        if ($script:stEmpty) { $script:stEmpty.Visibility = if (@($script:stRows | Where-Object { $_.El.Visibility -eq 'Visible' }).Count) { 'Collapsed' } else { 'Visible' } }
    }
    # a Status row's details open or closed (a click, or Enter / Space) - remembered for the next redraw and the next start
    function Switch-StatusRow($r) {
        $t = $r.Tag; $show = $t.More.Visibility -ne 'Visible'
        $t.More.Visibility = if ($show) { 'Visible' } else { 'Collapsed' }; $t.Chev.Text = [string][char]$(if ($show) { 0xE70E } else { 0xE70D })
        $script:openRows[$t.Title] = $show; Save-AppLast
    }
    # -Fix: @(glyph, label, action) - a row that needs a look gets its button right under it
    function New-StatusRow($title, $state, $detail, $level, $More, $Fix) {
        $r = New-Object Windows.Controls.DockPanel -Property @{ Margin = '-8,1,-8,1'; Background = [Windows.Media.Brushes]::Transparent }
        $dot = New-Object Windows.Shapes.Ellipse -Property @{ Width = 10; Height = 10; Fill = $levelBrush[$level]; VerticalAlignment = 'Top'; Margin = '8,10,14,0' }
        [Windows.Controls.DockPanel]::SetDock($dot, 'Left'); [void]$r.Children.Add($dot)
        $chev = $null
        if ($More) { $chev = New-Glyph 'E70D' 10 $brush.Sub; $chev.VerticalAlignment = 'Top'; $chev.Margin = '12,8,8,0'; [Windows.Controls.DockPanel]::SetDock($chev, 'Right'); [void]$r.Children.Add($chev) }
        $st = New-Text $state $(if ($level -eq 'warn') { $brush.Warn } else { $brush.Sub }) 13 'Normal' $(if ($More) { '16,5,0,0' } else { '16,5,8,0' }); $st.TextWrapping = 'NoWrap'; $st.VerticalAlignment = 'Top'
        [Windows.Controls.DockPanel]::SetDock($st, 'Right'); [void]$r.Children.Add($st)
        $l = New-Object Windows.Controls.StackPanel -Property @{ Margin = '0,4,0,4' }
        [void]$l.Children.Add((New-Text $title $(if ($level -eq 'dim') { $brush.Sub } else { $brush.Text }) 14 'Normal' '0'))
        if ($detail) { [void]$l.Children.Add((New-Text $detail $brush.Sub 12 'Normal' '0,1,0,0')) }
        if ($Fix) {
            $fp = New-Object Windows.Controls.WrapPanel -Property @{ Margin = '0,6,0,0' }
            [void]$fp.Children.Add((New-Btn $Fix[0] $Fix[1] $Fix[2] -Small))
            $fp.Add_MouseLeftButtonUp({ $_.Handled = $true })   # (a click beside the button doesn't open the details)
            [void]$l.Children.Add($fp)
        }
        if ($More) {
            # the details: a faint panel with a line on its left, out of the way until asked for
            $mb = New-Object Windows.Controls.Border -Property @{ Tag = 'more'; BorderBrush = $brush.Divider; BorderThickness = '2,0,0,0'; Padding = '12,2,0,2'; Margin = '0,8,0,4'; Cursor = 'Arrow' }
            $mp = New-Object Windows.Controls.StackPanel
            foreach ($m in @($More)) {
                if ($m -is [Windows.UIElement]) { [void]$mp.Children.Add($m); continue }
                if ($m -is [array]) { $t_ = New-Text '' $brush.Sub 12 'Normal' '0,2,0,2'; [void]$t_.Inlines.Add((New-Object Windows.Documents.Run -ArgumentList "$($m[0])  " -Property @{ Foreground = $brush.Text; FontWeight = 'SemiBold' })); [void]$t_.Inlines.Add((New-Object Windows.Documents.Run -ArgumentList "$($m[1])")); [void]$mp.Children.Add($t_) }
                else { [void]$mp.Children.Add((New-Text "$m" $brush.Sub 12 'Normal' '0,2,0,2')) }
            }
            $mb.Child = $mp
            $open = [bool]$script:openRows[$title]
            $mb.Visibility = if ($open) { 'Visible' } else { 'Collapsed' }; if ($open) { $chev.Text = [string][char]0xE70E }
            $mb.Add_MouseLeftButtonUp({ $_.Handled = $true })   # (selecting in the details doesn't close them)
            [void]$l.Children.Add($mb)
            $r.Cursor = 'Hand'; $r.ToolTip = 'Details'
            # the keyboard too: Tab reaches the row, Enter or Space opens its details (a faint highlight shows where focus is)
            $r.Focusable = $true; [Windows.Input.KeyboardNavigation]::SetIsTabStop($r, $true); $r.FocusVisualStyle = $null
            [Windows.Automation.AutomationProperties]::SetName($r, "$title - $state"); [Windows.Automation.AutomationProperties]::SetHelpText($r, 'Press Enter for details')
            $r.Add_GotKeyboardFocus({ $this.Background = $brush.CardHover }); $r.Add_LostKeyboardFocus({ $this.Background = [Windows.Media.Brushes]::Transparent })
            $r.Add_KeyDown({ param($s_, $e_) if ($e_.Key -in 'Return', 'Space' -and $e_.OriginalSource -eq $s_) { Switch-StatusRow $s_; $e_.Handled = $true } })
            $r.Tag = @{ More = $mb; Chev = $chev; Title = $title }
            $r.Add_MouseEnter({ $this.Background = $brush.CardHover }); $r.Add_MouseLeave({ $this.Background = [Windows.Media.Brushes]::Transparent })
            $r.Add_MouseLeftButtonUp({ Switch-StatusRow $this })
        }
        [void]$r.Children.Add($l); $r
    }

    # --- Trends: health over time (health-history.json, written by trends.ps1 at every check). One measure per chart,
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
        $W = 330; $H = 84; $lo = ($vals | Measure-Object -Minimum).Minimum; $hi = ($vals | Measure-Object -Maximum).Maximum
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

    # --- settings (kit-options.txt next to the scripts; the tray reads "openatlogin" and "cornernotes")
    # where the window was: the page (tab/sub-page) and the Status rows left open - it opens there next time (app-last.txt,
    # not kit-options.txt: a change there redraws the page)
    function Save-AppLast { try { [IO.File]::WriteAllLines("$cl\app-last.txt", [string[]]@("page=$(Get-PageKey)", "open=$((@($script:openRows.Keys | Where-Object { $script:openRows[$_] })) -join '|')", "chattab=$(if ($script:chatDir -and $script:chatDir -ne "$cl\chat") { Split-Path $script:chatDir -Leaf })", "chatzoom=$script:chatZoom")) } catch { } }
    function Get-AppLast($k) { "$((@(Get-Content "$cl\app-last.txt" -ErrorAction SilentlyContinue) -match "^$k=" | Select-Object -First 1) -replace "^$k=", '')".Trim() }
    # --- the RAM stick test (/maintain starts it - 'ram-stick-test' in maint-state.json, 60 days; health-check.ps1 logs
    # every start and crash to ram-test.log with the sticks fitted). The sticks have no serial numbers here, so a stick
    # is known by its slot: the first stick is tested in slot A, the other one in slot B.
    $ramNeed = 10   # starts without a crash before a stick counts as fine (with both in, about 1 start in 4 crashed)
    function Get-RamTest([string[]]$log, [string]$now) {
        $g = [ordered]@{}
        foreach ($l in $log) {
            if ($l -notmatch '^(\S+ \S+) \| (start|crash) \| (.+)$') { continue }
            $s = $Matches[3].Trim(); if (-not $g.Contains($s)) { $g[$s] = @{ Starts = 0; Crashes = 0; Since = $Matches[1] } }
            if ($Matches[2] -eq 'start') { $g[$s].Starts++ } else { $g[$s].Crashes++ }
        }
        $slot = { param($s) if ($s -match 'CHANNEL ([A-Z])\s*$') { $Matches[1] } elseif ($s -match ' in (.+)$') { $Matches[1] } else { '?' } }
        $one = @{}; foreach ($k in $g.Keys) { if ($k -like '1 stick(s)*') { $one[(& $slot $k)] = $g[$k] } }
        $both = $g.Keys | Where-Object { $_ -like '2 stick(s)*' } | Select-Object -First 1
        $L = New-Object Collections.Generic.List[object]
        $say = { param($t, $lv = 'info') $L.Add(@{ Text = $t; Level = $lv }) }
        if ($both) { $b = $g[$both]; & $say "With both sticks in: $($b.Starts) start$(if ($b.Starts -ne 1) { 's' }), $($b.Crashes) blue screen$(if ($b.Crashes -ne 1) { 's' }) or sudden restart$(if ($b.Crashes -ne 1) { 's' }) (counted since $(Format-When ([datetime]$b.Since) -DateOnly))." 'dim' }
        foreach ($k in 'A', 'B') { if ($one[$k]) { & $say "Only the stick in slot ${k}: $($one[$k].Starts) start$(if ($one[$k].Starts -ne 1) { 's' }), $($one[$k].Crashes) crash$(if ($one[$k].Crashes -ne 1) { 'es' })." $(if ($one[$k].Crashes) { 'warn' } else { 'dim' }) } }
        $done = { param($r) $r -and ($r.Crashes -or $r.Starts -ge $ramNeed) }
        $bad = { param($r) $r -and $r.Crashes }
        $shut = 'shut the PC down (Start > Power > Shut down) and unplug it, then'
        if ((& $done $one['A']) -and (& $done $one['B'])) {   # both tested: the answer
            if ((& $bad $one['A']) -and -not (& $bad $one['B'])) { & $say 'Result: the stick from slot A is faulty - the other one ran clean on its own. Keep using the good stick (16 GB is plenty for games) and get the faulty one replaced under Corsair''s lifetime warranty (corsair.com > Support > RMA; they usually replace the pair). To be extra sure it''s the stick and not the slot: put the faulty stick in slot B - if it crashes there too, it''s the stick.' 'warn' }
            elseif ((& $bad $one['B']) -and -not (& $bad $one['A'])) { & $say 'Result: the stick tested in slot B is faulty - the other one ran clean on its own. Keep using the good stick (16 GB is plenty for games) and get the faulty one replaced under Corsair''s lifetime warranty (corsair.com > Support > RMA; they usually replace the pair). To be extra sure it''s the stick and not the slot: put the faulty stick in slot A - if it crashes there too, it''s the stick.' 'warn' }
            elseif ((& $bad $one['A']) -and (& $bad $one['B'])) { & $say 'Result: both sticks crashed on their own, so the sticks are most likely fine - the processor''s memory controller or the motherboard is the likely cause. That''s a warranty case for AMD or ASRock; Claude can help you with it.' 'warn' }
            else { & $say "Result: neither stick crashed on its own ($ramNeed+ starts each). The fault may only show with both sticks in, or be rarer than the test caught. Put both sticks back in; Claude can help with the next step." 'info' }
        } elseif ($now -like '1 stick(s)*') {
            $k = & $slot $now; $r = $one[$k]; $other = if ($k -eq 'A') { 'B' } else { 'A' }
            if (& $done $r) {
                & $say "Next: $shut take this stick out and put the OTHER stick in slot $other on its own. $(if (& $bad $r) { 'This stick crashed on its own - the other one will show whether it''s the stick.' } else { "This stick ran $($r.Starts) starts without a crash, so it looks fine." })" 'warn'
            } else {
                $n = if ($r) { $r.Starts } else { 0 }
                & $say "Now: just use the PC as usual with this stick - $($ramNeed - $n) more start$(if ($ramNeed - $n -ne 1) { 's' }) to go. Messiah counts them by itself." 'ok'
            }
        } elseif (-not $one.Count) {
            & $say "Step 1 of 2: $shut take out the stick in slot B (the slot marked B on the motherboard, e.g. DDR5_B1) and leave the other one where it is. Then use the PC as usual for about $ramNeed starts; Messiah counts them and the crashes by itself. Leave EXPO off during the test." 'warn'
        } else {
            $t = if ($one['A']) { 'B' } else { 'A' }
            & $say "Both sticks are back in, but the test isn't finished: $shut put only the stick you haven't tested yet in slot $t." 'warn'
        }
        $L
    }
    function Get-RamTestNow {
        $st = Read-Json "$cl\maint-state.json"; $since = [datetime]::MinValue
        if (-not $st -or -not [datetime]::TryParse("$($st.'ram-stick-test')", [ref]$since) -or $since -lt (Get-Date).AddDays(-60)) { return }
        $sticks = @(Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue)
        $now = "$($sticks.Count) stick(s), $([math]::Round(($sticks | Measure-Object Capacity -Sum).Sum / 1GB)) GB in $(@($sticks | ForEach-Object { "$($_.BankLabel)".Trim() }) -join ' + ')"   # (health-check.ps1's words)
        Get-RamTest @(Get-Content "$cl\ram-test.log" -ErrorAction SilentlyContinue) $now
    }
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

    # --- pages: three tabs, two of them with sub-pages (the pills on the right of the page title)
    # (Welcome: after a new install, until "Got it" - Get-Pages again when that changes)
    function Get-Pages {
        $p = [ordered]@{}
        if ((Get-Opt 'welcome' '') -eq 'pending' -or ($Page -eq 'Welcome' -and -not $script:welcomeDone)) { $p.Welcome = 'E8E1' }
        $p.Home = 'E80F'; $p.Status = 'EA18'; $p.Activity = 'E81C'; $p.Settings = 'E713'
        $p
    }
    $subPages = @{ Activity = @('Checks', 'Trends', 'Alerts'); Settings = @('General', 'Windows', 'Tools') }
    $subs = @{ Welcome = 'Your PC is set up. Here is what happened and what happens from now on.'
        Status = 'Every optimization Messiah keeps in place on this PC - and whether it still is.'
        'Activity/Checks' = 'What the maintenance found, what it did, and when it runs next.'; 'Activity/Trends' = 'How this PC has been doing over time.'
        'Activity/Alerts' = 'What Messiah had to say - kept here instead of popping up.'
        'Settings/General' = 'Everything Messiah does is yours to switch on or off.'; 'Settings/Windows' = 'Each change Messiah makes in Windows - keep it or not.'
        'Settings/Tools' = 'Updates, repairs, drivers, the BIOS and the install USB.' }
    # older names (the tray, links in reports) still open the right place
    $oldPages = @{ Overview = 'Home'; Sessions = 'Home'; Maintenance = 'Activity/Checks'; Schedule = 'Activity/Checks'; History = 'Activity/Trends'; Notifications = 'Activity/Alerts' }
    $script:sub = @{ Activity = 'Checks'; Settings = 'General' }

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
                            @{ Text = "- It works quietly from the hidden tray (^ next to the clock) and never pops up. Ctrl+Alt+M opens this window; Home says when something needs you."; Level = 'info' }) $null))
                $opt = @()
                if (-not $ai) { $opt += New-Btn 'E99A' 'Switch on the AI assistant' { [void](& $act.AiOn) } }
                $opt += New-Btn 'E771' 'Review what Messiah changes' { Show-Page 'Settings' 'Windows' }
                $opt += New-Btn 'E88E' 'Make an install USB' $act.MakeUsb
                [void]$out.Add((New-Card 'Optional' 'E734' @(@{ Text = 'None of this is needed. The AI assistant (Claude, with your own account) can look after the PC with you; an install USB sets up another PC - or this one again - the same way.'; Level = 'dim' }) $opt))
            }
            'Home' {
                $todo = @($needs.Lines | Where-Object Level -eq 'warn'); $warn = @($last.Lines | Where-Object Level -eq 'warn')
                $sm = Get-StatusModel   # (the Status tab's rows: an optimization that needs a look counts here too - one status, not two)
                $state = if ($todo) { 'warn', "$($todo.Count)", "$($todo.Count) thing$(if ($todo.Count -ne 1) { 's' }) need$(if ($todo.Count -eq 1) { 's' }) you" }
                elseif ($warn) { 'warn', 'E9F5', 'The last check found something - it is being handled' }
                elseif ($sm.Warn) { 'warn', "$($sm.Warn)", "$($sm.Warn) optimization$(if ($sm.Warn -ne 1) { 's' }) need$(if ($sm.Warn -eq 1) { 's' }) a look" }
                else { 'ok', 'E73E', 'All good - nothing needs you' }
                $when = $last.Lines | Where-Object { $_.Text -match '^(Checked|No report)' } | Select-Object -First 1
                # the status at one glance: a ring in the status color (the number of things that need the owner, or a
                # check mark), one sentence, when it was last checked - and the main actions under it
                $hero = New-Object Windows.Controls.Grid
                [void]$hero.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' }))
                [void]$hero.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
                $ring = New-Object Windows.Controls.Grid -Property @{ Width = 96; Height = 96; Margin = '0,0,24,0'; VerticalAlignment = 'Center' }
                $sb_ = $levelBrush[$state[0]]
                [void]$ring.Children.Add((New-Object Windows.Shapes.Ellipse -Property @{ Fill = (New-Tint $sb_ 0x1F) }))
                [void]$ring.Children.Add((New-Object Windows.Shapes.Ellipse -Property @{ Stroke = $sb_; StrokeThickness = 5 }))
                $mid = if ($state[1] -match '^\d+$') { $t_ = New-Text $state[1] $sb_ 34 'SemiBold' '0'; $t_.FontFamily = $display; $t_.Tag = 'icon'; $t_ } else { New-Glyph $state[1] 34 $sb_ }   # (Tag icon: the tests read the sentence, not the ring)
                $mid.HorizontalAlignment = 'Center'; $mid.VerticalAlignment = 'Center'; [void]$ring.Children.Add($mid)
                $txt = New-Object Windows.Controls.StackPanel -Property @{ VerticalAlignment = 'Center' }
                $ht = New-Text $state[2] $brush.Text 26 'SemiBold' '0'; $ht.FontFamily = $display; [void]$txt.Children.Add($ht)
                $whenAt = if ($when -and $when.Text -match '^Checked (.+?)( in |$)') { $d = [datetime]::MinValue; if ([datetime]::TryParse($Matches[1], [ref]$d)) { $d } }
                [void]$txt.Children.Add((New-Text "$(if ($whenAt) { "Last check $(Format-When $whenAt)" } elseif ($when) { $when.Text } else { 'No check yet - the first one runs a few minutes after login' })$(if ($v = ("$(Get-Content 'C:\PCSetupKit\kit-version.txt' -TotalCount 1 -ErrorAction SilentlyContinue)").Trim()) { "  $([char]0xB7)  Messiah $v, updates by itself" })" $brush.Sub 13 'Normal' '0,4,0,0'))
                [Windows.Controls.Grid]::SetColumn($txt, 1); [void]$hero.Children.Add($ring); [void]$hero.Children.Add($txt)
                $heroBtns = @(@(if ($sm.Warn -and -not $todo -and -not $warn) { New-Btn 'EA18' 'Open Status' { Show-Page 'Status' } -Accent }) + @((New-Btn 'E768' 'Run maintenance now' $act.RunMaint -Accent:(-not ($sm.Warn -and -not $todo -and -not $warn))), (New-Btn 'E945' 'Optimize this PC' $act.Optimize)))
                $hc = New-Card $null $null @($hero) $heroBtns; $hc.Padding = '26,24'; [void]$out.Add($hc)
                # playing right now (game-check.ps1): everything heavy waits - said, so a quiet Messiah isn't a broken one
                $game = Get-Playing
                if ($game) { [void]$out.Add((New-Card "Playing $game" 'E7FC' @(@{ Text = 'Updates, checks and cleanup wait until you''re done - nothing runs that could slow the game or take over the screen. They catch up by themselves afterwards.'; Level = 'info' }) $null)) }
                # what's new after an update (whats-new.json from kit-update.ps1): until "Got it", three weeks at most
                $wn = Get-WhatsNew
                if ($wn) {
                    $pts = @($wn.points | Where-Object { $_ } | Select-Object -First 6 | ForEach-Object { @{ Text = "- $_"; Level = 'info' } })
                    if (-not $pts) { $pts = @(@{ Text = 'Small fixes and improvements.'; Level = 'info' }) }
                    $gb = New-Btn 'E73E' 'Got it' { Set-Opt 'newsseen' $this.Uid; Update-View -Force } -Accent; $gb.Uid = "$($wn.version)"
                    $nb = @($gb) + @(if ($wn.url) { $b_ = New-Btn 'E774' 'All release notes' { Start-Process $this.Uid }; $b_.Uid = "$($wn.url)"; $b_ })
                    [void]$out.Add((New-Card "What's new in Messiah $($wn.version)" 'E789' $pts $nb))
                }
                $pz = if (Test-Path "$cl\paused.ps1") { & "$cl\paused.ps1" }
                if ($pz) { [void]$out.Add((New-Card 'Maintenance paused' 'E769' @(@{ Text = "Until $($pz.ToString('ddd h:mm tt')) - updates, checks and cleanup wait (the tray's Pause maintenance)."; Level = 'warn' }) @(New-Btn 'E768' 'Resume now' { Set-Opt 'pause-until' ''; Say 'Maintenance runs again as usual.'; Update-View -Force }) -Calm)) }
                if ($todo) { [void]$out.Add((New-Card 'Needs you' 'E7BA' @(New-TodoLines $needs.Lines) $null -Calm)) }
                # the RAM stick test, while it runs: where the owner is in it and what to do next
                $rt = Get-RamTestNow
                if ($rt) { [void]$out.Add((New-Card 'RAM stick test' 'E950' $rt @(if ($script:ai) { New-Btn 'E99A' 'Ask Claude about it' { Show-Chat $true; Send-Chat 'Help me with the RAM stick test: where am I, and what do I do next?' } }) -Calm)) }
                # the tiles: the main facts at a glance, each a way into its page
                $tiles = New-Object Windows.Controls.Primitives.UniformGrid -Property @{ Columns = 4; Margin = '0,0,-12,2' }; $script:tileGrid = $tiles
                $lastPerf = Get-HealthHistory 'perf-history.json' | Select-Object -Last 1
                $hh1 = Get-HealthHistory | Select-Object -Last 1
                # Guarded: the Status tab's count (the same model) - how many optimizations are in place, how many need a look,
                # and when the guard last checked them (every 4 hours, at login and right after updates)
                $gs = Read-Json "$cl\guard-state.json"
                $nAll = $sm.Ok + $sm.Warn
                $guardOld = $sm.At -and $sm.Stale   # no pass in 2 days: something's wrong (it says so)
                $guardVal = if ($sm.Warn) { "$($sm.Warn) need$(if ($sm.Warn -eq 1) { 's' }) a look" } elseif ($sm.At) { "$($sm.Ok) of $nAll in place" } else { 'Ready' }
                $firstWarn = $sm.Rows | Where-Object { $_.Level -eq 'warn' } | Select-Object -First 1
                $guardSub = if ($firstWarn) { "$($firstWarn.State) - see Status" } elseif (-not $sm.At) { 'Checked every 4 hours' } elseif ($guardOld) { "Last checked $(Format-When $sm.At -Short) - it runs again soon" }
                    elseif ($gs -and [int]$gs.fixed -gt 0) { "$([int]$gs.fixed) put back $(Format-When $sm.At -Short)" } else { "Checked $(Format-When $sm.At -Short) - all in place" }
                if ($sm.Warn) { $guardOld = $true }   # (the tile in the warning color)
                # the next scheduled check (the first line of "Scheduled checks" with a time in it)
                $next = $sched.Lines | Where-Object { $_.Text -match '^([^:]+):\s+(.*)$' } | Select-Object -First 1
                $nextVal = if ($next -and $next.Text -match '^([^:]+):\s+(.*)$') { $Matches[1] } else { 'At login' }
                $nextSub = if ($next -and $next.Text -match '^([^:]+):\s+(.*)$') { Format-Line $Matches[2] } else { 'And every 4 hours' }
                $tileDefs = @(
                    @('EA18', 'Guarded', $guardVal, $guardSub, $(if ($guardOld) { 'warn' } else { 'info' }), 'Status'),
                    @('E7FC', 'Last game', $(if ($lastPerf) { "$([int]$lastPerf.fps) fps" } else { 'Nothing yet' }), $(if ($lastPerf) { "$($lastPerf.game), 1% low $([int]$lastPerf.low1) fps" } else { 'Measured while you play' }), 'info', 'Activity/Trends'),
                    @('EDA2', 'Free space on C:', $(if ($hh1 -and $null -ne $hh1.freeGB) { "$([int]$hh1.freeGB) GB" } else { '-' }), 'Cleaned up every week', $(if ($hh1 -and $null -ne $hh1.freeGB -and $hh1.freeGB -lt 30) { 'warn' } else { 'info' }), 'Activity/Trends'),
                    @('E787', 'Next', $nextVal, $nextSub, 'info', 'Activity/Checks'))
                foreach ($t in $tileDefs) { [void]$tiles.Children.Add((New-Tile @t)) }
                Update-Columns; [void]$out.Add($tiles)
                if (@($wait.Lines | Where-Object { $_.Text -notmatch '^Nothing' })) { [void]$out.Add((New-Card $wait.Title 'E777' $wait.Lines $null)) }
                if ($ai -and $mess) {
                    $n = @($mess.Lines | Where-Object { $_.Text -like 'Session*' }).Count
                    $line = @{ Text = $(if ($n) { "$n session$(if ($n -ne 1) { 's' }) running in the background - $($mess.Lines[0].Text)" } else { 'No session open - a hidden one starts by itself within a few minutes' }); Level = 'info' }
                    $cs = Get-ChatState
                    $line = @{ Text = $(if ($cs -and $cs.busy) { "Working right now$(if ($cs.step) { ": $($cs.step)" })" } elseif ($cs) { 'Ready - your conversation is kept, so you can pick up where you left off' } else { 'Chat with Claude right here - it can look at this PC and fix things, with admin rights' }); Level = 'info' }
                    [void]$out.Add((New-Card 'Claude' 'E99A' @($line, @{ Text = 'Your Claude account; what it does shows in the chat as it happens. Nothing runs in a terminal.'; Level = 'dim' }) @(New-Btn 'E8BD' 'Open chat' { Show-Chat $true } -Accent)))
                }
            }
            'Status' {
                # every optimization Messiah keeps in place (Get-StatusModel): the summary on top, then a card per group;
                # each row opens its details with a click, and one that needs a look has its fix-it button
                $sm = Get-StatusModel -Details
                if ($script:checkingSince -and -not $sm.Checking) {   # a check the owner started has finished (or given up)
                    Say $(if ($sm.At -and $sm.At -ge $script:checkingSince) { "Check finished - $(if ($sm.Warn) { "$($sm.Warn) need$(if ($sm.Warn -eq 1) { 's' }) a look" } else { 'everything is in place' })." } else { 'The check is taking longer than usual - this page updates by itself when it finishes.' })
                    $script:checkingSince = $null
                }
                $hl = if ($sm.Checking) { 'info', 'E895', 'Checking everything now...' } elseif (-not $sm.At) { 'dim', 'E9F5', 'Not checked yet' } elseif ($sm.Warn) { 'warn', "$($sm.Warn)", "$($sm.Warn) need$(if ($sm.Warn -eq 1) { 's' }) a look" } elseif ($sm.Stale) { 'warn', 'E9F5', 'Not checked lately' } else { 'ok', 'E73E', "All $($sm.Ok) in place" }
                $hero = New-Object Windows.Controls.Grid
                [void]$hero.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition -Property @{ Width = 'Auto' }))
                [void]$hero.ColumnDefinitions.Add((New-Object Windows.Controls.ColumnDefinition))
                $ring = New-Object Windows.Controls.Grid -Property @{ Width = 64; Height = 64; Margin = '0,0,20,0'; VerticalAlignment = 'Center' }
                $sb_ = if ($hl[0] -eq 'info') { $brush.Accent } else { $levelBrush[$hl[0]] }
                [void]$ring.Children.Add((New-Object Windows.Shapes.Ellipse -Property @{ Fill = (New-Tint $sb_ 0x1F) }))
                [void]$ring.Children.Add((New-Object Windows.Shapes.Ellipse -Property @{ Stroke = $sb_; StrokeThickness = 4 }))
                $mid = if ($hl[1] -match '^\d+$') { $t_ = New-Text $hl[1] $sb_ 24 'SemiBold' '0'; $t_.Tag = 'icon'; $t_ } else { New-Glyph $hl[1] 24 $sb_ }
                $mid.HorizontalAlignment = 'Center'; $mid.VerticalAlignment = 'Center'; [void]$ring.Children.Add($mid)
                if ($sm.Checking -and -not $Test) {   # (the sync arrows turn while it checks)
                    $rot = New-Object Windows.Media.RotateTransform; $mid.RenderTransformOrigin = '0.5,0.5'; $mid.RenderTransform = $rot
                    $rot.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, (New-Object Windows.Media.Animation.DoubleAnimation -Property @{ From = 0; To = 360; Duration = [TimeSpan]::FromSeconds(1.6); RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever }))
                }
                $txt = New-Object Windows.Controls.StackPanel -Property @{ VerticalAlignment = 'Center' }
                $ht = New-Text $hl[2] $brush.Text 22 'SemiBold' '0'; $ht.FontFamily = $display; [void]$txt.Children.Add($ht)
                $sub_ = if ($sm.Checking) { 'Settings, services, apps, the power plan, the NVIDIA profile and the monitors - this page updates by itself when it is done (usually under a minute).' }
                else { "$(if ($sm.At) { "Checked $(Format-When $sm.At)" } else { 'The first check runs a few minutes after login' }) $([char]0xB7) checked again at every login, every 4 hours and 2 minutes after each Windows or driver update - anything an update changes back is put back by itself. Click a row for details." }
                [void]$txt.Children.Add((New-Text $sub_ $brush.Sub 13 'Normal' '0,4,0,0'))
                [Windows.Controls.Grid]::SetColumn($txt, 1); [void]$hero.Children.Add($ring); [void]$hero.Children.Add($txt)
                $chk = New-Btn 'E72C' $(if ($sm.Checking) { 'Checking...' } else { 'Check now' }) { & $act.CheckNow } -Accent; $chk.IsEnabled = -not $sm.Checking
                $hc = New-Card $null $null @($hero) @($chk, (New-Btn 'E7B3' 'Preview changes' $act.PreviewTweaks), (New-Btn 'E713' 'Choose what Messiah changes' { Show-Page 'Settings' 'Windows' }), (New-Btn 'E8C8' 'Copy a report' $act.CopyReport)); $hc.Padding = '24,20'; [void]$out.Add($hc)
                # filters (All / Needs a look / Put back / Off, with counts) and a search box: rows are hidden in place, no redraw -
                # the choice and the text stay while the page refreshes
                $cnt = @{ all = $sm.Rows.Count; warn = @($sm.Rows | Where-Object Level -eq 'warn').Count; back = @($sm.Rows | Where-Object { $_.State -like 'Put back*' }).Count; off = @($sm.Rows | Where-Object Level -eq 'dim').Count }
                if (-not $script:stFilter) { $script:stFilter = 'all' }
                $fbar = New-Object Windows.Controls.DockPanel -Property @{ Margin = '0,0,0,14'; LastChildFill = $false }
                $seg = New-Object Windows.Controls.Border -Property @{ Background = $brush.Seg; CornerRadius = 8; Padding = '3'; VerticalAlignment = 'Center' }
                $pills = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
                foreach ($f_ in @(@('all', 'All'), @('warn', 'Needs a look'), @('back', 'Put back'), @('off', 'Off'))) {
                    $rb = New-Object Windows.Controls.RadioButton -Property @{ GroupName = 'stf'; Tag = $f_[0]; Content = "$($f_[1])  $($cnt[$f_[0]])"; IsChecked = ($script:stFilter -eq $f_[0]) }
                    $rb.Style = $win.FindResource('Pill'); [Windows.Automation.AutomationProperties]::SetName($rb, "Show: $($f_[1]), $($cnt[$f_[0]])")
                    $rb.Add_Checked({ $script:stFilter = $this.Tag; Set-StatusFilter }); [void]$pills.Children.Add($rb)
                }
                $seg.Child = $pills; [Windows.Controls.DockPanel]::SetDock($seg, 'Left'); [void]$fbar.Children.Add($seg)
                $sbx = New-Object Windows.Controls.Border -Property @{ Background = $brush.Seg; CornerRadius = 8; Padding = '10,0'; Width = 240; VerticalAlignment = 'Center'; Margin = '12,0,0,0' }
                $sg = New-Object Windows.Controls.Grid
                $shint = New-Text 'Search optimizations...' $brush.Sub 13 'Normal' '0,6,0,6'; $shint.IsHitTestVisible = $false
                $stb = New-Object Windows.Controls.TextBox -Property @{ Text = "$script:stSearch"; FontSize = 13; Background = [Windows.Media.Brushes]::Transparent; BorderThickness = 0; Foreground = $brush.Text; CaretBrush = $brush.Text; Padding = '0,6,0,6'; VerticalContentAlignment = 'Center' }
                [Windows.Automation.AutomationProperties]::SetName($stb, 'Search optimizations')
                $shint.Visibility = if ($stb.Text) { 'Collapsed' } else { 'Visible' }; $stb.Tag = $shint
                $stb.Add_TextChanged({ $script:stSearch = $this.Text; $this.Tag.Visibility = if ($this.Text) { 'Collapsed' } else { 'Visible' }; Set-StatusFilter })
                $stb.Add_PreviewKeyDown({ param($s_, $e_) if ($e_.Key -eq 'Escape' -and $s_.Text) { $s_.Text = ''; $e_.Handled = $true } })
                [void]$sg.Children.Add($shint); [void]$sg.Children.Add($stb); $sbx.Child = $sg
                [Windows.Controls.DockPanel]::SetDock($sbx, 'Right'); [void]$fbar.Children.Add($sbx)
                $fwrap = New-Object Windows.Controls.Border -Property @{ Tag = 'filters'; Child = $fbar }; [void]$out.Add($fwrap)
                $script:stRows = New-Object Collections.ArrayList; $script:stCardEls = [ordered]@{}
                foreach ($g in @($sm.Rows | ForEach-Object { $_.Card } | Select-Object -Unique)) {
                    $rs = @(foreach ($row in @($sm.Rows | Where-Object { $_.Card -eq $g })) {
                            $el = New-StatusRow $row.Title $row.State $row.Detail $row.Level $row.More $row.Fix
                            $words = "$($row.Title) $($row.State) $($row.Detail) $(@($row.More | Where-Object { $_ -is [array] } | ForEach-Object { $_ -join ' ' }) -join ' ')"
                            [void]$script:stRows.Add(@{ El = $el; Level = $row.Level; State = "$($row.State)"; Text = $words; Card = $g }); $el })
                    $cd = New-Card $g $(switch ($g) { 'Speed and games' { 'E945' } 'Privacy and clutter' { 'E72E' } 'This PC' { 'E7F4' } default { 'E895' } }) $rs $null
                    $script:stCardEls[$g] = $cd; [void]$out.Add($cd)
                }
                $script:stEmpty = New-Text 'Nothing matches - try another filter or search.' $brush.Sub 13 'Normal' '4,4,0,0'; [void]$out.Add($script:stEmpty)
                Set-StatusFilter
            }
            'Activity/Checks' {
                [void]$out.Add((New-Card 'Last background check' 'E9D9' $last.Lines @((New-Btn 'E768' 'Run maintenance now' $act.RunMaint -Accent), (New-Btn 'E8A5' 'Full report' $act.Report))))
                [void]$out.Add((New-Card 'Needs you' 'E7BA' @(New-TodoLines $needs.Lines) @(New-Btn 'E8A5' 'Open the to-do list' $act.Todo) -Calm))
                if ($ai -and $hidden) { [void]$out.Add((New-Card "Claude's own checks" 'E90F' (@($hidden.Lines | ForEach-Object { @{ Text = ($_.Text -replace '\(improve\)', '(looked for improvements)' -replace '\(maintain\)', '(maintenance)' -replace '^Self-improvement:', 'Improving Messiah:'); Level = $_.Level } }) + @(@{ Text = 'About 2 minutes after each login, Claude handles anything in the report that needs judgment, then looks for ways to make Messiah better (at most once a day).'; Level = 'dim' })) @((New-Btn 'E890' 'Watch live' $act.WatchLive), (New-Btn 'E8F1' 'Self-improvement journal' $act.Journal), (New-Btn 'E8B7' 'Run logs' $act.Logs)))) }
                $pairs = foreach ($l in $sched.Lines) {
                    if ($l.Text -match '^([^:]+):\s+(.*)$') { , @($Matches[1], $Matches[2], $l.Level) } else { , @('', $l.Text, $l.Level) }
                }
                [void]$out.Add((New-Card 'Scheduled checks' 'E787' @((New-Rows $pairs), @{ Text = 'Everything here runs by itself. Checks wait while a game is running, and anything that needs a restart finishes the next time you turn the PC off.'; Level = 'dim' }) $null))
                $tl = @(Get-MaintTimeline | Select-Object -First 40)
                $rows = if ($tl) { $tl | ForEach-Object { , @($_.When, $_.Text, 'info') } } else { , @('', 'Nothing changed yet - the checks found everything in order.', 'dim') }
                [void]$out.Add((New-Card 'What maintenance did' 'E90F' @(New-Rows $rows) $null))
            }
            'Activity/Trends' {
                $hh = Get-HealthHistory
                $pt = { param($field, [switch]$PerBoot)
                    $rows = @($hh | Where-Object { $null -ne $_.$field })
                    if ($PerBoot) { $rows = @($rows | Where-Object bootAt | Group-Object bootAt | ForEach-Object { $_.Group[-1] }); $rows | ForEach-Object { [pscustomobject]@{ D = [datetime]$_.bootAt; V = $_.$field } } }
                    else { $rows | ForEach-Object { [pscustomobject]@{ D = [datetime]$_.date; V = $_.$field } } } }
                $grid = New-Object Windows.Controls.Primitives.UniformGrid -Property @{ Columns = 2; Margin = '0,0,-14,0' }
                # games (game-perf.ps1, while playing): the most played game's frame rate, and the card's heat under load
                $perf = Get-HealthHistory 'perf-history.json'; $net = Get-HealthHistory 'net-history.json'
                $top = $perf | Group-Object game | Sort-Object Count -Descending | Select-Object -First 1
                $gp = { param($rows, $field) @($rows | Where-Object { $null -ne $_.$field } | ForEach-Object { [pscustomobject]@{ D = [datetime]$_.date; V = $_.$field } }) }
                $charts = @((New-Chart 'Start-up time' ' s' (& $pt boot -PerBoot) 1 10), (New-Chart 'Free space on C:' ' GB' (& $pt freeGB) 0 20),
                    (New-Chart 'Graphics card at idle' ' C' (& $pt gpuIdle) 0 10), (New-Chart 'SSD temperature' ' C' (& $pt ssdTemp) 0 10),
                    (New-Chart "Frame rate$(if ($top) { " - $($top.Name)" })" ' fps' (& $gp $(if ($top) { $top.Group }) fps) 0 20),
                    (New-Chart "1% low frame rate$(if ($top) { " - $($top.Name)" })" ' fps' (& $gp $(if ($top) { $top.Group }) low1) 0 20),
                    (New-Chart 'Graphics card while gaming' ' C' (& $gp $perf gpuTemp) 0 10), (New-Chart 'Internet ping' ' ms' (& $gp $net ping) 0 10))
                foreach ($ch in $charts) { $ch.Margin = '0,0,14,14'; [void]$grid.Children.Add($ch) }
                [void]$out.Add($grid)
                # each game: its latest sample next to its usual (the median of its samples)
                $games = @($perf | Group-Object game | Sort-Object { ($_.Group | Select-Object -Last 1).date } -Descending | ForEach-Object {
                        $l = $_.Group | Select-Object -Last 1; $u = Median @($_.Group | ForEach-Object { [double]$_.low1 })
                        , @(([datetime]$l.date).ToString('MMM d'), "$($_.Name): $([int]$l.fps) fps, 1% low $([int]$l.low1) fps (usual $([int]$u))$(if ($null -ne $l.gpuTemp) { ", card $($l.gpuTemp) C" }) - $($_.Count) sample(s)", 'info') })
                if (-not $games) { $games = , @('', 'Nothing recorded yet - a minute of each game is measured while you play (at most every 3 hours).', 'dim') }
                [void]$out.Add((New-Card 'Games' 'E7FC' @(New-Rows $games) $null))
                [void]$out.Add((New-Text 'Recorded at every check (at each login and once a day); games while you play. Idle temperatures are taken only while the graphics card is idle, so a game never skews them.' $brush.Sub 12 'Normal' '4,2,0,0'))
            }
            'Activity/Alerts' {
                $notes = @(Get-Notes | Sort-Object When -Descending | Select-Object -First 80)
                # a "Needs you" alert whose item is no longer on the to-do list was resolved, and anything over a week old is
                # earlier news: both move to a quieter card under the recent ones (10/11: notes about a long-settled memory
                # test still led the list a week later)
                $open = @($needs.Lines | Where-Object Level -eq 'warn' | ForEach-Object { ($_.Text -replace '^- ', '').Trim() })
                $isOpen = { param($t)
                    if ($t -notmatch '^Needs you[^:]*:\s*(.+?)(\s*/\s*\+ \d+ more)?$') { return $null }
                    $head = ($Matches[1].Trim() -replace '\s*\.\.\.$', ''); $k = $head.Substring(0, [Math]::Min(40, $head.Length))
                    [bool]($open | Where-Object { $_.StartsWith($k) }) }
                $recent = @(); $earlier = @()
                foreach ($n in $notes) {
                    $o_ = & $isOpen $n.Text
                    if ($o_ -eq $false) { $earlier += , @($n.When.ToString('ddd MMM d, h:mm tt'), "$($n.Text)  (resolved)", 'dim') }
                    elseif ($n.When -lt (Get-Date).AddDays(-7)) { $earlier += , @($n.When.ToString('ddd MMM d, h:mm tt'), $n.Text, 'dim') }
                    else { $recent += , @($n.When.ToString('ddd MMM d, h:mm tt'), $n.Text, 'info') }
                }
                $rows = if ($recent) { $recent } elseif ($notes) { , @('', 'Nothing new this week.', 'dim') } else { , @('', 'No alerts yet.', 'dim') }
                $clear = New-Btn 'E74D' 'Clear' { [IO.File]::WriteAllText("$cl\notifications.log", ''); $script:shown = $null; Update-View -Force }
                [void]$out.Add((New-Card 'Alerts' 'EA8F' @(New-Rows $rows) @(if ($notes) { $clear })))
                if ($earlier) { [void]$out.Add((New-Card 'Earlier and resolved' 'E81C' @(New-Rows @($earlier | Select-Object -First 30)) $null)) }
                [void]$out.Add((New-Text "Messiah never pops up by itself: what it has to say is kept here. Settings > General > Show alerts in the corner brings the small corner notes back." $brush.Sub 12 'Normal' '4,2,0,0'))
            }
            'Settings/General' {
                $aiRow = New-SwitchRow 'AI assistant (Claude)' $(if ($ai) { 'On: Messiah sessions (Claude Code with admin rights) with your Claude account, and Claude''s own maintenance checks. Off: its sessions close; Claude Code and your conversations stay.' } else { 'Sign in with your own Claude account (Claude Code comes with Claude''s Pro and Max plans) and Claude looks after the PC with you. Everything else works without it.' }) ([bool]$ai) {
                    if ($this.IsChecked) { if (-not (& $act.AiOn)) { $this.IsChecked = $false } } else { & $act.AiOff }
                }
                $openRow = New-SwitchRow "Open $name when I log in" "This window opens once per start-up (not while a game is fullscreen). Off: $name starts quietly in the hidden tray (^ next to the clock) and works on its own." ((Get-Opt 'openatlogin' 'off') -eq 'on') {
                    Set-Opt 'openatlogin' $(if ($this.IsChecked) { 'on' } else { 'off' }); Say "Saved - $(if ($this.IsChecked) { "this window opens at login" } else { "$name starts in the hidden tray at login" })."
                }
                # (the tray's Alert(): off by default - the owner's rule 10/10, nothing pops up by itself)
                $noteRow = New-SwitchRow 'Show alerts in the corner' 'A small note in the corner of the screen when something needs you or an update finished (never over a game). Off (default): nothing pops up - it waits on Home and under Activity > Alerts, and the tray icon''s tooltip counts what needs you.' ((Get-Opt 'cornernotes' 'off') -eq 'on') {
                    Set-Opt 'cornernotes' $(if ($this.IsChecked) { 'on' } else { 'off' }); Say "Saved - $(if ($this.IsChecked) { 'alerts show in the corner' } else { 'nothing pops up; alerts wait here' })."
                }
                # (restart-night.ps1: on by default, except on the PC the kit is made on)
                $nightRow = New-SwitchRow 'Restart at night to finish updates' 'When an update waits for a restart, the PC restarts between 3:30 and 5:30 AM - only if nobody has used it for an hour, no game is running and it is plugged in. A 5-minute warning first (the tray''s Cancel restart stops it). Off: updates finish whenever you restart.' ((Get-Opt 'nightrestart' $(if (Test-Path "$cl\publish-kit.ps1") { 'off' } else { 'on' })) -eq 'on') {
                    Set-Opt 'nightrestart' $(if ($this.IsChecked) { 'on' } else { 'off' }); Say "Saved - $(if ($this.IsChecked) { 'pending updates finish with a restart at night while the PC is unused' } else { 'updates finish whenever you restart' })."
                }
                [void]$out.Add((New-Card 'Start-up and alerts' 'E713' @($aiRow, $openRow, $noteRow, $nightRow) $null))
                # the Status tab's details: settings in plain words, or by their registry names (for whoever knows them)
                $techRow = New-SwitchRow 'Show technical names' 'In a Status row''s details, the settings by their registry names (AllowTelemetry, HwSchMode...) instead of in plain words. Off (default): plain words.' ((Get-Opt 'technames' 'off') -eq 'on') { Set-Opt 'technames' $(if ($this.IsChecked) { 'on' } else { 'off' }); Say 'Saved.' }
                [void]$out.Add((New-Card 'Display' 'E7F4' @($techRow) $null))
                # --- Gaming options (kit-options.txt; gaming-check.ps1 / nvidia-settings.ps1 apply them at the next check)
                $opts = foreach ($o in @(@('defenderexclusions', 'off', 'Microsoft Defender skips my game folders', 'Less stutter while games load and build their shaders. A small security trade-off: files in those folders are no longer scanned. Off by default.'),
                        @('nvidiasettings', 'on', 'NVIDIA driver settings for games', 'Low-latency mode on and an unlimited shader cache (less stutter), set in the driver for every game, and put back if anything resets them. Off: no longer applied (the driver keeps the last values until changed in the NVIDIA Control Panel).'),
                        @('autorollback', 'on', 'Undo a graphics driver that crashes', 'A new graphics driver that causes freezes or blue screens in its first two weeks - when the one before didn''t - is swapped back to the one before by itself, and held back until a newer version comes. Off: you get a warning with a one-click button instead.'))) {
                    New-SwitchRow $o[2] $o[3] ((Get-Opt $o[0] $o[1]) -eq 'on') { Set-Opt $this.Tag $(if ($this.IsChecked) { 'on' } else { 'off' }); Say 'Saved - applied at the next check (or click Run maintenance now).' } $o[0]
                }
                [void]$out.Add((New-Card 'Games' 'E7FC' @($opts) $null))
                # --- Backup
                $bks = @(@("$([Environment]::GetFolderPath('MyDocuments'))\PC Setup Kit Backup") + @(Get-PSDrive -PSProvider FileSystem | ForEach-Object { "$($_.Root)PC Setup Kit Backup" }) | Where-Object { Test-Path $_ } | ForEach-Object { Get-ChildItem "$_\*.zip" -ErrorAction SilentlyContinue } | Sort-Object LastWriteTime -Descending)
                $bl = @(if ($bks) { @(@{ Text = "Last backup: $($bks[0].LastWriteTime.ToString('ddd MMM d, h:mm tt')) in $(Split-Path $bks[0].FullName)"; Level = 'info' }) } else { @(@{ Text = 'No backup yet - the first one is made at the next weekly maintenance.'; Level = 'dim' }) })
                $bl += @{ Text = 'Weekly: wallpaper, dark mode, colours, taskbar, mouse, Start pins, game settings and Messiah''s memory. Reinstalling Windows with the install USB brings them back by itself; plug in the USB once in a while and a copy goes onto it too.'; Level = 'dim' }
                [void]$out.Add((New-Card 'Settings backup' 'E777' $bl @((New-Btn 'E777' 'Back up now' $act.BackupNow), (New-Btn 'E896' 'Restore from a backup...' $act.RestoreFrom))))
                # --- Game saves (game-saves.ps1, Ludusavi): off until turned on
                if (Test-Path "$cl\game-saves.ps1") {
                    $gsOn = (Get-Opt 'gamesaves' 'off') -eq 'on'; $gst = Read-Json "$cl\game-saves.json"; $gsAt = [datetime]::MinValue
                    $gl = @(New-SwitchRow 'Back up my game saves every day' 'Every game''s saves (Steam or not - Ludusavi knows 10,000+ games) go to Documents\Game Saves (Messiah), zipped, the last 3 copies of each. Never while you play. With a backup drive set up, they go there too.' $gsOn { Set-Opt 'gamesaves' $(if ($this.IsChecked) { 'on' } else { 'off' }); Say $(if ($this.IsChecked) { 'On - the first backup runs at the next check (or click Back up now).' } else { 'Off - the backups made so far stay.' }) } 'gamesaves')
                    if ($gst -and [datetime]::TryParse("$($gst.lastRun)", [ref]$gsAt)) { $gl += @{ Text = "Last backup $(Format-When $gsAt): $($gst.games) games$(if (@($gst.ignored).Count) { " ($(@($gst.ignored).Count) cache file(s) left out - not saves)" })"; Level = 'dim' } }
                    [void]$out.Add((New-Card 'Game saves' 'E7FC' $gl @((New-Btn 'E777' 'Back up now' { Start-Process powershell -WindowStyle Hidden -ArgumentList ((& $psArgs 'game-saves.ps1') + '-Run'); Say 'Backing up your game saves in the background - "Last backup" here updates when it''s done (under a minute).' }), (New-Btn 'E8B7' 'Open the backups' { $d_ = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'Game Saves (Messiah)'; if (Test-Path $d_) { Start-Process explorer.exe "`"$d_`"" } else { Say 'No backup yet - click Back up now.' } }), (New-Btn 'E896' 'Restore saves...' { $r_ = & "$cl\game-saves.ps1" -Restore; if ($r_) { Say $r_ } else { Say 'Ludusavi opens - choose Restore, pick the game, and it puts the saves back.' } }))))
                }
            }
            'Settings/Windows' {
                # every change the kit makes, each one the owner's to keep or not (tweaks.ps1 reads "tweak.<id>=off", puts
                # back what it had changed, and keeps to the choice after updates) - in groups
                $tw = Get-TweakCatalog
                [void]$out.Add((New-Card 'Preview' 'E7B3' @(@{ Text = 'See exactly what Messiah would change on this PC right now - each setting with its current and new value, what Windows refuses, and what is already in place. Nothing is changed.'; Level = 'dim' }) @(New-Btn 'E7B3' 'Preview changes' $act.PreviewTweaks)))
                foreach ($g in $tw.Keys) {
                    $rows2 = foreach ($o in $tw[$g]) {
                        # (a 4th item: the default - 'off' for opt-in changes such as removing Edge)
                        New-SwitchRow $o[1] $o[2] ((Get-Opt "tweak.$($o[0])" $(if ($o.Count -gt 3) { $o[3] } else { 'on' })) -ne 'off') {
                            Set-Opt "tweak.$($this.Tag)" $(if ($this.IsChecked) { 'on' } else { 'off' })
                            if (Send-Tray $cmd.ApplyTweaks) { Say 'Saved - applying it now (a few seconds; some changes need a restart).' } else { Say 'Saved - applied at the next check (or click Run maintenance now).' } } $o[0]
                    }
                    [void]$out.Add((New-Card $g $(switch ($g) { 'Speed and games' { 'E945' } 'Privacy and clutter' { 'E72E' } default { 'E895' } }) @($rows2) $null))
                }
            }
            'Settings/Tools' {
                $kvf = Get-Item 'C:\PCSetupKit\kit-version.txt' -ErrorAction SilentlyContinue
                $prev = Get-Content "$env:ProgramData\PCSetupKit\previous\version.txt" -TotalCount 1 -ErrorAction SilentlyContinue
                $kl = @(@{ Text = "$(if ($kvf) { "Version $((Get-Content $kvf.FullName -TotalCount 1).Trim()), since $($kvf.LastWriteTime.ToString('MMM d')). " })It updates itself (checks every 4 hours) and tests itself after each update."; Level = 'info' })
                if ($prev) { $kl += @{ Text = "The version before ($("$prev".Trim())) is kept: Undo goes back to it."; Level = 'dim' } }
                if ($ai -and $script:claudeVer) { $kl += @{ Text = "Claude Code $script:claudeVer - updates itself; an idle hidden session moves onto a new version by itself."; Level = 'dim' } }
                [void]$out.Add((New-Card 'Messiah updates' 'E895' $kl @((New-Btn 'E90F' 'Repair Messiah' $act.Repair), (New-Btn 'E7A7' 'Undo the last update' $act.Rollback))))
                # the graphics driver, with the one-click way back to the one before (gpu-rollback.ps1, through the tray)
                if (-not $script:gd -and -not $env:PCKIT_IN_TESTS) { $script:gd = Get-CimInstance Win32_PnPSignedDriver -Filter "DeviceClass='DISPLAY'" -ErrorAction SilentlyContinue | Where-Object { $_.InfName -match '^oem\d+\.inf$' } |
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
                $kv = Get-Content 'C:\PCSetupKit\kit-version.txt' -TotalCount 1 -ErrorAction SilentlyContinue
                [void]$out.Add((New-Card 'About' 'E946' @(
                            @{ Text = "$name$(if ($kv) { " $kv" })"; Level = 'info' },
                            @{ Text = 'Keeps this PC updated, tuned and checked by itself, and updates itself. Tips: Ctrl+Alt+M opens this window from anywhere; Ctrl+K searches everything in it.'; Level = 'dim' }) @(New-Btn 'E8F1' 'Take the tour' $act.Tour)))
                # help from someone else: what they need, on the clipboard (no names, paths or e-mail addresses)
                [void]$out.Add((New-Card 'Get help' 'E897' @(@{ Text = 'Something not right? Copy a short report - versions, hardware, anything that isn''t green, what needs you and the last check - and paste it into a message to whoever helps you. Nothing personal is in it.'; Level = 'dim' }) @(New-Btn 'E8C8' 'Copy a report for help' $act.CopyReport)))
                [void]$out.Add((New-Card 'Uninstall' 'E74D' @(@{ Text = 'Removes Messiah - the tray icon, the automatic maintenance and this app. Your apps, files and games stay; it asks whether to put back the Windows settings it changed.'; Level = 'dim' }) @(New-Btn 'E74D' 'Uninstall Messiah...' $act.Uninstall)))
            }
        }
        $out
    }

    # where the window opens: -Page (also the older page names), else Home
    $script:onPage = 'Home'
    # no -Page: where the owner was last time (app-last.txt) - the tab, its sub-page and the Status rows they had open
    if (-not $Page -and -not $Test) { $Page = "$((Get-Content "$cl\app-last.txt" -ErrorAction SilentlyContinue) -match '^page=' -replace '^page=', '')".Trim(); if ($Page -eq 'Welcome') { $Page = $null } }
    if ($Page) { $pg_ = if ($oldPages.Contains($Page)) { $oldPages[$Page] } else { $Page }; $p_, $s_ = $pg_ -split '/', 2; if ($p_ -in 'Welcome', 'Home', 'Status', 'Activity', 'Settings') { $script:onPage = $p_; if ($s_) { $script:sub[$p_] = $s_ } } }
    $script:shown = $null; $script:claudeVer = $null; $navItems = @{}
    function Get-PageKey { if ($subPages.Contains($script:onPage)) { "$script:onPage/$($script:sub[$script:onPage])" } else { $script:onPage } }
    function Show-Page($p, $s) {   # a tab (and its sub-page) from anywhere: a tile, a button
        if ($s) { $script:sub[$p] = $s }
        if ($navItems.Contains($p)) { if ($navItems[$p].Button.IsChecked) { $script:onPage = $p; Update-Sub; Update-View -Force } else { $navItems[$p].Button.IsChecked = $true } }
    }
    # the pills next to a page's title (its sub-pages)
    function Update-Sub {
        $ui.SubNav.Children.Clear()
        $list = $subPages[$script:onPage]
        $ui.SubBox.Visibility = if ($list) { 'Visible' } else { 'Collapsed' }
        foreach ($s in @($list)) {
            $rb = New-Object Windows.Controls.RadioButton -Property @{ GroupName = 'sub'; Tag = $s; Content = $s; IsChecked = ($s -eq $script:sub[$script:onPage]) }
            $rb.Style = $win.FindResource('Pill')
            $rb.Add_Checked({ $script:sub[$script:onPage] = $this.Tag; Say ''; $ui.Scroll.ScrollToTop(); Update-View -Force })
            [void]$ui.SubNav.Children.Add($rb)
        }
    }
    function Update-View([switch]$Force) {
        # the AI assistant switched on or off (ai-toggle.ps1, a minute after the switch): the pages change with it
        $nowAi = if (Test-Path "$cl\ai-enabled.ps1") { [bool](& "$cl\ai-enabled.ps1") } else { $true }
        if ($nowAi -ne [bool]$script:ai) { $script:ai = $nowAi; $script:claudeVer = $null; $Force = $true }
        $secs = @(Get-KitStatus -ClaudeVersion $script:claudeVer)
        if ($ai -and -not $script:claudeVer) { $m = Sec $secs 'Messiah'; if ($m) { $script:claudeVer = ($m.Lines[0].Text -replace '^Claude Code ', '') } }
        # the Home tab shows how many things need the owner
        $todo = @((Sec $secs 'Needs you').Lines | Where-Object Level -eq 'warn').Count
        $navItems.Home.Tag.Text = if ($todo) { "$todo" } else { '' }; $navItems.Home.Tag.Parent.Visibility = if ($todo) { 'Visible' } else { 'Collapsed' }
        $ui.AiPill.Visibility = if ($ai) { 'Visible' } else { 'Collapsed' }
        # redraw only when something changed (no flicker; the scroll position stays while reading)
        $key = Get-PageKey
        if (-not $Test -and $key -ne $script:lastKey) { $script:lastKey = $key; Save-AppLast }   # (where to open next time)
        $sig = "$key`n" + (($secs | ForEach-Object { $_.Title; $_.Lines | ForEach-Object { "$($_.Level)|$($_.Text)" } }) -join "`n") +
            "`n" + ((Get-Item "$cl\health-history.json", "$cl\notifications.log", "$cl\maint-history", "$cl\kit-options.txt", "$cl\tweak-status.json", "$cl\guard-state.json", "$cl\diag-state.json", "$cl\whats-new.json" -ErrorAction SilentlyContinue | ForEach-Object { $_.LastWriteTime.Ticks }) -join ',') +
            "`n$($script:checkingSince -and $script:checkingSince -gt (Get-Date).AddMinutes(-3))`n$(if ($key -eq 'Home') { Get-Playing })"   # (a Check now running, or given up after 3 minutes; a game started or ended)
        if (-not $Force -and $sig -eq $script:shown) { return }
        $script:shown = $sig
        # Home: the status card is the header; the other pages have a title and their pills
        $ui.PageTitle.Text = switch ($script:onPage) { 'Welcome' { 'Welcome to Messiah' } default { $script:onPage } }
        $ui.PageSub.Text = $subs[$key]
        $ui.Header.Visibility = if ($script:onPage -eq 'Home') { 'Collapsed' } else { 'Visible' }
        $ui.Content.Children.Clear()
        # one page failing to build never takes the window down: it says so (the tests look for PAGE ERROR)
        $script:pageError = $null
        $els = try { @(Build-Page $key $secs) } catch {
            $script:pageError = "$($_.Exception.Message) (line $($_.InvocationInfo.ScriptLineNumber))"
            @(New-Card "This page couldn't be shown" 'E783' @(@{ Text = 'Something in its data is damaged. The other pages work; the next maintenance usually repairs it.'; Level = 'warn' }, @{ Text = $script:pageError; Level = 'dim' }) $null)
        }
        foreach ($el in $els) { [void]$ui.Content.Children.Add($el) }
    }

    # the tabs (built again when they change: the welcome page done)
    function Update-Nav {
        $script:pages = Get-Pages
        $ui.NavList.Children.Clear(); $navItems.Clear()
        foreach ($p in $pages.Keys) {
            $rb = New-Object Windows.Controls.RadioButton -Property @{ GroupName = 'nav'; Tag = $p; ToolTip = $p }; [Windows.Automation.AutomationProperties]::SetName($rb, $p)
            $rb.Style = $win.FindResource('Tab')
            $row = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
            [void]$row.Children.Add((New-Glyph $pages[$p] 14)); $row.Children[0].Margin = '0,0,8,0'
            [void]$row.Children.Add((New-Text $p $brush.Text 14 'Normal' '0'))
            $count = New-Object Windows.Controls.Border -Property @{ CornerRadius = 8; Background = $brush.Warn; Padding = '6,0'; MinWidth = 18; Margin = '8,0,0,0'; Visibility = 'Collapsed'; VerticalAlignment = 'Center' }
            $count.Child = New-Text '' $onColor 11 'SemiBold' '0'; $count.Child.HorizontalAlignment = 'Center'
            [void]$row.Children.Add($count)
            $rb.Content = $row
            $navItems[$p] = [pscustomobject]@{ Button = $rb; Tag = $count.Child }
            $rb.Add_Checked({ $script:onPage = $this.Tag; Say ''; Update-Sub; $ui.Scroll.ScrollToTop(); Update-View -Force })
            [void]$ui.NavList.Children.Add($rb)
        }
        if (-not $pages.Contains($script:onPage)) { $script:onPage = 'Home' }
        if (-not $Test) { $navItems[$script:onPage].Button.IsChecked = $true }
    }
    # --- the chat with Claude (chat-host.ps1, started by the elevated tray - app command 13): everything in the app, no
    # terminal. The app drops messages in chat\inbox and follows chat\events.jsonl; chat\state.json says what it's doing.
    # More chats can run side by side (10/11, the chat menu): the main one in chat\, the others in chats\<id>\. What's
    # shown when a chat opens is its conversation's transcript (so what was typed on the phone is there too).
    $script:chatDir = "$cl\chat"; if (($t_ = Get-AppLast 'chattab') -and $t_ -match '^[\w-]+$' -and (Test-Path "$cl\chats\$t_\inbox")) { $script:chatDir = "$cl\chats\$t_" }   # (the tab that was open last time) $script:live = $null; $script:liveText = ''
    $projDir = "$cl\projects\C--WINDOWS-system32"; $script:titleCache = @{}; $script:closing = @{}
    $script:chatW = 440; try { $script:chatW = [Math]::Max(320, [double](Get-Opt 'chatwidth' 440)) } catch {}
    function Set-IconBtn($b, $glyph, [switch]$Accent) {
        $b.Style = $win.FindResource($(if ($Accent) { 'AccentBtn' } else { 'Btn' })); $b.Margin = '4,0,0,0'; $b.Padding = '9,7'
        $b.Content = New-Glyph $glyph 14 $(if ($Accent) { $brush.OnAccent } else { $brush.Text })
    }
    # Markdown, simply: paragraphs, bullets, headings, code blocks, **bold** and `code` - in a read-only document, so
    # the text can be selected and copied (Ctrl+C, right-click); web addresses and files that exist are links
    $script:linkRx = '(https?://[^\s<>"`]*[^\s<>"`.,;:!?)\]]|[A-Za-z]:\\[^\s<>"`|*?]*[^\s<>"`|*?.,;:!?)\]])'
    function Get-LinkPath([string]$t) { $t -replace ':\d+(:\d+)?$', '' }   # (file.ps1:42 - the file)
    function Test-LinkTarget([string]$t) { if ($t -match '^https?://\S+$') { return $true }; if ($t -notmatch '^[A-Za-z]:\\') { return $false }; try { Test-Path -LiteralPath (Get-LinkPath $t) } catch { $false } }
    # a link: web addresses open in the browser, folders in Explorer, files selected in Explorer (never run)
    function Open-Target([string]$t) {
        if ($t -match '^https?://') { Start-Process $t; return }
        $p = Get-LinkPath $t
        if (Test-Path -LiteralPath $p -PathType Container) { Start-Process explorer.exe "`"$p`"" }
        elseif (Test-Path -LiteralPath $p) { Start-Process explorer.exe "/select,`"$p`"" }
        else { Say "Can't find $p any more." }
    }
    function New-Link([string]$text, [string]$target, [switch]$Code) {
        $h = New-Object Windows.Documents.Hyperlink (New-Object Windows.Documents.Run $text)
        $h.Foreground = $brush.Accent; $h.Tag = $target; $h.Cursor = 'Hand'
        $h.ToolTip = if ($target -match '^https?://') { "Open $target" } else { "Show in File Explorer: $target" }
        if ($Code) { $h.FontFamily = 'Cascadia Mono, Consolas'; $h.FontSize = 12.5 }
        $h.Add_Click({ try { Open-Target "$($this.Tag)" } catch { Say "Couldn't open it: $($_.Exception.Message)" } })
        $h
    }
    function Add-Plain($tb, [string]$t) {
        $i = 0
        foreach ($part in [regex]::Split($t, $script:linkRx)) {
            if ($part) { if ($i % 2 -and (Test-LinkTarget $part)) { $tb.Inlines.Add((New-Link $part $part)) } else { $tb.Inlines.Add((New-Object Windows.Documents.Run $part)) } }
            $i++
        }
    }
    function Add-Inlines($tb, [string]$t) {
        foreach ($part in [regex]::Split($t, '(\*\*[^*]+\*\*|`[^`]+`)')) {
            if (-not $part) { continue }
            if ($part -match '^\*\*(.+)\*\*$') { $r = New-Object Windows.Documents.Span; $r.FontWeight = 'SemiBold'; Add-Plain $r $Matches[1]; $tb.Inlines.Add($r) }
            elseif ($part -match '^`(.+)`$') {
                $x = $Matches[1]
                if (Test-LinkTarget $x) { $tb.Inlines.Add((New-Link $x $x -Code)) }
                else { $r = New-Object Windows.Documents.Run $x; $r.FontFamily = 'Cascadia Mono, Consolas'; $r.FontSize = 12.5; $r.Background = $brush.Seg; $tb.Inlines.Add($r) }
            }
            else { Add-Plain $tb $part }
        }
    }
    # a document that can be selected but not edited (the chat's own scrolling and Ctrl+wheel zoom: ChatScroll)
    function New-ChatDoc {
        $doc = New-Object Windows.Documents.FlowDocument -Property @{ PagePadding = '0'; FontFamily = $win.FontFamily; FontSize = 14; Foreground = $brush.Text; TextAlignment = 'Left' }
        New-Object Windows.Controls.RichTextBox -Property @{ Document = $doc; IsReadOnly = $true; IsDocumentEnabled = $true; Background = [Windows.Media.Brushes]::Transparent
            BorderThickness = '0'; Padding = '0'; Foreground = $brush.Text; FocusVisualStyle = $null; SelectionBrush = $brush.Accent; VerticalScrollBarVisibility = 'Disabled'; HorizontalScrollBarVisibility = 'Disabled' }
    }
    function Copy-Text([string]$t, [string]$what = 'Copied.') { try { [Windows.Clipboard]::SetText($t); Say $what } catch { Say "Couldn't copy: $($_.Exception.Message)" } }
    function New-CopyBtn([string]$text, [string]$tip) {
        $b = New-Object Windows.Controls.Button -Property @{ ToolTip = $tip; Tag = $text; Cursor = 'Hand' }
        Set-IconBtn $b 'E8C8'; $b.Padding = '6,4'; $b.Margin = '0'; $b.Content.FontSize = 12
        $b.Add_Click({ param($s_, $e_) $e_.Handled = $true; Copy-Text "$($this.Tag)" })
        $b
    }
    function New-Md([string]$md) {
        $rtb = New-ChatDoc; $doc = $rtb.Document
        $code = $null
        foreach ($l in ($md -replace "`r", '') -split "`n") {
            if ($l -match '^\s*```') {
                if ($null -ne $code) {   # a code block: its own box with a copy button
                    $ct = $code -join "`n"
                    $g = New-Object Windows.Controls.Grid -Property @{ Margin = '0,4,0,6' }
                    $cb = New-Object Windows.Controls.Border -Property @{ Background = $brush.Seg; CornerRadius = 6; Padding = '10,8,36,8' }
                    $cb.Child = New-Object Windows.Controls.TextBox -Property @{ Text = $ct; IsReadOnly = $true; FontFamily = 'Cascadia Mono, Consolas'; FontSize = 12; TextWrapping = 'Wrap'; Foreground = $brush.Text; Background = [Windows.Media.Brushes]::Transparent; BorderThickness = '0'; Padding = '0'; SelectionBrush = $brush.Accent; FocusVisualStyle = $null; VerticalScrollBarVisibility = 'Disabled' }
                    [void]$g.Children.Add($cb)
                    $cp = New-CopyBtn $ct 'Copy this'; $cp.HorizontalAlignment = 'Right'; $cp.VerticalAlignment = 'Top'; $cp.Margin = '0,4,4,0'
                    [void]$g.Children.Add($cp)
                    [void]$doc.Blocks.Add((New-Object Windows.Documents.BlockUIContainer $g)); $code = $null
                }
                else { $code = @() }
                continue
            }
            if ($null -ne $code) { $code += $l; continue }
            if (-not $l.Trim()) { continue }
            $tb = New-Object Windows.Documents.Paragraph -Property @{ Margin = '0,2,0,4' }
            if ($l -match '^\s*#{1,4}\s+(.*)') { Add-Inlines $tb $Matches[1]; $tb.FontWeight = 'SemiBold'; $tb.FontSize = 15; $tb.Margin = '0,6,0,4' }
            elseif ($l -match '^(\s*)[-*]\s+(.*)') { $tb.Margin = "$(8 + 14 * [Math]::Min(3, [int]($Matches[1].Length / 2))),1,0,3"; $tb.Inlines.Add((New-Object Windows.Documents.Run "$([char]0x2022)  ")); Add-Inlines $tb $Matches[2] }
            elseif ($l -match '^(\s*)(\d+[.)])\s+(.*)') { $tb.Margin = '8,1,0,3'; $tb.Inlines.Add((New-Object Windows.Documents.Run "$($Matches[2])  ")); Add-Inlines $tb $Matches[3] }
            else { Add-Inlines $tb $l }
            [void]$doc.Blocks.Add($tb)
        }
        if ($null -ne $code) { $p = New-Object Windows.Documents.Paragraph (New-Object Windows.Documents.Run ($code -join "`n")); $p.FontFamily = 'Cascadia Mono, Consolas'; $p.FontSize = 12; [void]$doc.Blocks.Add($p) }   # (a block still being written)
        $rtb
    }
    # a file sent along with a message: a line of its own, "Attached: <path>" (Claude reads it - pictures too)
    $script:attachRx = '^Attached: (.+)$'
    function Add-ChatItem($t, [string]$text) {
        switch ($t) {
            'user' {
                $b = New-Object Windows.Controls.Border -Property @{ CornerRadius = 12; Padding = '10,6'; Margin = '48,10,0,6'; HorizontalAlignment = 'Right'; Background = (New-Tint $brush.Accent 0x40) }
                $rtb = New-ChatDoc; $doc = $rtb.Document; $words = @(); $shown = @()
                foreach ($l in ($text -replace "`r", '') -split "`n") {
                    if ($l -match $script:attachRx) {
                        $f = $Matches[1].Trim(); $shown += "xx $(Split-Path $f -Leaf)"; $p = New-Object Windows.Documents.Paragraph -Property @{ Margin = '0,2,0,0'; FontSize = 12.5 }
                        $p.Inlines.Add((New-Object Windows.Documents.Run "$([char]0xD83D)$([char]0xDCCE) "))
                        if (Test-Path -LiteralPath $f) { $p.Inlines.Add((New-Link (Split-Path $f -Leaf) $f)) } else { $p.Inlines.Add((New-Object Windows.Documents.Run (Split-Path $f -Leaf))) }
                        [void]$doc.Blocks.Add($p)
                    } else { $words += $l }
                }
                $w = ($words -join "`n").Trim()
                if ($w) { $p = New-Object Windows.Documents.Paragraph -Property @{ Margin = '0' }; Add-Plain $p $w; if ($doc.Blocks.FirstBlock) { $doc.Blocks.InsertBefore($doc.Blocks.FirstBlock, $p) } else { [void]$doc.Blocks.Add($p) } }
                if (-not $doc.Blocks.Count) { return }
                # (a bubble only as wide as its longest line, else as wide as the chat: a document would always fill it)
                $tf = New-Object Windows.Media.Typeface "$($win.FontFamily)"; $max = 0
                foreach ($s in @($w -split "`n") + $shown) { if ($s) { $ft = New-Object Windows.Media.FormattedText ($s, [Globalization.CultureInfo]::CurrentUICulture, [Windows.FlowDirection]::LeftToRight, $tf, 14.0, $brush.Text, 1.0); $max = [Math]::Max($max, $ft.WidthIncludingTrailingWhitespace) } }
                $rtb.MaxWidth = [Math]::Max(40, $max + 16)
                $b.Child = $rtb; $b.Margin = '0'
                # the last message can be edited (a pencil beside it on hover): sent again in its place
                $wrap = New-Object Windows.Controls.DockPanel -Property @{ HorizontalAlignment = 'Right'; Margin = '48,10,0,6'; Background = [Windows.Media.Brushes]::Transparent; Tag = $text }
                $eb = New-Object Windows.Controls.Button -Property @{ ToolTip = 'Edit - Claude answers the new version instead'; VerticalAlignment = 'Center'; Opacity = 0 }
                Set-IconBtn $eb 'E70F'; $eb.Margin = '0,0,6,0'; $eb.Padding = '6,4'; $eb.Content.FontSize = 12
                $eb.Add_Click({ if ($this.Parent -eq $script:lastUser) { Start-Edit "$($this.Parent.Tag)" } })
                [Windows.Controls.DockPanel]::SetDock($eb, 'Left'); [void]$wrap.Children.Add($eb); [void]$wrap.Children.Add($b)
                $wrap.Add_MouseEnter({ if ($this -eq $script:lastUser) { $this.Children[0].Opacity = 1 } }); $wrap.Add_MouseLeave({ $this.Children[0].Opacity = 0 })
                $script:lastUser = $wrap
                [void]$ui.ChatList.Children.Add($wrap)
            }
            'text' {
                $sp = New-Object Windows.Controls.StackPanel -Property @{ Margin = '0,6,0,6'; Background = [Windows.Media.Brushes]::Transparent }
                [void]$sp.Children.Add((New-Md $text))
                $cp = New-CopyBtn $text 'Copy this reply'; $cp.HorizontalAlignment = 'Left'; $cp.Opacity = 0; $cp.Margin = '0,2,0,0'
                [void]$sp.Children.Add($cp)
                $sp.Add_MouseEnter({ $this.Children[1].Opacity = 1 }); $sp.Add_MouseLeave({ $this.Children[1].Opacity = 0 })
                [void]$ui.ChatList.Children.Add($sp)
            }
            'tool' {
                $r = New-Object Windows.Controls.DockPanel -Property @{ Margin = '2,2,0,2' }
                $g = New-Glyph 'E756' 11 $brush.Sub; $g.Margin = '0,1,8,0'; [Windows.Controls.DockPanel]::SetDock($g, 'Left'); [void]$r.Children.Add($g)
                [void]$r.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $text; Foreground = $brush.Sub; FontSize = 12; TextTrimming = 'CharacterEllipsis'; ToolTip = $text }))
                [void]$ui.ChatList.Children.Add($r)
            }
            'error' { [void]$ui.ChatList.Children.Add((New-Line "WARNING: $text" 'warn')) }
            'status' { if ($text -ne 'idle') { $x = New-Text $text $brush.Sub 12 'Normal' '0,8,0,8'; $x.HorizontalAlignment = 'Center'; [void]$ui.ChatList.Children.Add($x) } }
        }
    }
    # suggestions on an empty chat (and the to-do walk-through the terminal used to start by itself)
    function Show-ChatStart {
        $ui.ChatList.Children.Clear()
        $w = New-Text 'Ask anything - Claude can look at this PC and fix things, with admin rights. What it does shows here as it happens.' $brush.Sub 13 'Normal' '0,6,0,12'
        [void]$ui.ChatList.Children.Add($w)
        $ideas = @()
        if (Test-Path "$cl\maint-todo.txt") { $ideas += 'Go through my to-do list with me' }
        $ideas += 'How is my PC doing?', 'Why is my PC slow or stuttering?', 'What did maintenance do this week?'
        foreach ($i in $ideas) {
            $b = New-Btn 'E8BD' $i -Small { Send-Chat $this.ToolTip }; $b.Margin = '0,0,0,6'; $b.HorizontalAlignment = 'Left'
            [void]$ui.ChatList.Children.Add($b)
        }
    }
    # (pinned tabs first)
    function Get-ChatDirs { $all = @("$cl\chat") + @(Get-ChildItem "$cl\chats" -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object FullName | Where-Object { -not $script:closing[$_] }); @($all | Where-Object { Test-Path "$_\pinned.txt" }) + @($all | Where-Object { -not (Test-Path "$_\pinned.txt") }) }
    function Get-ChatState($d = $script:chatDir) { $j = try { Get-Content "$d\state.json" -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null }; if ($j -and $j.pid -and (Get-Process -Id $j.pid -ErrorAction SilentlyContinue)) { $j } }
    function Get-ChatSession($d = $script:chatDir) { $s = Get-ChatState $d; if ($s -and $s.session) { $s.session } else { "$(Get-Content "$d\session.txt" -ErrorAction SilentlyContinue)".Trim() } }
    # the tray's host (elevated) also starts the other chats' hosts when they have messages waiting
    function Start-ChatHost($d = $script:chatDir) {
        if (Get-ChatState $d) { return }
        if (-not (Send-Tray 13)) { Start-Process powershell -WindowStyle Hidden -ArgumentList ((& $psArgs 'chat-host.ps1') + @(if ($d -ne "$cl\chat") { '-Dir', "`"$d`"" })) }
    }
    function Send-ChatCmd($obj, $d = $script:chatDir) {
        New-Item "$d\inbox" -ItemType Directory -Force | Out-Null
        [IO.File]::WriteAllText("$d\inbox\$((Get-Date).ToString('yyyyMMddHHmmssfff'))-$(Get-Random).json", ($obj | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
        Start-ChatHost $d
    }
    # a file Claude is still writing: read it anyway
    function Read-Lines([string]$file) { try { $fs = [IO.File]::Open($file, 'Open', 'Read', 'ReadWrite'); try { $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8); while ($null -ne ($l = $sr.ReadLine())) { $l } } finally { $fs.Close() } } catch {} }
    function Get-StepText($c) {   # (chat-host.ps1's Get-Step: the same words)
        $i = $c.input
        $what = if ($i.description) { $i.description } elseif ($i.file_path) { "$(Split-Path $i.file_path -Leaf)" } elseif ($i.pattern) { "searching for $($i.pattern)" } elseif ($i.url) { $i.url } elseif ($i.query) { $i.query } elseif ($i.prompt) { "$($i.prompt)".Substring(0, [Math]::Min(60, "$($i.prompt)".Length)) } else { '' }
        $verb = switch -Regex ($c.name) { '^(Bash|PowerShell)$' { 'Running' } '^Read$' { 'Reading' } '^(Edit|Write|MultiEdit)$' { 'Editing' } '^(Grep|Glob)$' { 'Searching' } '^Web' { 'Looking up' } '^(Agent|Task)$' { 'Helper' } default { $c.name } }
        "$verb$(if ($what) { ": $what" })"
    }
    # a conversation from its transcript: what was asked (here, in the terminal or on the phone), the answers and the
    # steps - the last $Max of them
    function Get-TranscriptItems([string]$id, [int]$Max = 160) {
        $file = "$projDir\$id.jsonl"
        if (-not $id -or -not (Test-Path $file)) { return }
        $lines = @(Read-Lines $file | Where-Object { $_ -match '"type":"(user|assistant)"' -and $_ -notmatch '"isSidechain":true|"type":"tool_result"' })
        if ($lines.Count -gt $Max * 2) { $lines = $lines[($lines.Count - $Max * 2)..($lines.Count - 1)] }
        $out = foreach ($l in $lines) {
            $j = try { $l | ConvertFrom-Json } catch { continue }
            if ($j.type -eq 'user') {
                if ($j.isMeta -or $j.isCompactSummary) { continue }
                $c = $j.message.content
                $x = if ($c -is [string]) { $c } else { @($c | Where-Object type -eq 'text' | ForEach-Object text) -join "`n" }
                if ("$x".Trim() -and -not "$x".TrimStart().StartsWith('<')) { [pscustomobject]@{ T = 'user'; X = $x } }
            } elseif ($j.type -eq 'assistant') {
                foreach ($b in @($j.message.content)) {
                    if ($b.type -eq 'text' -and "$($b.text)".Trim()) { [pscustomobject]@{ T = 'text'; X = $b.text } }
                    elseif ($b.type -eq 'tool_use') { [pscustomobject]@{ T = 'tool'; X = (Get-StepText $b) } }
                }
            }
        }
        @($out) | Select-Object -Last $Max
    }
    # a conversation's name: the one it was given, else Claude's title for it, else the last thing asked
    function Get-SessionTitle($file) {
        $tail = try { $fs = [IO.File]::Open($file.FullName, 'Open', 'Read', 'ReadWrite'); try { $n = [int][Math]::Min($fs.Length, 262144); [void]$fs.Seek(-$n, 'End'); $buf = New-Object byte[] $n; [void]$fs.Read($buf, 0, $n); [Text.Encoding]::UTF8.GetString($buf) } finally { $fs.Close() } } catch { '' }
        $pick = { param($k) $m = [regex]::Matches($tail, "`"$k`":`"((?:[^`"\\]|\\.)*)`""); if ($m.Count) { try { "`"$($m[$m.Count - 1].Groups[1].Value)`"" | ConvertFrom-Json } catch { $null } } }
        $custom = & $pick 'customTitle'
        if ($custom -like 'Hidden maintenance*' -or "$(& $pick 'lastPrompt')" -match '^(Login rehearsal|Smoke test from the Messiah app):') { return [pscustomobject]@{ Title = $custom; Hidden = $true } }
        $title = if ($custom) { $custom } elseif ($x = & $pick 'aiTitle') { $x } elseif ($x = & $pick 'lastPrompt') { $x } else { $null }
        if (-not $title) { return $null }   # nothing said in it
        $title = ($title -replace '\s+', ' ').Trim(); if ($title.Length -gt 90) { $title = $title.Substring(0, 87) + '...' }
        [pscustomobject]@{ Title = $title; Hidden = $false }
    }
    # earlier conversations, newest first; InUse: open somewhere else right now (a terminal, a hidden run)
    function Get-SessionList {
        $live = @{}; foreach ($p in @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'")) { if ("$($p.CommandLine)" -match '--(session-id|resume)\s+"?([0-9a-fA-F-]{36})') { $live[$Matches[2]] = $true } }
        foreach ($file in @(Get-ChildItem "$projDir\*.jsonl" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 80)) {
            $key = "$($file.FullName)|$($file.LastWriteTime.Ticks)"
            if (-not $script:titleCache.ContainsKey($key)) { $script:titleCache[$key] = Get-SessionTitle $file }
            $ti = $script:titleCache[$key]
            if (-not $ti -or $ti.Hidden) { continue }
            [pscustomobject]@{ Id = $file.BaseName; Title = $ti.Title; When = $file.LastWriteTime; InUse = [bool]$live[$file.BaseName] -or ((Get-Date) - $file.LastWriteTime).TotalMinutes -lt 2 }   # (a terminal session: its command line has no id)
        }
    }
    # a chat's name: the one the owner gave its tab (title.txt), else its conversation's
    function Get-OwnTitle($d = $script:chatDir) { "$(Get-Content "$d\title.txt" -Encoding UTF8 -ErrorAction SilentlyContinue)".Trim() }
    function Get-HeaderTitle([string]$auto) { $o = Get-OwnTitle; if ($o) { $o } elseif (@(Get-ChatDirs).Count -gt 1) { if ($auto) { $auto } else { Get-ChatTitle } } else { 'Claude' } }
    function Get-ChatTitle($d = $script:chatDir) {
        $o = Get-OwnTitle $d; if ($o) { return $o }
        $id = Get-ChatSession $d
        $file = if ($id) { Get-Item "$projDir\$id.jsonl" -ErrorAction SilentlyContinue }
        $ti = if ($file) { $key = "$($file.FullName)|$($file.LastWriteTime.Ticks)"; if (-not $script:titleCache.ContainsKey($key)) { $script:titleCache[$key] = Get-SessionTitle $file }; $script:titleCache[$key] }
        if ($ti -and $ti.Title) { $ti.Title } else { 'New chat' }
    }
    # files going with the next message: pasted pictures (saved in .claude\chat-attachments - kept 30 days) and files
    # pasted or dropped from Explorer (sent as their paths; Claude Code reads pictures as pictures)
    $script:attach = New-Object Collections.Generic.List[string]; $script:lastSent = @{}
    $attDir = "$cl\chat-attachments"
    Get-ChildItem $attDir -File -ErrorAction SilentlyContinue | Where-Object LastWriteTime -lt (Get-Date).AddDays(-30) | ForEach-Object { [IO.File]::Delete($_.FullName) }
    function Update-Attach {
        $ui.ChatAttach.Children.Clear()
        foreach ($f in $script:attach) {
            $chip = New-Object Windows.Controls.Border -Property @{ CornerRadius = 6; Background = $brush.Seg; Padding = '8,2,2,2'; Margin = '0,0,6,4'; ToolTip = $f }
            $sp = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
            $g = New-Glyph $(if ($f -match '\.(png|jpe?g|gif|bmp|webp)$') { 'EB9F' } else { 'E8A5' }) 12 $brush.Sub; $g.Margin = '0,0,6,0'; [void]$sp.Children.Add($g)
            [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = (Split-Path $f -Leaf); FontSize = 12; MaxWidth = 180; TextTrimming = 'CharacterEllipsis'; VerticalAlignment = 'Center' }))
            $x = New-Object Windows.Controls.Button -Property @{ ToolTip = "Don't send this"; Tag = $f }
            Set-IconBtn $x 'E711'; $x.Margin = '4,0,0,0'; $x.Padding = '4,2'; $x.Content.FontSize = 9
            $x.Add_Click({ [void]$script:attach.Remove("$($this.Tag)"); Update-Attach })
            [void]$sp.Children.Add($x); $chip.Child = $sp
            [void]$ui.ChatAttach.Children.Add($chip)
        }
        $ui.ChatAttach.Visibility = if ($script:attach.Count) { 'Visible' } else { 'Collapsed' }
        $ui.ChatHint.Visibility = if ($ui.ChatInput.Text -or $script:attach.Count) { 'Collapsed' } else { 'Visible' }
    }
    function Clear-Attach { $script:attach.Clear(); Update-Attach }
    function Add-Attach([string[]]$paths) {
        foreach ($f in $paths) { if ($f -and (Test-Path -LiteralPath $f) -and -not $script:attach.Contains($f)) { $script:attach.Add($f) } }
        Update-Attach; $ui.ChatInput.Focus() | Out-Null
    }
    # a picture on the clipboard (a screenshot, Win+Shift+S): saved as a PNG file to send
    function Save-ClipImage {
        $img = [Windows.Clipboard]::GetImage(); if (-not $img) { return $null }
        New-Item $attDir -ItemType Directory -Force | Out-Null
        $f = "$attDir\screenshot-$((Get-Date).ToString('yyyyMMdd-HHmmss-fff')).png"
        $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($img))
        $fs = [IO.File]::Create($f); try { $enc.Save($fs) } finally { $fs.Close() }
        $f
    }
    # editing the last message: its words (and files) back in the box; sent, it replaces the old one and its answer
    $script:editing = $false; $script:lastUser = $null
    function Start-Edit([string]$text) {
        Clear-Attach; $w = @()
        foreach ($l in ($text -replace "`r", '') -split "`n") { if ($l -match $script:attachRx) { Add-Attach $Matches[1].Trim() } else { $w += $l } }
        $ui.ChatInput.Text = ($w -join "`n").Trim(); $ui.ChatInput.CaretIndex = $ui.ChatInput.Text.Length
        $script:editing = $true; $ui.ChatEditing.Visibility = 'Visible'; $ui.ChatInput.Focus() | Out-Null
    }
    function Stop-Edit { $script:editing = $false; $ui.ChatEditing.Visibility = 'Collapsed' }
    function Send-Chat([string]$t) {
        if ($t -eq 'Go through my to-do list with me') { $t = '/maintain The owner opened the chat in the Messiah app. Briefly go through the open items in maint-todo.txt with them.' }
        $files = @($script:attach)
        if (-not $t.Trim() -and -not $files.Count) { return }
        if ($t.Trim()) { $script:lastSent[$script:chatDir] = $t }
        if ($files.Count) { $t = (@($(if ($t.Trim()) { $t.TrimEnd() } else { 'Take a look at this.' })) + @($files | ForEach-Object { "Attached: $_" })) -join "`n"; Clear-Attach }
        if ($script:editing -and $script:lastUser) {
            $i = $ui.ChatList.Children.IndexOf($script:lastUser)   # (the old message and everything after it go)
            if ($i -ge 0) { while ($ui.ChatList.Children.Count -gt $i) { $ui.ChatList.Children.RemoveAt($i) } }
            $script:lastUser = $null; $script:live = $null; Stop-Edit
            Send-ChatCmd @{ cmd = 'edit'; text = $t }
        } else { Stop-Edit; Send-ChatCmd @{ text = $t } }
        $ui.ChatInput.Text = ''
        $ui.ChatWorking.Text = 'Sending...'; $ui.ChatWorking.Visibility = 'Visible'
    }
    # the chat follows events.jsonl: whole lines only, from where it left off
    function Update-Chat {
        $f = "$chatDir\events.jsonl"
        if (-not (Test-Path $f)) { return }
        $fs = [IO.File]::Open($f, 'Open', 'Read', 'ReadWrite')
        try {
            if ($fs.Length -lt $script:chatPos) { $script:chatPos = 0 }   # shortened by the host: read again
            if ($fs.Length -eq $script:chatPos) { return }
            [void]$fs.Seek($script:chatPos, 'Begin'); $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
            $text = $sr.ReadToEnd(); $cut = $text.LastIndexOf("`n") + 1
            $script:chatPos += [Text.Encoding]::UTF8.GetByteCount($text.Substring(0, $cut))
        } finally { $fs.Close() }
        $atEnd = $ui.ChatScroll.VerticalOffset -ge $ui.ChatScroll.ScrollableHeight - 40
        foreach ($line in $text.Substring(0, $cut) -split "`n") {
            $e = try { $line | ConvertFrom-Json } catch { continue }
            if (-not $e) { continue }
            if ($e.t -eq 'delta') {
                if (-not $script:live) { $script:live = New-Text '' $brush.Text 14 'Normal' '0,6,0,6'; $script:liveText = ''; [void]$ui.ChatList.Children.Add($script:live) }
                $script:liveText += $e.text; $script:live.Text = $script:liveText; continue
            }
            if ($e.t -eq 'text' -and $script:live) { $ui.ChatList.Children.Remove($script:live); $script:live = $null }
            if ($e.t -eq 'session') { continue }
            if ($ui.ChatList.Children.Count -and $ui.ChatList.Children[0].Text -like 'Ask anything*') { $ui.ChatList.Children.Clear() }
            Add-ChatItem $e.t $e.text
        }
        if ($atEnd) { $ui.ChatScroll.ScrollToEnd() }
    }
    # the open chat's conversation: from its transcript; a conversation not saved yet (or a failed first message): the
    # events since its Claude started (deltas left out - the whole messages follow them)
    function Open-ChatHistory([string]$Session) {
        $script:finds.Clear(); $script:findAt = -1; if ($ui.ChatFind.Visibility -eq 'Visible') { $ui.ChatFind.Visibility = 'Collapsed'; $ui.ChatFindCount.Text = '' }; Update-ChatModeBtn
        $ui.ChatList.Children.Clear(); $script:live = $null; $script:lastUser = $null; if ($script:editing) { Stop-Edit; $ui.ChatInput.Text = ''; Clear-Attach }
        $f = "$script:chatDir\events.jsonl"
        $shown = 0
        foreach ($i in @(Get-TranscriptItems $(if ($Session) { $Session } else { Get-ChatSession }))) { Add-ChatItem $i.T $i.X; $shown++ }
        if (-not $shown) {
            $lines = @(Get-Content $f -Encoding UTF8 -Tail 300 -ErrorAction SilentlyContinue)
            $start = 0; for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match '"t":"session"|"t":"status","text":"(New conversation|Opened an earlier|Continuing a copy)') { $start = $i + 1; break } }
            # (the "if": a range past the end would count backwards)
            foreach ($l in @(if ($start -lt $lines.Count) { $lines[$start..($lines.Count - 1)] })) { $e = try { $l | ConvertFrom-Json } catch { $null }; if ($e -and $e.t -notin 'delta', 'session') { Add-ChatItem $e.t $e.text; $shown++ } }
        }
        if (-not $shown) { Show-ChatStart }
        $script:chatPos = if (Test-Path $f) { (Get-Item $f).Length } else { 0 }
        $ui.ChatScroll.ScrollToEnd()
        $ui.ChatTitle.Text = Get-HeaderTitle
        Update-ChatTabs
    }
    # the screen the window is on (its work area, in the window's units): for sizes that fit any screen
    function Get-WorkArea {
        try {
            $h = (New-Object Windows.Interop.WindowInteropHelper $win).Handle
            $wa = [Windows.Forms.Screen]::FromHandle($h).WorkingArea
            $src = [Windows.PresentationSource]::FromVisual($win); $m = if ($src) { $src.CompositionTarget.TransformFromDevice } else { [Windows.Media.Matrix]::Identity }
            New-Object Windows.Rect ($m.Transform((New-Object Windows.Point $wa.Left, $wa.Top))), ($m.Transform((New-Object Windows.Point $wa.Right, $wa.Bottom)))
        } catch { [Windows.SystemParameters]::WorkArea }
    }
    # the window inside its screen (a smaller screen, another resolution, a monitor unplugged)
    function Set-WindowFit {
        if ($win.WindowState -ne 'Normal') { return }
        $a = Get-WorkArea
        if ($win.Width -gt $a.Width) { $win.Width = [Math]::Max($win.MinWidth, $a.Width) }
        if ($win.Height -gt $a.Height) { $win.Height = [Math]::Max($win.MinHeight, $a.Height) }
        if ($win.Left + $win.Width -gt $a.Right) { $win.Left = $a.Right - $win.Width }
        if ($win.Top + $win.Height -gt $a.Bottom) { $win.Top = $a.Bottom - $win.Height }
        if ($win.Left -lt $a.Left) { $win.Left = $a.Left }
        if ($win.Top -lt $a.Top) { $win.Top = $a.Top }
    }
    # the layout follows the window's width: the chat beside the page (its edge drags), or the whole window when it's
    # narrow; less margin, and the app's name and the button words go, as it gets smaller
    function Update-Layout {
        $w = $win.ActualWidth; if ($w -le 0) { return }
        $chat = $ui.ChatPanel.Visibility -eq 'Visible'
        $full = $chat -and $w -lt 900
        $star = New-Object Windows.GridLength 1, 'Star'
        if ($full) {
            $ui.MainCol.MinWidth = 0; $ui.MainCol.Width = New-Object Windows.GridLength 0
            $ui.ChatCol.MinWidth = 0; $ui.ChatCol.MaxWidth = [double]::PositiveInfinity; $ui.ChatCol.Width = $star
            $ui.ChatSplit.Visibility = 'Collapsed'; $mainW = 0
        } elseif ($chat) {
            $ui.MainCol.Width = $star; $ui.MainCol.MinWidth = 360
            $ui.ChatCol.MinWidth = 320; $ui.ChatCol.MaxWidth = [Math]::Max(320, $w - 380)
            if (-not $ui.ChatCol.Width.IsAbsolute -or $ui.ChatCol.Width.Value -lt 1) { $ui.ChatCol.Width = New-Object Windows.GridLength ([Math]::Min($script:chatW, $ui.ChatCol.MaxWidth)) }
            $ui.ChatSplit.Visibility = 'Visible'; $mainW = $w - $ui.ChatCol.Width.Value
        } else {
            $ui.MainCol.Width = $star; $ui.MainCol.MinWidth = 0
            $ui.ChatCol.MinWidth = 0; $ui.ChatCol.Width = New-Object Windows.GridLength 0
            $ui.ChatSplit.Visibility = 'Collapsed'; $mainW = $w
        }
        $m = if ($mainW -lt 640) { 12 } else { 24 }
        $ui.TopBar.Margin = "$m,14,$m,4"; $ui.Body.Margin = "$m,14,$m,28"; $ui.NowBar.Margin = "$m,8,$m,0"
        $ui.AppName.Visibility = if ($mainW -lt 780) { 'Collapsed' } else { 'Visible' }
        $ui.AiPill.Content.Children[1].Visibility = if ($mainW -lt 620) { 'Collapsed' } else { 'Visible' }
        if ($script:searchBtn) { $script:searchBtn.Content.Children[1].Visibility = if ($mainW -lt 700) { 'Collapsed' } else { 'Visible' } }
        foreach ($n in $navItems.Values) { $n.Button.Content.Children[1].Visibility = if ($mainW -lt 560) { 'Collapsed' } else { 'Visible' }; $n.Button.Content.Children[0].Margin = if ($mainW -lt 560) { '0' } else { '0,0,8,0' } }
        $narrow = $mainW -lt 660   # the page's own tabs go under its title
        [Windows.Controls.DockPanel]::SetDock($ui.SubBox, $(if ($narrow) { 'Bottom' } else { 'Right' }))
        $ui.SubBox.HorizontalAlignment = if ($narrow) { 'Left' } else { 'Stretch' }; $ui.SubBox.Margin = if ($narrow) { '0,12,0,0' } else { '16,0,0,0' }
        Update-Columns
    }
    function Show-Chat([bool]$on) {
        $ui.ChatPanel.Visibility = if ($on) { 'Visible' } else { 'Collapsed' }
        if ($on) {
            # room for the page and the chat side by side, when the screen has it
            if ($win.WindowState -eq 'Normal' -and $win.ActualWidth -lt $script:chatW + 600) {
                $a = Get-WorkArea; $nw = [Math]::Min($a.Width, $script:chatW + 760)
                if ($nw -gt $win.ActualWidth) { $win.Width = $nw; if ($win.Left + $nw -gt $a.Right) { $win.Left = [Math]::Max($a.Left, $a.Right - $nw) } }
            }
            Open-ChatHistory; if (-not (Get-ChatState)) { Send-ChatCmd @{ cmd = 'start' } }; $ui.ChatInput.Focus() | Out-Null
        } else { Show-ChatMenu $false }
        Update-Layout
    }
    # --- the chat menu (the button at the top left of the chat): the chats running here, a new one beside them, and
    # earlier conversations (this PC's: the app, the terminal, the phone) to pick up again
    function New-MenuRow($title, $sub, [scriptblock]$do, $arg, [switch]$Current, [scriptblock]$close, $glyph = 'E8BD') {   # $do / $close get $arg
        $row = New-Object Windows.Controls.Border -Property @{ CornerRadius = 8; Padding = '10,8'; Margin = '0,0,0,2'; Cursor = 'Hand'; Background = $(if ($Current) { $brush.SegSel } else { [Windows.Media.Brushes]::Transparent }); Tag = @($do, $arg); Uid = $(if ($Current) { 'current' } else { '' }) }
        $dp = New-Object Windows.Controls.DockPanel
        $g = New-Glyph $glyph 13 $(if ($Current) { $brush.Accent } else { $brush.Sub }); $g.Margin = '0,2,10,0'; $g.VerticalAlignment = 'Top'; [Windows.Controls.DockPanel]::SetDock($g, 'Left'); [void]$dp.Children.Add($g)
        if ($close) {
            $x = New-Object Windows.Controls.Button -Property @{ ToolTip = 'Close this chat (the conversation stays in the list below)'; Tag = @($close, $arg); VerticalAlignment = 'Center' }
            Set-IconBtn $x 'E711'; $x.Padding = '6,4'; $x.Add_Click({ param($s_, $e_) $e_.Handled = $true; & $this.Tag[0] $this.Tag[1] })
            [Windows.Controls.DockPanel]::SetDock($x, 'Right'); [void]$dp.Children.Add($x)
        }
        $sp = New-Object Windows.Controls.StackPanel
        [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $title; FontSize = 13; Foreground = $brush.Text; TextTrimming = 'CharacterEllipsis'; ToolTip = $title }))
        if ($sub) { [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $sub; FontSize = 11.5; Foreground = $brush.Sub; TextTrimming = 'CharacterEllipsis' })) }
        [void]$dp.Children.Add($sp); $row.Child = $dp
        $row.Add_MouseEnter({ if ($this.Uid -ne 'current') { $this.Background = $brush.NavHover } })
        $row.Add_MouseLeave({ $this.Background = if ($this.Uid -eq 'current') { $brush.SegSel } else { [Windows.Media.Brushes]::Transparent } })
        $row.Add_MouseLeftButtonUp({ try { & $this.Tag[0] $this.Tag[1] } catch { Say "Couldn't do that: $($_.Exception.Message)" } })
        $row
    }
    function Show-ChatMenu([bool]$on) {
        $ui.ChatMenuPanel.Visibility = if ($on) { 'Visible' } else { 'Collapsed' }
        Set-IconBtn $ui.ChatMenu $(if ($on) { 'E711' } else { 'E700' }); $ui.ChatMenu.Margin = '0'
        if ($on) { $ui.ChatSearch.Text = ''; Update-ChatMenu; $ui.ChatSearch.Focus() | Out-Null }
    }
    function Update-ChatMenu {
        $L = $ui.ChatMenuList; $L.Children.Clear(); $q = $ui.ChatSearch.Text.Trim()
        $dirs = @(Get-ChatDirs); $open = @{}
        foreach ($d in $dirs) { $s = Get-ChatSession $d; if ($s) { $open[$s] = $d } }
        if (-not $q) {
            [void]$L.Children.Add((New-Section 'Chats running here'))
            foreach ($d in $dirs) {
                $s = Get-ChatState $d
                $sub = if ($s -and $s.busy) { "Working$(if ($s.step) { ": $($s.step)" })" } elseif ($s) { "Ready$(if ($s.remote) { ' - on your phone too' })" } else { 'Starts when you send a message' }
                $close = if ($d -ne "$cl\chat") { { param($x) Close-ChatTab $x } }
                [void]$L.Children.Add((New-MenuRow (Get-ChatTitle $d) $sub { param($x) Switch-Chat $x } $d -Current:($d -eq $script:chatDir) -close $close -glyph $(if ($s -and $s.busy) { 'E916' } else { 'E8BD' })))
            }
            [void]$L.Children.Add((New-MenuRow 'New chat beside these' 'Another Claude, working at the same time (Ctrl+T)' { New-ChatTab } $null -glyph 'E710'))
            if (Get-ChatSession) { [void]$L.Children.Add((New-MenuRow 'Copy this conversation' 'The whole chat as text, to paste anywhere' { Copy-Conversation; Show-ChatMenu $false } $null -glyph 'E8C8')) }
        }
        [void]$L.Children.Add((New-Section 'Earlier conversations'))
        $n = 0
        foreach ($s in @(Get-SessionList)) {
            if ($q -and $s.Title -notlike "*$q*") { continue }
            if ($n++ -ge 50) { break }
            $where = if ($open[$s.Id]) { 'open in a chat here' } elseif ($s.InUse) { 'open somewhere else now' } else { '' }
            $sub = "$(Format-When $s.When)$(if ($where) { "  -  $where" })"
            [void]$L.Children.Add((New-MenuRow $s.Title $sub { param($x) Open-Earlier $x } $s -glyph 'E81C'))
        }
        if (-not $n) { [void]$L.Children.Add((New-Text $(if ($q) { "Nothing matches `"$q`"." } else { 'No earlier conversations yet.' }) $brush.Sub 13 'Normal' '10,4,0,0')) }
    }
    function Switch-Chat($d) { $script:chatDir = $d; if (-not $Test) { Save-AppLast }; Show-ChatMenu $false; Open-ChatHistory; if (-not (Get-ChatState)) { Send-ChatCmd @{ cmd = 'start' } }; Update-Now; $ui.ChatInput.Focus() | Out-Null }
    # the chats running here as tabs under the title (only when there's more than one); rebuilt only when one changed
    function Update-ChatTabs {
        $dirs = @(Get-ChatDirs)
        $tabs = foreach ($d in $dirs) { $s = Get-ChatState $d; [pscustomobject]@{ Dir = $d; Title = (Get-ChatTitle $d); Busy = [bool]($s -and $s.busy); Pin = (Test-Path "$d\pinned.txt") } }
        $key = "$script:chatDir|" + (($tabs | ForEach-Object { "$($_.Dir)>$($_.Title)>$($_.Busy)>$($_.Pin)" }) -join '|')
        if ($key -eq $script:tabsKey -or $script:renaming) { return }; $script:tabsKey = $key
        $ui.ChatTabs.Children.Clear()
        $ui.ChatTabs.Visibility = if ($dirs.Count -gt 1) { 'Visible' } else { 'Collapsed' }
        if ($dirs.Count -lt 2) { return }
        foreach ($t in $tabs) {
            $cur = $t.Dir -eq $script:chatDir
            $tab = New-Object Windows.Controls.Border -Property @{ CornerRadius = 8; Padding = '9,4,4,4'; Margin = '0,0,6,6'; Cursor = 'Hand'; Tag = $t.Dir; ToolTip = $t.Title; BorderThickness = 1
                Background = $(if ($cur) { $brush.SegSel } else { $brush.Seg }); BorderBrush = $(if ($cur) { $brush.Accent } else { [Windows.Media.Brushes]::Transparent }) }
            $sp = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
            if ($t.Busy) { $g = New-Glyph 'E916' 11 $brush.Accent; $g.Margin = '0,0,6,0'; [void]$sp.Children.Add($g) }
            elseif ($t.Pin) { $g = New-Glyph 'E718' 11 $brush.Sub; $g.Margin = '0,0,6,0'; [void]$sp.Children.Add($g) }
            [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $t.Title; FontSize = 12; MaxWidth = 140; TextTrimming = 'CharacterEllipsis'; VerticalAlignment = 'Center'; Foreground = $(if ($cur) { $brush.Text } else { $brush.Sub }) }))
            # right-click: rename, pin, close; double-click: rename
            $cm = New-Object Windows.Controls.ContextMenu
            foreach ($mi in @(@('Rename', 'rename'), @($(if ($t.Pin) { 'Unpin' } else { 'Pin (stays first, can''t be closed by accident)' }), 'pin'), @('Close', 'close'))) {
                $m_ = New-Object Windows.Controls.MenuItem -Property @{ Header = $mi[0]; Tag = @($mi[1], $t.Dir) }
                if ($mi[1] -eq 'close' -and ($t.Pin -or $t.Dir -eq "$cl\chat")) { $m_.IsEnabled = $false }
                $m_.Add_Click({ $w_, $d_ = $this.Tag; switch ($w_) { 'rename' { Start-RenameChat $d_ } 'pin' { Switch-ChatPin $d_ } 'close' { Close-ChatTab $d_ } } })
                [void]$cm.Items.Add($m_)
            }
            $tab.ContextMenu = $cm
            $tab.Add_MouseLeftButtonDown({ param($s_, $e_) if ($e_.ClickCount -eq 2) { $e_.Handled = $true; Start-RenameChat $this.Tag } })
            if ($t.Dir -ne "$cl\chat" -and -not $t.Pin) {
                $x = New-Object Windows.Controls.Button -Property @{ ToolTip = 'Close this tab (the conversation stays in the list)'; Tag = $t.Dir; VerticalAlignment = 'Center' }
                Set-IconBtn $x 'E711'; $x.Margin = '4,0,0,0'; $x.Padding = '4,2'; $x.Content.FontSize = 9
                $x.Add_Click({ param($s_, $e_) $e_.Handled = $true; Close-ChatTab $this.Tag })
                [void]$sp.Children.Add($x)
            } else { $sp.Margin = '0,0,5,0' }
            $tab.Child = $sp
            if (-not $cur) { $tab.Add_MouseEnter({ $this.Background = $brush.NavHover }); $tab.Add_MouseLeave({ $this.Background = $brush.Seg }) }
            $tab.Add_MouseLeftButtonUp({ if ($this.Tag -ne $script:chatDir) { Switch-Chat $this.Tag } })
            [void]$ui.ChatTabs.Children.Add($tab)
        }
    }
    # pin: the tab stays first and has no close button; rename: a box in the tab (or the chat's title, with one chat) -
    # Enter keeps it, Esc goes back, empty = the conversation's own title again. Also its name in Remote Control (name.txt).
    function Switch-ChatPin($d) {
        if (Test-Path "$d\pinned.txt") { [IO.File]::Delete("$d\pinned.txt"); Say 'Unpinned.' } else { Set-Content "$d\pinned.txt" (Get-Date -Format s); Say 'Pinned - it stays first and can''t be closed by accident.' }
        $script:tabsKey = $null; Update-ChatTabs
    }
    function Save-ChatName($d, [string]$name) {
        $name = ($name -replace '\s+', ' ').Trim(); if ($name.Length -gt 60) { $name = $name.Substring(0, 60) }
        if ($name) { [IO.File]::WriteAllText("$d\title.txt", $name, (New-Object Text.UTF8Encoding $false)); Set-Content "$d\name.txt" $name -Encoding UTF8 }
        elseif (Test-Path "$d\title.txt") { [IO.File]::Delete("$d\title.txt") }
    }
    function Start-RenameChat($d) {
        if ($script:renaming) { return }
        $tab = @($ui.ChatTabs.Children | Where-Object { $_.Tag -eq $d }) | Select-Object -First 1
        $box = New-Object Windows.Controls.TextBox -Property @{ Text = (Get-ChatTitle $d); FontSize = 12; MinWidth = 140; MaxWidth = 220; Tag = $d; Background = $brush.Btn; Foreground = $brush.Text; CaretBrush = $brush.Text; BorderBrush = $brush.Accent; Padding = '4,1' }
        if ($tab -and $ui.ChatTabs.Visibility -eq 'Visible') { $script:renameHost = @($tab, $tab.Child); $tab.Child = $box }
        else { $pp = $ui.ChatTitle.Parent; $box.FontSize = 15; $script:renameHost = @($pp, $null); $ui.ChatTitle.Visibility = 'Collapsed'; $pp.Children.Insert(0, $box) }
        $script:renaming = $true
        $done = {
            param([bool]$keep)
            if (-not $script:renaming) { return }; $script:renaming = $false
            $b_ = $script:renameEdit; if ($keep) { Save-ChatName $b_.Tag $b_.Text }
            $h_ = $script:renameHost; if ($h_[1]) { $h_[0].Child = $h_[1] } else { $h_[0].Children.Remove($b_); $ui.ChatTitle.Visibility = 'Visible' }
            $script:tabsKey = $null; Update-ChatTabs; $ui.ChatTitle.Text = Get-HeaderTitle
        }
        $script:renameDone = $done; $script:renameEdit = $box
        $box.Add_KeyDown({ param($s_, $e_) if ($e_.Key -eq 'Return') { $e_.Handled = $true; & $script:renameDone $true } elseif ($e_.Key -eq 'Escape') { $e_.Handled = $true; & $script:renameDone $false } })
        $box.Add_LostKeyboardFocus({ & $script:renameDone $true })
        $box.Focus() | Out-Null; $box.SelectAll()
    }
    # the open chat as plain text: what was asked and the answers (not the steps)
    function Copy-Conversation {
        $items = @(Get-TranscriptItems (Get-ChatSession) -Max 2000 | Where-Object { $_.T -in 'user', 'text' })
        if (-not $items.Count) { Say 'Nothing in this chat yet.'; return }
        Copy-Text (($items | ForEach-Object { "$(if ($_.T -eq 'user') { 'You' } else { 'Claude' }):`n$($_.X.Trim())" }) -join "`n`n") "Copied the conversation ($($items.Count) messages)."
    }
    # the tray asks for a chat to be shown (its "Claude finished" note was clicked): app-request.txt "chat=<tab>"
    function Read-AppRequest {
        $f = "$cl\app-request.txt"; if ($Test -or -not $script:ai -or -not (Test-Path $f)) { return }
        $r = "$(Get-Content $f -ErrorAction SilentlyContinue)".Trim(); [IO.File]::Delete($f)
        if ($r -notmatch '^chat=([\w-]*)$') { return }
        $d = if ($Matches[1] -and (Test-Path "$cl\chats\$($Matches[1])")) { "$cl\chats\$($Matches[1])" } else { "$cl\chat" }
        if ($ui.ChatPanel.Visibility -ne 'Visible') { $script:chatDir = $d; Show-Chat $true } elseif ($d -ne $script:chatDir) { Switch-Chat $d }
    }
    function New-ChatTab {
        $d = "$cl\chats\$((Get-Date).ToString('yyyyMMdd-HHmmss'))"; New-Item "$d\inbox" -ItemType Directory -Force | Out-Null
        Set-Content "$d\name.txt" "Messiah $(@(Get-ChatDirs).Count)"   # (its name in Remote Control, on the phone)
        Switch-Chat $d
    }
    function Close-ChatTab($d) {
        if (Test-Path "$d\pinned.txt") { Say 'This tab is pinned - right-click it > Unpin first.'; return }
        $s = Get-ChatState $d
        if ($s -and $s.busy -and [Windows.MessageBox]::Show('Claude is still working in this chat. Stop it and close the chat?', 'Close chat', 'OKCancel', 'Question') -ne 'OK') { return }
        $script:closing[$d] = $true
        if ($s) { Send-ChatCmd @{ cmd = 'quit' } $d } else { Remove-Item $d -Recurse -Force -ErrorAction SilentlyContinue }
        if ($script:chatDir -eq $d) { Switch-Chat "$cl\chat" } elseif ($ui.ChatMenuPanel.Visibility -eq 'Visible') { Update-ChatMenu }
        Update-ChatTabs
    }
    # an earlier conversation: in the chat that has it open, else in this chat (or a new one beside it, when this one
    # is busy). Open somewhere else right now: a copy, so the two don't write over each other.
    function Open-Earlier($s) {
        foreach ($d in @(Get-ChatDirs)) { if ((Get-ChatSession $d) -eq $s.Id) { Switch-Chat $d; return } }
        $cs = Get-ChatState
        if ($cs -and $cs.busy) { $d = "$cl\chats\$((Get-Date).ToString('yyyyMMdd-HHmmss'))"; New-Item "$d\inbox" -ItemType Directory -Force | Out-Null; Set-Content "$d\name.txt" "Messiah $(@(Get-ChatDirs).Count)"; $script:chatDir = $d }
        Send-ChatCmd @{ cmd = 'open'; session = $s.Id; fork = $s.InUse }
        Show-ChatMenu $false; Open-ChatHistory -Session $s.Id
        if ($s.InUse) { Say 'That conversation is open somewhere else too - this chat continues a copy of it, so the two don''t clash.' }
        $ui.ChatTitle.Text = Get-HeaderTitle $s.Title
        $ui.ChatInput.Focus() | Out-Null
    }
    # what's running right now - the chat, a hidden maintenance run, a session finishing earlier work - one line at the top
    function Get-Now {
        foreach ($d in @(Get-ChatDirs)) { $cs = Get-ChatState $d; if ($cs -and $cs.busy) { $script:nowChat = $d; return @('chat', "Claude is working$(if ($cs.step) { ": $($cs.step)" })") } }
        $m = "$cl\maint-claude-running"
        if ((Test-Path $m) -and ((Get-Date) - (Get-Item $m).LastWriteTime).TotalMinutes -lt 60 -and (Get-Item $m).LastWriteTime -gt (Get-CimInstance Win32_OperatingSystem).LastBootUpTime) {
            $s = @(Get-Content "$cl\maint-claude-session" -ErrorAction SilentlyContinue)
            $kind = switch -Regex ("$($s[1])") { 'improve' { 'improving Messiah' } 'maintain' { 'checking the PC' } default { 'maintenance' } }
            $step = ''
            $t = if ($s) { Get-ChildItem "$cl\projects\*\$($s[0]).jsonl" -ErrorAction SilentlyContinue | Select-Object -First 1 }
            if ($t) { foreach ($l in @(Get-Content $t.FullName -Tail 30 -Encoding UTF8 -ErrorAction SilentlyContinue)) { $j = try { $l | ConvertFrom-Json } catch { $null }; if ($j.type -eq 'assistant') { foreach ($c in @($j.message.content)) { if ($c.type -eq 'tool_use') { $step = if ($c.input.description) { $c.input.description } else { $c.name } } } } } }
            return @('maint', "Claude is $kind in the background$(if ($step) { ": $step" })")
        }
        $null
    }
    $script:nowTick = 0
    function Update-Now {
        Read-AppRequest
        $n = Get-Now
        $ui.NowBar.Visibility = if ($n) { 'Visible' } else { 'Collapsed' }
        if ($n) { $ui.NowText.Text = $n[1]; $ui.NowBar.Tag = $n[0]; $ui.NowDot.Opacity = if ($script:nowTick++ % 2) { 0.35 } else { 1 } }
        $cs = Get-ChatState
        $ui.ChatStatus.Text = if (-not $cs) { 'Starts when you send a message' } elseif ($cs.busy) { 'Working' } else { "Ready$(if ($cs.remote) { ' - on your phone too' })" }
        $ui.ChatRemote.Visibility = if ($cs -and $cs.remote) { 'Visible' } else { 'Collapsed' }; $ui.ChatRemote.Tag = if ($cs) { $cs.remote }
        Update-ChatTabs
        # the screen changed (resolution, another monitor): the window fits it again
        $wa = "$(Get-WorkArea)"; if ($script:lastWa -and $wa -ne $script:lastWa) { Set-WindowFit; Update-Layout }; $script:lastWa = $wa
        $busy = $cs -and $cs.busy
        $ui.ChatWorking.Visibility = if ($busy) { 'Visible' } elseif ($ui.ChatWorking.Text -eq 'Sending...' -and $cs) { 'Visible' } else { 'Collapsed' }
        if ($busy) { $ui.ChatWorking.Text = "$([char]0x25CF) $(if ($cs.step) { $cs.step } else { 'Thinking' })..." }
        if ($script:sendBusy -ne [bool]$busy) { $script:sendBusy = [bool]$busy; if ($busy) { Set-IconBtn $ui.ChatSend 'E71A'; $ui.ChatSend.ToolTip = 'Stop' } else { Set-IconBtn $ui.ChatSend 'E724' -Accent; $ui.ChatSend.ToolTip = 'Send (Enter) - Shift+Enter for a new line' } }
    }
    Set-IconBtn $ui.ChatClose 'E711'; Set-IconBtn $ui.ChatNew 'E710'; Set-IconBtn $ui.ChatSend 'E724' -Accent; $script:sendBusy = $false
    Set-IconBtn $ui.ChatMenu 'E700'; $ui.ChatMenu.Margin = '0'; Set-IconBtn $ui.ChatRemote 'E8EA'
    $ui.ChatRemote.ToolTip = 'Remote Control is on: this chat is on your phone (Claude app) and at claude.ai/code too - click to open it in the browser'
    $ui.ChatRemote.Add_Click({ if ($this.Tag) { Start-Process "$($this.Tag)" } })
    $ui.ChatMenu.Add_Click({ Show-ChatMenu ($ui.ChatMenuPanel.Visibility -ne 'Visible') })
    $ui.ChatSearch.Add_TextChanged({ $ui.ChatSearchHint.Visibility = if ($ui.ChatSearch.Text) { 'Collapsed' } else { 'Visible' }; if ($ui.ChatMenuPanel.Visibility -eq 'Visible') { Update-ChatMenu } })
    $ui.ChatSplit.Add_DragCompleted({ $script:chatW = [Math]::Round($ui.ChatCol.ActualWidth); Set-Opt 'chatwidth' $script:chatW; Update-Layout })
    $ui.ChatClose.Add_Click({ Show-Chat $false })
    # a new conversation opens in a new tab and the one open keeps going (this chat still empty: it's already new)
    # --- the chat's speed, per tab (mode.txt "model/effort", read by chat-host.ps1): the button in the chat's title bar
    $script:modes = @(
        @('Quick', 'sonnet/low', 'Sonnet, low effort - fast answers, easy on your plan''s usage'),
        @('Standard', 'opus/medium', 'Opus, medium effort - the default'),
        @('Deep', 'opus/high', 'Opus, high effort - hard problems like crash hunts'),
        @('Deepest', 'opus/max', 'Opus, maximum effort - slowest, uses the most'))
    function Get-ChatMode($d = $script:chatDir) { $m = "$(Get-Content "$d\mode.txt" -ErrorAction SilentlyContinue)".Trim(); $f = $script:modes | Where-Object { $_[1] -eq $m } | Select-Object -First 1; if ($f) { $f } else { $script:modes[1] } }
    function Update-ChatModeBtn {
        $m = Get-ChatMode; $sp = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
        [void]$sp.Children.Add((New-Glyph $(if ($m[0] -eq 'Quick') { 'E945' } else { 'E9D9' }) 13 $brush.Text))
        [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $m[0]; FontSize = 12; Margin = '6,0,0,0'; VerticalAlignment = 'Center' }))
        $ui.ChatMode.Content = $sp; $ui.ChatMode.ToolTip = "Speed: $($m[0]) ($($m[2])). Click to change - for this tab."
    }
    function Set-ChatMode($v) {
        $d = $script:chatDir
        if ($v -eq 'opus/medium') { if (Test-Path "$d\mode.txt") { [IO.File]::Delete("$d\mode.txt") } } else { Set-Content "$d\mode.txt" $v }
        Update-ChatModeBtn; if (Get-ChatState) { Send-ChatCmd @{ cmd = 'mode' } }
        $m = Get-ChatMode; Say "$($m[0]) from now on in this tab$(if ((Get-ChatState) -and (Get-ChatState).busy) { ' - after the current answer' })."
    }
    $ui.ChatMode.Style = $win.FindResource('Btn'); $ui.ChatMode.Margin = '4,0,0,0'; $ui.ChatMode.Padding = '9,6'
    $ui.ChatMode.Add_Click({
            $cm = New-Object Windows.Controls.ContextMenu; $cur = (Get-ChatMode)[1]
            foreach ($m in $script:modes) {
                $mi = New-Object Windows.Controls.MenuItem -Property @{ Header = "$($m[0]) - $($m[2])"; IsCheckable = $true; IsChecked = ($m[1] -eq $cur); Tag = $m[1] }
                $mi.Add_Click({ Set-ChatMode "$($this.Tag)" }); [void]$cm.Items.Add($mi)
            }
            $cm.PlacementTarget = $this; $cm.Placement = 'Bottom'; $cm.IsOpen = $true })
    Update-ChatModeBtn
    # --- find in the open conversation (Ctrl+F in the chat): every match marked, Enter / Shift+Enter go through them
    $script:finds = New-Object Collections.Generic.List[object]; $script:findAt = -1
    $findBrush = New-Tint $brush.Warn 0x55; $findCur = New-Tint $brush.Warn 0xB0
    function Get-ChatDocs {   # the replies' and messages' documents, in order
        foreach ($el in $ui.ChatList.Children) {
            if ($el -is [Windows.Controls.StackPanel] -and $el.Children.Count -and $el.Children[0] -is [Windows.Controls.RichTextBox]) { $el.Children[0] }
            elseif ($el -is [Windows.Controls.DockPanel] -and $el.Children.Count -gt 1 -and $el.Children[1].Child -is [Windows.Controls.RichTextBox]) { $el.Children[1].Child }
        }
    }
    function Clear-Finds { foreach ($f in $script:finds) { try { $f.R.ApplyPropertyValue([Windows.Documents.TextElement]::BackgroundProperty, $f.Bg) } catch {} }; $script:finds.Clear(); $script:findAt = -1 }
    function Find-InChat([string]$q) {
        Clear-Finds
        if ($q.Length -ge 2) {
            foreach ($rtb in @(Get-ChatDocs)) {
                $hits = @(); $p = $rtb.Document.ContentStart
                while ($p) {
                    if ($p.GetPointerContext('Forward') -eq 'Text') {
                        $run = $p.GetTextInRun('Forward'); $i = 0
                        while (($i = $run.IndexOf($q, $i, [StringComparison]::OrdinalIgnoreCase)) -ge 0) { $hits += , @($p.GetPositionAtOffset($i), $p.Parent); $i += $q.Length }
                    }
                    $p = $p.GetNextContextPosition('Forward')
                }
                foreach ($h in $hits) {   # (marked after the walk: marking splits the text it walks)
                    $r = New-Object Windows.Documents.TextRange ($h[0], $h[0].GetPositionAtOffset($q.Length))
                    $script:finds.Add([pscustomobject]@{ R = $r; Bg = $(if ($h[1] -is [Windows.Documents.TextElement]) { $h[1].Background }); Box = $rtb })
                    $r.ApplyPropertyValue([Windows.Documents.TextElement]::BackgroundProperty, $findBrush)
                }
            }
        }
        $ui.ChatFindCount.Text = if ($q.Length -lt 2) { '' } elseif ($script:finds.Count) { "$($script:finds.Count) found" } else { 'Not found' }
        if ($script:finds.Count) { Step-Find ($script:finds.Count - 1) -Absolute }   # (the newest first - what was just said)
    }
    function Step-Find([int]$n, [switch]$Absolute) {
        if (-not $script:finds.Count) { return }
        if ($script:findAt -ge 0) { $script:finds[$script:findAt].R.ApplyPropertyValue([Windows.Documents.TextElement]::BackgroundProperty, $findBrush) }
        $script:findAt = if ($Absolute) { $n } else { ($script:findAt + $n + $script:finds.Count) % $script:finds.Count }
        $f = $script:finds[$script:findAt]; $f.R.ApplyPropertyValue([Windows.Documents.TextElement]::BackgroundProperty, $findCur)
        $ui.ChatFindCount.Text = "$($script:findAt + 1) of $($script:finds.Count)"
        try {   # scrolled to it, a little below the top
            $rc = $f.R.Start.GetCharacterRect('Forward'); $pt = $f.Box.TranslatePoint((New-Object Windows.Point 0, $rc.Top), $ui.ChatScroll)
            $ui.ChatScroll.ScrollToVerticalOffset([Math]::Max(0, $ui.ChatScroll.VerticalOffset + $pt.Y - 80))
        } catch {}
    }
    function Show-ChatFind([bool]$on) {
        $ui.ChatFind.Visibility = if ($on) { 'Visible' } else { 'Collapsed' }
        if ($on) { $ui.ChatFindBox.Focus() | Out-Null; $ui.ChatFindBox.SelectAll(); if ($ui.ChatFindBox.Text) { Find-InChat $ui.ChatFindBox.Text } } else { Clear-Finds; $ui.ChatFindCount.Text = ''; $ui.ChatInput.Focus() | Out-Null }
    }
    foreach ($x in @(@($ui.ChatFindPrev, 'E70E', 'Previous (Shift+Enter)'), @($ui.ChatFindNext, 'E70D', 'Next (Enter)'), @($ui.ChatFindClose, 'E711', 'Close (Esc)'))) { Set-IconBtn $x[0] $x[1]; $x[0].Padding = '6,4'; $x[0].Margin = '2,0,0,0'; $x[0].ToolTip = $x[2]; $x[0].Content.FontSize = 11 }
    $ui.ChatFindPrev.Add_Click({ Step-Find -1 }); $ui.ChatFindNext.Add_Click({ Step-Find 1 }); $ui.ChatFindClose.Add_Click({ Show-ChatFind $false })
    $ui.ChatFindBox.Add_TextChanged({ Find-InChat $ui.ChatFindBox.Text })
    $ui.ChatFindBox.Add_PreviewKeyDown({ param($s_, $e_)
            if ($e_.Key -eq 'Return') { $e_.Handled = $true; Step-Find $(if ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Shift) { -1 } else { 1 }) }
            elseif ($e_.Key -eq 'Escape') { $e_.Handled = $true; Show-ChatFind $false } })
    function New-Conversation { $cs = Get-ChatState; if ((Get-ChatSession) -or ($cs -and $cs.busy)) { New-ChatTab } else { Show-ChatMenu $false; Show-ChatStart; $ui.ChatInput.Focus() | Out-Null } }
    $ui.ChatTitle.ToolTip = 'Double-click to rename this chat'; $ui.ChatTitle.Add_MouseLeftButtonDown({ param($s_, $e_) if ($e_.ClickCount -eq 2) { $e_.Handled = $true; Start-RenameChat $script:chatDir } })
    $ui.ChatNew.Add_Click({ New-Conversation }); $ui.ChatNew.ToolTip = 'New conversation in a new tab (Ctrl+T)'
    $ui.ChatSend.Add_Click({ if ($script:sendBusy) { Send-ChatCmd @{ cmd = 'stop' } } else { Send-Chat $ui.ChatInput.Text } })
    $ui.ChatInput.Add_TextChanged({ $ui.ChatHint.Visibility = if ($ui.ChatInput.Text -or $script:attach.Count) { 'Collapsed' } else { 'Visible' } })
    # Enter sends (Shift+Enter: a new line); Up in an empty box: the last message again; Ctrl+V: a screenshot or files
    # from Explorer go with the message (text pastes as usual)
    $ui.ChatInput.Add_PreviewKeyDown({ param($s_, $e_)
            $mods = [Windows.Input.Keyboard]::Modifiers
            if ($e_.Key -eq 'Return' -and -not ($mods -band [Windows.Input.ModifierKeys]::Shift)) { $e_.Handled = $true; if (-not $script:sendBusy -or $script:editing) { Send-Chat $ui.ChatInput.Text } }
            elseif ($e_.Key -eq 'Escape' -and $script:editing) { $e_.Handled = $true; Stop-Edit; $ui.ChatInput.Text = ''; Clear-Attach }
            elseif ($e_.Key -eq 'Up' -and -not $ui.ChatInput.Text -and $script:lastSent[$script:chatDir]) { $e_.Handled = $true; $ui.ChatInput.Text = $script:lastSent[$script:chatDir]; $ui.ChatInput.CaretIndex = $ui.ChatInput.Text.Length }
            elseif ($e_.Key -eq 'V' -and $mods -eq [Windows.Input.ModifierKeys]::Control) {
                try {
                    if ([Windows.Clipboard]::ContainsFileDropList()) { $e_.Handled = $true; Add-Attach @([Windows.Clipboard]::GetFileDropList()) }
                    elseif ([Windows.Clipboard]::ContainsImage()) { $e_.Handled = $true; $f = Save-ClipImage; if ($f) { Add-Attach $f } }
                } catch { Say "Couldn't paste that: $($_.Exception.Message)" }
            } })
    # files dropped on the chat (from Explorer; Windows doesn't let a program without admin rights drop onto one with
    # them - then Ctrl+C the file in Explorer and Ctrl+V it here)
    $ui.ChatPanel.Add_PreviewDragOver({ param($s_, $e_) if ($e_.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { $e_.Effects = 'Copy'; $e_.Handled = $true } })
    $ui.ChatPanel.Add_PreviewDragEnter({ param($s_, $e_) if ($e_.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { $e_.Effects = 'Copy'; $e_.Handled = $true } })
    $ui.ChatPanel.Add_PreviewDrop({ param($s_, $e_) if ($e_.Data.GetDataPresent([Windows.DataFormats]::FileDrop)) { $e_.Handled = $true; Add-Attach @($e_.Data.GetData([Windows.DataFormats]::FileDrop)) } })
    # the chat scrolls as one (the messages are documents that would keep the wheel to themselves); Ctrl+wheel: text size
    $script:chatZoom = 1.0; try { if ($z_ = Get-AppLast 'chatzoom') { $script:chatZoom = [Math]::Min(1.6, [Math]::Max(0.8, [double]$z_)) } } catch {}
    function Set-ChatZoom([double]$z) {
        $script:chatZoom = [Math]::Round([Math]::Min(1.6, [Math]::Max(0.8, $z)), 2)
        $ui.ChatList.LayoutTransform = New-Object Windows.Media.ScaleTransform ($script:chatZoom, $script:chatZoom)
        if (-not $Test) { Save-AppLast }
    }
    if ($script:chatZoom -ne 1) { $ui.ChatList.LayoutTransform = New-Object Windows.Media.ScaleTransform ($script:chatZoom, $script:chatZoom) }
    $ui.ChatScroll.Add_PreviewMouseWheel({ param($s_, $e_)
            $e_.Handled = $true
            if ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) { Set-ChatZoom ($script:chatZoom + $(if ($e_.Delta -gt 0) { 0.1 } else { -0.1 })); Say "Chat text size: $([int]($script:chatZoom * 100))% (Ctrl+0: back to normal)" }
            else { $ui.ChatScroll.ScrollToVerticalOffset($ui.ChatScroll.VerticalOffset - $e_.Delta) } })
    $ui.NowBar.Add_MouseLeftButtonUp({ if ($this.Tag -eq 'chat' -and $ai) { if ($script:nowChat -and $script:nowChat -ne $script:chatDir) { $script:chatDir = $script:nowChat }; Show-Chat $true } else { Show-Page 'Activity' 'Checks' } })

    # Ask Claude, top right (with the AI assistant on): the chat, beside whatever page is open
    $ui.AiPill.Style = $win.FindResource('Btn'); $ui.AiPill.Margin = '0'; $ui.AiPill.Padding = '14,6'; $ui.AiPill.ToolTip = 'Chat with Claude - it can look at this PC and fix things'
    $aiSp = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal' }
    [void]$aiSp.Children.Add((New-Glyph 'E99A' 14 $brush.Accent)); [void]$aiSp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = 'Ask Claude'; Margin = '8,0,0,0'; VerticalAlignment = 'Center' }))
    $ui.AiPill.Content = $aiSp
    $ui.AiPill.Add_Click({ Show-Chat ($ui.ChatPanel.Visibility -ne 'Visible') })

    # --- search everywhere (Ctrl+K or Ctrl+F, or the search button top right): pages, every optimization on the Status tab,
    # every switch in Settings and the main actions - type a few letters, Enter (or a click) goes there
    function Get-SearchIndex {
        $ix = New-Object Collections.ArrayList
        $add = { param($t, $sub, $glyph, $go) [void]$ix.Add(@{ Title = $t; Sub = $sub; Glyph = $glyph; Go = $go }) }
        foreach ($pg in @(@('Home', 'Home', 'E80F'), @('Status', 'Status', 'EA18'), @('Activity/Checks', 'Checks - what the maintenance did', 'E81C'), @('Activity/Trends', 'Trends - charts over time', 'E9D9'),
                @('Activity/Alerts', 'Alerts', 'EA8F'), @('Settings/General', 'Settings - general', 'E713'), @('Settings/Windows', 'Settings - what Messiah changes in Windows', 'E713'), @('Settings/Tools', 'Tools - updates, repair, drivers, BIOS, install USB', 'E90F'))) {
            & $add $pg[1] 'Page' $pg[2] ([scriptblock]::Create("Show-Page $(($pg[0] -split '/' | ForEach-Object { "'$_'" }) -join ' ')"))
        }
        foreach ($r in @((Get-StatusModel).Rows)) {
            $q_ = $r.Title.Replace("'", "''")
            & $add $r.Title "Status - $($r.State)" 'EA18' ([scriptblock]::Create("`$script:stFilter = 'all'; `$script:stSearch = '$q_'; Show-Page 'Status'"))
        }
        $twc = Get-TweakCatalog; foreach ($g in $twc.Keys) { foreach ($o in $twc[$g]) { & $add $o[1] "Settings > Windows - $g" 'E713' { Show-Page 'Settings' 'Windows' } } }
        foreach ($t in 'AI assistant (Claude)', "Open $name when I log in", 'Show alerts in the corner', 'Restart at night to finish updates', 'Microsoft Defender skips my game folders',
            'NVIDIA driver settings for games', 'Undo a graphics driver that crashes', 'Settings backup - back up now or restore', 'Show technical names in Status details') { & $add $t 'Settings > General' 'E713' { Show-Page 'Settings' 'General' } }
        foreach ($t in 'Repair Messiah', 'Undo the last update', 'Go back to the previous graphics driver', 'Motherboard and BIOS', 'Make an install USB', 'Uninstall Messiah', 'Take the tour again') { & $add $t 'Settings > Tools' 'E90F' { Show-Page 'Settings' 'Tools' } }
        & $add 'Run maintenance now' 'Action' 'E768' { & $act.RunMaint }
        & $add 'Check every optimization now' 'Action' 'E72C' { Show-Page 'Status'; & $act.CheckNow }
        & $add 'Copy a report for help' 'Action - a summary to paste to whoever helps you' 'E8C8' { & $act.CopyReport }
        & $add 'Preview what Messiah would change' 'Action' 'E7B3' { & $act.PreviewTweaks }
        & $add 'Take the tour' 'Action - a short walk through the app' 'E8F1' { Show-Tour 0 }
        if ($script:ai) { & $add 'Chat with Claude' 'Action' 'E99A' { Show-Chat $true } }
        , $ix.ToArray()
    }
    # the box: over the window, near the top; Up/Down choose, Enter goes, Esc (or a click outside) closes
    $root = $ui.TopBar.Parent
    $sOver = New-Object Windows.Controls.Grid -Property @{ Visibility = 'Collapsed'; Background = (New-Tint $brush.Bg 0x99) }
    [Windows.Controls.Grid]::SetRowSpan($sOver, 3); [Windows.Controls.Panel]::SetZIndex($sOver, 50)
    $sCard = New-Object Windows.Controls.Border -Property @{ Width = 600; MaxHeight = 520; VerticalAlignment = 'Top'; HorizontalAlignment = 'Center'; Margin = '24,70,24,24'; Padding = '14'; CornerRadius = 12; Background = $brush.Card; BorderBrush = $brush.Border; BorderThickness = 1 }
    $sCard.Effect = New-Object Windows.Media.Effects.DropShadowEffect -Property @{ BlurRadius = 30; ShadowDepth = 6; Opacity = 0.35; Color = [Windows.Media.Colors]::Black }
    $sDock = New-Object Windows.Controls.DockPanel
    $sTop = New-Object Windows.Controls.DockPanel -Property @{ Margin = '4,0,4,8' }; [Windows.Controls.DockPanel]::SetDock($sTop, 'Top')
    $sg_ = New-Glyph 'E721' 16 $brush.Sub; $sg_.Margin = '0,0,10,0'; [Windows.Controls.DockPanel]::SetDock($sg_, 'Left'); [void]$sTop.Children.Add($sg_)
    $sBox = New-Object Windows.Controls.TextBox -Property @{ FontSize = 16; Background = [Windows.Media.Brushes]::Transparent; BorderThickness = 0; Foreground = $brush.Text; CaretBrush = $brush.Text; Padding = '0,4' }
    [Windows.Automation.AutomationProperties]::SetName($sBox, 'Search Messiah')
    [void]$sTop.Children.Add($sBox); [void]$sDock.Children.Add($sTop)
    $sHint = New-Text 'Type to search pages, optimizations, settings and actions - Enter opens, Esc closes' $brush.Sub 12 'Normal' '4,0,4,8'; [Windows.Controls.DockPanel]::SetDock($sHint, 'Top'); [void]$sDock.Children.Add($sHint)
    $sList = New-Object Windows.Controls.StackPanel; $sScroll = New-Object Windows.Controls.ScrollViewer -Property @{ VerticalScrollBarVisibility = 'Auto'; Content = $sList }
    [void]$sDock.Children.Add($sScroll); $sCard.Child = $sDock; [void]$sOver.Children.Add($sCard)
    [Windows.Controls.Grid]::SetColumnSpan($sOver, 1); [void]$root.Children.Add($sOver)
    $script:sSel = 0; $script:sHits = @()
    function Update-Search {
        $q = $sBox.Text.Trim(); $words = @($q -split '\s+' | Where-Object { $_ })
        $script:sHits = @(if ($words) { $script:sIndex | Where-Object { $h_ = "$($_.Title) $($_.Sub)"; -not ($words | Where-Object { $h_.IndexOf($_, [StringComparison]::OrdinalIgnoreCase) -lt 0 }) } |
                Sort-Object { if ($_.Title.StartsWith($q, [StringComparison]::OrdinalIgnoreCase)) { 0 } elseif ($_.Title.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0) { 1 } else { 2 } } | Select-Object -First 9 } else { $script:sIndex | Where-Object { $_.Sub -eq 'Page' -or $_.Sub -like 'Action*' } })
        if ($script:sSel -ge $script:sHits.Count) { $script:sSel = 0 }
        $sList.Children.Clear(); $i = 0
        foreach ($h in $script:sHits) {
            $row = New-Object Windows.Controls.Border -Property @{ CornerRadius = 8; Padding = '10,7'; Cursor = 'Hand'; Tag = $i; Background = $(if ($i -eq $script:sSel) { $brush.CardHover } else { [Windows.Media.Brushes]::Transparent }) }
            $rp = New-Object Windows.Controls.DockPanel
            $gl = New-Glyph $h.Glyph 14 $brush.Accent; $gl.Margin = '0,0,12,0'; [Windows.Controls.DockPanel]::SetDock($gl, 'Left'); [void]$rp.Children.Add($gl)
            $tx = New-Object Windows.Controls.StackPanel; [void]$tx.Children.Add((New-Text $h.Title $brush.Text 14 'Normal' '0')); [void]$tx.Children.Add((New-Text $h.Sub $brush.Sub 12 'Normal' '0'))
            [void]$rp.Children.Add($tx); $row.Child = $rp
            [Windows.Automation.AutomationProperties]::SetName($row, "$($h.Title), $($h.Sub)")
            $row.Add_MouseEnter({ $script:sSel = [int]$this.Tag; foreach ($c_ in $sList.Children) { $c_.Background = if ([int]$c_.Tag -eq $script:sSel) { $brush.CardHover } else { [Windows.Media.Brushes]::Transparent } } })
            $row.Add_MouseLeftButtonUp({ $script:sSel = [int]$this.Tag; Invoke-SearchHit })
            [void]$sList.Children.Add($row); $i++
        }
        if (-not $script:sHits) { [void]$sList.Children.Add((New-Text 'Nothing found - try another word.' $brush.Sub 13 'Normal' '10,6,0,6')) }
    }
    function Invoke-SearchHit { $h = $script:sHits[$script:sSel]; if (-not $h) { return }; Show-Search $false; try { & $h.Go } catch { Say "Couldn't open that: $($_.Exception.Message)" } }
    function Show-Search([bool]$on) {
        if ($on) { $script:sIndex = Get-SearchIndex; $sBox.Text = ''; $script:sSel = 0; Update-Search; $sOver.Visibility = 'Visible'; [void]$sBox.Focus() }
        else { $sOver.Visibility = 'Collapsed' }
    }
    $sBox.Add_TextChanged({ $script:sSel = 0; Update-Search })
    $sBox.Add_PreviewKeyDown({ param($s_, $e_)
            switch ($e_.Key) {
                'Down' { $script:sSel = [Math]::Min($script:sSel + 1, [Math]::Max(0, $script:sHits.Count - 1)); Update-Search; $e_.Handled = $true }
                'Up' { $script:sSel = [Math]::Max(0, $script:sSel - 1); Update-Search; $e_.Handled = $true }
                'Return' { Invoke-SearchHit; $e_.Handled = $true }
                'Escape' { Show-Search $false; $e_.Handled = $true }
            } })
    $sOver.Add_MouseLeftButtonDown({ param($s_, $e_) if ($e_.OriginalSource -eq $sOver) { Show-Search $false } })
    # the button, top right (left of Ask Claude)
    $sBtn = New-Btn 'E721' 'Search' { Show-Search $true }; $sBtn.ToolTip = 'Search everything (Ctrl+K)'; $sBtn.Margin = '0,0,8,0'; $sBtn.Padding = '12,6'
    [Windows.Automation.AutomationProperties]::SetName($sBtn, 'Search everything')
    [void]$ui.TopBar.Children.Remove($ui.AiPill)
    $tr_ = New-Object Windows.Controls.StackPanel -Property @{ Orientation = 'Horizontal'; HorizontalAlignment = 'Right'; VerticalAlignment = 'Center' }
    [Windows.Controls.Grid]::SetColumn($tr_, 2); [void]$tr_.Children.Add($sBtn); [void]$tr_.Children.Add($ui.AiPill); [void]$ui.TopBar.Children.Add($tr_)
    $script:searchBtn = $sBtn
    # keys for the whole window: Ctrl+K / Ctrl+F search, Esc closes the search or the tour
    $win.Add_PreviewKeyDown({ param($s_, $e_)
            $ctrl = [Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control
            $shift = [Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Shift
            $chatOn = $script:ai -and $ui.ChatPanel.Visibility -eq 'Visible'
            if ($ctrl -and $e_.Key -eq 'F' -and $chatOn -and $ui.ChatPanel.IsKeyboardFocusWithin) { Show-ChatFind $true; $e_.Handled = $true }   # (in the chat: find in the conversation)
            elseif ($ctrl -and $e_.Key -in 'K', 'F' -and $ui.ChatInput.IsKeyboardFocused -eq $false) { Show-Search $true; $e_.Handled = $true }
            # the chat's tabs: Ctrl+T new, Ctrl+W close (the first chat: hides the chat), Ctrl+Tab / Ctrl+Shift+Tab switch;
            # Ctrl+0 normal text size
            elseif ($ctrl -and $e_.Key -eq 'T' -and $script:ai) { $e_.Handled = $true; if (-not $chatOn) { Show-Chat $true }; New-Conversation }
            elseif ($ctrl -and $e_.Key -eq 'W' -and $chatOn) { $e_.Handled = $true; if ($script:chatDir -eq "$cl\chat") { Show-Chat $false } else { Close-ChatTab $script:chatDir } }
            elseif ($ctrl -and $e_.Key -eq 'Tab' -and $chatOn) {
                $e_.Handled = $true; $ds = @(Get-ChatDirs)
                if ($ds.Count -gt 1) { $i = [Array]::IndexOf($ds, $script:chatDir); Switch-Chat $ds[(($i + $(if ($shift) { -1 } else { 1 })) + $ds.Count) % $ds.Count] }
            }
            elseif ($ctrl -and $e_.Key -in 'D0', 'NumPad0' -and $chatOn) { $e_.Handled = $true; Set-ChatZoom 1; Say 'Chat text size: normal.' }
            elseif ($e_.Key -eq 'Escape' -and $script:tourOver -and $script:tourOver.Visibility -eq 'Visible') { Show-Tour -1; $e_.Handled = $true } })

    # --- "keep this value" (a Status row's history): the owner's own value for one setting, kept from then on - tweaks.ps1
    # reads "keep.<key>\<name>=<value>" from kit-options.txt and holds that value instead of Messiah's ("(not set)": none)
    function Get-Keeps { $k_ = @{}; foreach ($l in @(Get-Content "$cl\kit-options.txt" -ErrorAction SilentlyContinue)) { if ($l -match '^\s*keep\.(.+?)=(.*)$') { $k_[$Matches[1].Trim()] = $Matches[2] } }; $k_ }
    function Set-Keep([string]$Full, $Value) {   # $Value $null: Messiah manages it again
        $f = "$cl\kit-options.txt"; $rx = '^\s*keep\.' + [regex]::Escape($Full) + '\s*='
        $lines = @(Get-Content $f -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch $rx }) + @(if ($null -ne $Value) { "keep.$Full=$Value" })
        [IO.File]::WriteAllLines($f, [string[]]$lines)
    }
    $act.KeepValue = { param($full, $old)
        $nm = Get-PlainName $full
        if ([Windows.MessageBox]::Show("Keep `"$nm`" at $(if ($old -eq '(not set)') { 'Windows'' default (not set)' } else { "'$old'" })?`n`nMessiah puts that value back now and keeps it that way after updates, instead of its own. Its row's details have a link to hand it back to Messiah.", 'Keep this value', 'OKCancel', 'Question') -ne 'OK') { return }
        Set-Keep $full $old; & $act.CheckNow; Say "Kept - $nm stays the way you had it." }
    $act.ManageAgain = { param($full) Set-Keep $full $null; & $act.CheckNow; Say "$(Get-PlainName $full) is Messiah's to keep in place again." }

    # --- "Copy a report for help": what someone helping needs, as text on the clipboard - versions, hardware, every
    # optimization that isn't plain green, what needs the owner, the last check. No names, paths or e-mail addresses.
    $act.CopyReport = {
        $sm = Get-StatusModel
        $os = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
        $hw = Get-Cached 'hw' 3600 { "$((Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue | Select-Object -First 1).Name.Trim()); $((@(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object Status -eq 'OK' | ForEach-Object Name)) -join ', '); $([Math]::Round(((Get-CimInstance Win32_PhysicalMemory -ErrorAction SilentlyContinue | Measure-Object Capacity -Sum).Sum) / 1GB)) GB RAM" }
        $L = New-Object Collections.Generic.List[string]
        $L.Add("Messiah report - $((Get-Date).ToString('yyyy-MM-dd HH:mm'))")
        $kv_ = "$(Get-Content 'C:\PCSetupKit\kit-version.txt' -TotalCount 1 -ErrorAction SilentlyContinue)".Trim(); $L.Add("Messiah $(if ($kv_) { $kv_ } else { '(version unknown)' }); Windows $($os.DisplayVersion) build $($os.CurrentBuild).$($os.UBR)")
        $L.Add("PC: $hw"); $L.Add('')
        $L.Add("STATUS: $(if ($sm.Warn) { "$($sm.Warn) need$(if ($sm.Warn -eq 1) { 's' }) a look" } else { "all $($sm.Ok) in place" })$(if ($sm.At) { " (checked $($sm.At.ToString('yyyy-MM-dd HH:mm')))" })")
        foreach ($r in @($sm.Rows | Where-Object { $_.Level -eq 'warn' -or $_.State -like 'Put back*' })) { $L.Add("  [$(if ($r.Level -eq 'warn') { '!' } else { 'fixed' })] $($r.Title): $($r.State)$(if ($r.Detail) { " - $($r.Detail)" })") }
        $offs = @($sm.Rows | Where-Object Level -eq 'dim' | ForEach-Object Title); if ($offs) { $L.Add("  Off by choice: $($offs -join '; ')") }
        $keeps = Get-Keeps; if ($keeps.Count) { $L.Add("  Kept by the owner: $(@($keeps.Keys | ForEach-Object { Get-PlainName $_ }) -join '; ')") }
        $todo = @(Get-Content "$cl\maint-todo.txt" -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
        $L.Add(''); $L.Add("NEEDS THE OWNER: $(if ($todo) { '' } else { 'nothing' })"); foreach ($t in $todo) { $L.Add("  - $t") }
        $L.Add(''); $L.Add('LAST CHECK:'); foreach ($t in @(Get-Content "$cl\maint-report.txt" -Encoding UTF8 -ErrorAction SilentlyContinue)) { $L.Add("  $t") }
        $txt = ($L -join "`r`n")
        foreach ($pr in @(@($env:USERPROFILE, '%USERPROFILE%'), @($env:USERNAME, '<user>'), @($env:COMPUTERNAME, '<pc>'))) { if ($pr[0] -and $pr[0].Length -ge 3) { $txt = [regex]::Replace($txt, [regex]::Escape($pr[0]), $pr[1], 'IgnoreCase') } }
        $txt = [regex]::Replace($txt, '[\w.+-]+@[\w-]+\.[\w.]+', '<email>')
        if ($Test) { return $txt }
        [Windows.Clipboard]::SetText($txt); Say 'Copied - paste it into a message to whoever helps you. No names, paths or e-mail addresses are in it.'
    }

    # --- the tour: once, after setup's Welcome (or Settings > Tools > Take the tour) - a card at the bottom walks through
    # the tabs, each opened behind it
    $tourSteps = @(
        @('Home', $null, 'Home - your PC at a glance', 'The ring says whether anything needs you; the tiles under it open the details. Most days it just says all good.'),
        @('Status', $null, 'Status - every optimization, kept in place', 'Green means in place. Click any row for what it does and its history; a row that needs a look has its fix-it button. Filters and search are on top.'),
        @('Activity', 'Checks', 'Activity - what Messiah did', 'What each check found and fixed, charts of how the PC is doing over time, and alerts - Messiah never pops up, it writes here.'),
        @('Settings', 'Windows', 'Settings - yours to choose', 'Every change Messiah makes in Windows has its own switch. Tools has repairs, drivers, the BIOS and the install USB.'),
        @('Status', $null, 'Search everything', 'Press Ctrl+K anywhere (or the Search button top right) to jump to any page, setting or optimization.'))
    $script:tourOver = New-Object Windows.Controls.Border -Property @{ Visibility = 'Collapsed'; VerticalAlignment = 'Bottom'; HorizontalAlignment = 'Center'; MaxWidth = 620; Margin = '24,0,24,24'; Padding = '20,16'; CornerRadius = 12; Background = $brush.Toast; BorderBrush = $brush.Accent; BorderThickness = 1 }
    $script:tourOver.Effect = New-Object Windows.Media.Effects.DropShadowEffect -Property @{ BlurRadius = 30; ShadowDepth = 6; Opacity = 0.4; Color = [Windows.Media.Colors]::Black }
    [Windows.Controls.Grid]::SetRow($script:tourOver, 2); [Windows.Controls.Panel]::SetZIndex($script:tourOver, 40); [void]$root.Children.Add($script:tourOver)
    function Show-Tour([int]$i) {
        if ($i -lt 0 -or $i -ge $tourSteps.Count) { $script:tourOver.Visibility = 'Collapsed'; Set-Opt 'tour' 'done'; return }
        $st_ = $tourSteps[$i]; Show-Page $st_[0] $st_[1]
        $sp = New-Object Windows.Controls.StackPanel
        $hd = New-Object Windows.Controls.DockPanel
        $n_ = New-Text "$($i + 1) of $($tourSteps.Count)" $brush.Sub 12 'Normal' '12,4,0,0'; [Windows.Controls.DockPanel]::SetDock($n_, 'Right'); [void]$hd.Children.Add($n_)
        $tt = New-Text $st_[2] $brush.Text 17 'SemiBold' '0'; $tt.FontFamily = $display; [void]$hd.Children.Add($tt); [void]$sp.Children.Add($hd)
        [void]$sp.Children.Add((New-Text $st_[3] $brush.Sub 13 'Normal' '0,6,0,12'))
        $bp = New-Object Windows.Controls.WrapPanel
        $bt = New-Btn 'E711' 'Skip the tour' { Show-Tour -1 }; [void]$bp.Children.Add($bt)
        if ($i -gt 0) { $bb = New-Btn 'E72B' 'Back' { Show-Tour ([int]$this.Uid) }; $bb.Uid = "$($i - 1)"; [void]$bp.Children.Add($bb) }
        $bn = New-Btn $(if ($i -eq $tourSteps.Count - 1) { 'E73E' } else { 'E72A' }) $(if ($i -eq $tourSteps.Count - 1) { 'Done' } else { 'Next' }) { Show-Tour ([int]$this.Uid) } -Accent; $bn.Uid = "$(if ($i -eq $tourSteps.Count - 1) { -1 } else { $i + 1 })"; [void]$bp.Children.Add($bn)
        [void]$sp.Children.Add($bp); $script:tourOver.Child = $sp; $script:tourOver.Visibility = 'Visible'; [void]$bn.Focus()
    }
    $act.Tour = { Show-Tour 0 }

    # --- what's new after an update (whats-new.json, written by kit-update.ps1): a card on Home until "Got it", 3 weeks at most
    # a game running right now (game-check.ps1 -NoLearn: this window in front never counts as one), read every 30 s at most
    function Get-Playing {
        if ($env:PCKIT_GAME_TEST) { return $env:PCKIT_GAME_TEST }
        if ($env:PCKIT_IN_TESTS -or -not (Test-Path "$cl\game-check.ps1")) { return }
        "$(Get-Cached 'game' 30 { & "$cl\game-check.ps1" -NoLearn })".Trim()
    }
    function Get-WhatsNew {
        $w = Read-Json "$cl\whats-new.json"; if (-not $w -or -not $w.version) { return }
        $d_ = [datetime]::MinValue; if ([datetime]::TryParse("$($w.date)", [ref]$d_) -and $d_ -lt (Get-Date).AddDays(-21)) { return }
        if ((Get-Opt 'newsseen' '') -eq "$($w.version)") { return }
        $w
    }
    $script:ai = [bool]$ai
    Update-Nav
    if ($Page -eq 'Chat' -and $ai -and -not $Test) { $win.Add_ContentRendered({ Show-Chat $true }) }   # -Page Chat: open with the chat (the tray's Ask Claude)

    if ($Test) {
        "WINDOW: $($win.Title)"
        # the chat's messages: selectable documents, links only to what exists, copy buttons, attachments
        $ui.ChatList.Children.Clear()
        Add-ChatItem 'text' "## Head`nSee **$env:SystemRoot** and ``$env:SystemRoot\System32\notepad.exe`` or https://example.com/a.`nNot a link: ``C:\no\such\file.txt```n```````n`$x = 1`n```````n- point"
        Add-ChatItem 'user' "Look at this`nAttached: $env:SystemRoot\win.ini"
        Add-ChatItem 'user' 'Just words'; "CHAT PLAIN: $(@($ui.ChatList.Children)[-1].Children[1].Child.Document.Blocks.Count) block"
        $win.Measure((New-Object Windows.Size 900, 900)); $ui.ChatList.Measure((New-Object Windows.Size 440, 5000))
        $all_ = @($ui.ChatList.Children)
        $doc_ = $all_[0].Children[0].Document; $lk = @(); $codeBox = 0
        foreach ($bl in $doc_.Blocks) { if ($bl -is [Windows.Documents.Paragraph]) { foreach ($in in $bl.Inlines) { if ($in -is [Windows.Documents.Hyperlink]) { $lk += $in.Tag } elseif ($in -is [Windows.Documents.Span]) { foreach ($i2 in $in.Inlines) { if ($i2 -is [Windows.Documents.Hyperlink]) { $lk += $i2.Tag } } } } } elseif ($bl -is [Windows.Documents.BlockUIContainer]) { $codeBox++ } }
        $ub = $all_[1].Children[1].Child.Document
        "CHAT: reply=$($all_[0].Children[0].GetType().Name) readonly=$($all_[0].Children[0].IsReadOnly) blocks=$($doc_.Blocks.Count) codeboxes=$codeBox code=[$(@($doc_.Blocks | Where-Object { $_ -is [Windows.Documents.BlockUIContainer] })[0].Child.Children[0].Child.Text)] copy=$($all_[0].Children[1].ToolTip)"
        "CHAT LINKS: $($lk -join ' | ')"
        "CHAT USER: blocks=$($ub.Blocks.Count) attach=$(@($ub.Blocks.LastBlock.Inlines | Where-Object { $_ -is [Windows.Documents.Hyperlink] } | ForEach-Object Tag) -join ',') width=$([int]$all_[1].Children[1].Child.MaxWidth)"
        Start-Edit "Fix this`nAttached: $env:SystemRoot\win.ini"; "CHAT EDIT: box=[$($ui.ChatInput.Text)] files=$($script:attach.Count) editing=$script:editing shown=$($ui.ChatEditing.Visibility) last=$([bool]$script:lastUser)"; Stop-Edit; $ui.ChatInput.Text = ''; Clear-Attach
        Add-ChatItem 'text' 'The **Head** again, and head once more'; Find-InChat 'head'; $n1 = $script:finds.Count; $at1 = $ui.ChatFindCount.Text; Step-Find 1; $at2 = $ui.ChatFindCount.Text
        $marked = @($script:finds | Where-Object { $_.R.GetPropertyValue([Windows.Documents.TextElement]::BackgroundProperty) }).Count; Clear-Finds
        $left = 0; foreach ($rb in @(Get-ChatDocs)) { $q_ = $rb.Document.ContentStart; while ($q_) { if ($q_.GetPointerContext('Forward') -eq 'Text' -and $q_.Parent.Background -and $q_.Parent.Background.Color -eq $findBrush.Color) { $left++ }; $q_ = $q_.GetNextContextPosition('Forward') } }
        "CHAT FIND: found=$n1 first=[$at1] next=[$at2] marked=$marked leftover=$left"
        $md_ = Join-Path $env:TEMP "dash-mode-$PID"; New-Item $md_ -ItemType Directory -Force | Out-Null; $m0 = (Get-ChatMode $md_)[0]; Set-Content "$md_\mode.txt" 'opus/high'; $m1 = (Get-ChatMode $md_)[0]; Set-Content "$md_\mode.txt" 'junk'; $m2 = (Get-ChatMode $md_)[0]; [IO.Directory]::Delete($md_, $true)
        "CHAT MODE: default=$m0 chosen=$m1 junk=$m2 button=[$($ui.ChatMode.Content.Children[1].Text)]"
        $ui.ChatList.Children.Clear()
        # a tab's own name and pin (a scratch folder, not a real chat)
        $td_ = Join-Path $env:TEMP "dash-tab-$PID"; New-Item $td_ -ItemType Directory -Force | Out-Null
        Save-ChatName $td_ '  My   build chat  '; $n1 = Get-ChatTitle $td_; $rc = "$(Get-Content "$td_\name.txt")".Trim()
        Save-ChatName $td_ ''; $n2 = Get-ChatTitle $td_
        Switch-ChatPin $td_; $p1 = Test-Path "$td_\pinned.txt"; Close-ChatTab $td_; $kept = Test-Path $td_; Switch-ChatPin $td_; $p2 = Test-Path "$td_\pinned.txt"
        "CHAT TAB: named=[$n1] remote=[$rc] cleared=[$n2] pinned=$p1 closeRefused=$kept unpinned=$(-not $p2)"
        [IO.Directory]::Delete($td_, $true)
        # the RAM stick test, each stage (made-up logs)
        $two = '2 stick(s), 32 GB in P0 CHANNEL A + P0 CHANNEL B'; $oA = '1 stick(s), 16 GB in P0 CHANNEL A'; $oB = '1 stick(s), 16 GB in P0 CHANNEL B'
        $base = @("2026-10-05 09:54 | start | $two", "2026-10-10 11:30 | crash | $two", "2026-10-10 11:30 | start | $two")
        $st_ = { param($n, $s, [int]$c) @(1..$n | ForEach-Object { "2026-10-13 10:$('{0:d2}' -f $_) | start | $s" }) + @(if ($c) { 1..$c | ForEach-Object { "2026-10-14 10:0$_ | crash | $s" } }) }
        foreach ($case in @(
                @('not started', $base, $two), @('A running', ($base + (& $st_ 3 $oA 0)), $oA), @('A clean', ($base + (& $st_ 10 $oA 0)), $oA),
                @('A crashed', ($base + (& $st_ 2 $oA 1)), $oA), @('B running', ($base + (& $st_ 10 $oA 0) + (& $st_ 4 $oB 0)), $oB),
                @('A bad', ($base + (& $st_ 2 $oA 1) + (& $st_ 10 $oB 0)), $oB), @('both bad', ($base + (& $st_ 2 $oA 1) + (& $st_ 3 $oB 1)), $oB),
                @('both clean', ($base + (& $st_ 10 $oA 0) + (& $st_ 10 $oB 0)), $oB), @('back too soon', ($base + (& $st_ 3 $oA 0)), $two))) {
            "RAMTEST $($case[0]): $(@(Get-RamTest $case[1] $case[2]) | Where-Object { $_.Level -ne 'dim' } | ForEach-Object { ($_.Text -split '[:.]')[0] })"
        }
        foreach ($p in @($pages.Keys)) {
            foreach ($s in @(if ($subPages.Contains($p)) { $subPages[$p] } else { '' })) {
                $script:onPage = $p; if ($s) { $script:sub[$p] = $s }; Update-View -Force
                "PAGE: $($ui.PageTitle.Text)$(if ($s) { " / $s" })"; if ($script:pageError) { "PAGE ERROR: $script:pageError" }
                foreach ($card in @($ui.Content.Children | ForEach-Object { if ($_ -is [Windows.Controls.Primitives.UniformGrid] -or $_ -is [Windows.Controls.WrapPanel]) { $_.Children } else { $_ } })) {
                    if ($card -is [Windows.Controls.TextBlock]) { if ($card.Visibility -eq 'Visible') { "NOTE: $($card.Text)" }; continue }
                    if ("$($card.Tag)" -eq 'filters') { "FILTERS: $(@($card.Child.Children[0].Child.Children | ForEach-Object { "$($_.Content)$(if ($_.IsChecked) { '*' })" }) -join ' | ')"; continue }
                    if ($card.Visibility -ne 'Visible') { continue }
                    $all = @($card.Child.Children)
                    $chart = $all | Where-Object { "$($_.Tag)" -like 'CHART:*' } | Select-Object -First 1
                    if ($chart) { "  $($chart.Tag)"; continue }
                    $head = $all[0]; if ($head -is [Windows.Controls.StackPanel] -and $head.Orientation -eq 'Horizontal') { "CARD: $(@($head.Children)[-1].Text)"; $all = $all | Select-Object -Skip 1 } else { 'CARD: -' }
                    foreach ($el in $all) {
                        if ($el -is [Windows.Controls.TextBlock]) { "  $($el.Text)" }
                        elseif ($el -is [Windows.Controls.WrapPanel]) { "  BUTTONS: $(@($el.Children | ForEach-Object { $_.ToolTip }) -join ' | ')" }
                        elseif ($el -is [Windows.Controls.Grid] -and $el.RowDefinitions.Count) { $t = @($el.Children | ForEach-Object Text); for ($i = 0; $i -lt $t.Count; $i += 2) { "  $($t[$i]): $($t[$i + 1])" } }
                        else {   # a row: its text (status icons left out); a to-do row's text sits one level down, its buttons too
                            $tb = @($el.Children | ForEach-Object { if ($_ -is [Windows.Controls.TextBlock]) { $_ } elseif ($_.Children) { $_.Children | Where-Object { $_ -is [Windows.Controls.TextBlock] } } } | Where-Object { "$($_.Tag)" -ne 'icon' -and $_.Visibility -eq 'Visible' } | ForEach-Object Text)
                            "  $($tb -join ' / ')"
                            $bp = @($el.Children | ForEach-Object { $_.Children } | Where-Object { $_ -is [Windows.Controls.WrapPanel] })
                            foreach ($w in $bp) { "    ROW BUTTONS: $(@($w.Children | ForEach-Object { $_.ToolTip }) -join ' | ')" }
                            # a Status row's details (behind a click): its lines, and its buttons
                            foreach ($mb in @($el.Children | ForEach-Object { $_.Children } | Where-Object { "$($_.Tag)" -eq 'more' })) {
                                "    MORE: $(@($mb.Child.Children | ForEach-Object { if ($_ -is [Windows.Controls.TextBlock]) { (@($_.Inlines | ForEach-Object Text) -join '').Trim() } else { "[$($_.ToolTip)]" } }) -join ' | ')" }
                        }
                    }
                }
            }
        }
        "NAV: $(@($pages.Keys) -join ' | ')"
        if ($env:PCKIT_REPORT_TEST) { "REPORT: $((& $act.CopyReport) -replace "?
", ' // ')" }   # (the help report's text, for tests)
        return
    }
    $ui.Scroll.Add_SizeChanged({ Update-Columns })
    $timer = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromSeconds(10) }
    $timer.Add_Tick({ try { Update-View } catch {} })
    $win.Add_SizeChanged({ Update-Layout })
    # the size it had last time (on a screen that's still there), else one that suits this screen
    try { Add-Type -AssemblyName System.Windows.Forms } catch {}
    $pa = [Windows.SystemParameters]::WorkArea
    $va = New-Object Windows.Rect ([Windows.SystemParameters]::VirtualScreenLeft), ([Windows.SystemParameters]::VirtualScreenTop), ([Windows.SystemParameters]::VirtualScreenWidth), ([Windows.SystemParameters]::VirtualScreenHeight)
    $pl = "$(Get-Content "$cl\app-window-place.txt" -ErrorAction SilentlyContinue)" -split ','
    $r = if ($pl.Count -ge 5) { try { New-Object Windows.Rect ([double]$pl[0]), ([double]$pl[1]), ([double]$pl[2]), ([double]$pl[3]) } catch { $null } }
    if ($r -and $va.Contains((New-Object Windows.Point ($r.Left + 80), ($r.Top + 16))) -and $r.Width -ge $win.MinWidth -and $r.Height -ge $win.MinHeight) {
        $win.Left = $r.Left; $win.Top = $r.Top; $win.Width = $r.Width; $win.Height = $r.Height
        if ($pl[4] -eq 'max') { $win.WindowState = 'Maximized' }
    } else {
        $win.Width = [Math]::Max($win.MinWidth, [Math]::Min($pa.Width, [Math]::Min(1400, [Math]::Max(760, $pa.Width * 0.7))))
        $win.Height = [Math]::Max($win.MinHeight, [Math]::Min($pa.Height, [Math]::Min(1000, [Math]::Max(560, $pa.Height * 0.86))))
        $win.Left = $pa.Left + ($pa.Width - $win.Width) / 2; $win.Top = $pa.Top + ($pa.Height - $win.Height) / 2
    }
    $win.Add_SourceInitialized({ Set-WindowFit })
    $win.Add_ContentRendered({ Update-Layout })
    # the tour, once: after setup's Welcome is done (not over it), not while a game runs
    $win.Add_ContentRendered({ if ((Get-Opt 'tour' '') -ne 'done' -and (Get-Opt 'welcome' '') -ne 'pending' -and $script:onPage -ne 'Welcome' -and -not (Get-Playing)) { Show-Tour 0 } })
    $win.Add_Closing({ $b = $win.RestoreBounds; if (-not $b.IsEmpty) { "$([Math]::Round($b.Left)),$([Math]::Round($b.Top)),$([Math]::Round($b.Width)),$([Math]::Round($b.Height)),$(if ($win.WindowState -eq 'Maximized') { 'max' } else { 'normal' })" | Set-Content "$cl\app-window-place.txt" -Encoding ASCII } })
    $fast = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromMilliseconds(400) }
    $fast.Add_Tick({ try { if ($ui.ChatPanel.Visibility -eq 'Visible') { Update-Chat }; if (($script:fastN++ % 5) -eq 0) { Update-Now } } catch {} })
    $fast.Start(); $script:fastN = 0
    $timer.Start()
    [void]$win.ShowDialog()
}
catch {
    if ($Test) { throw }
    Start-Process powershell -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$cl\status.ps1`""
}
