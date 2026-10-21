using System.Collections.Generic;
using System.Linq;

namespace Messiah
{
    // every change the kit makes, by group: id, title, what it does (and what "off" means), the default for opt-in ones -
    // the Settings > Windows switches and the Status tab's details (dashboard.ps1's Get-TweakCatalog)
    static class TweakCatalog
    {
        public class Item { public string Id, Title, About, Default; }
        public static readonly (string Group, Item[] Items)[] Groups = {
            ("Speed and games", new[] {
                I("memory-integrity", "Memory integrity off", "Core isolation (VBS) costs 0-15% frame rate, mostly in games limited by the processor (little when the graphics card is the limit). Some anti-cheats check it. Off: extra protection against malicious drivers, a bit less speed."),
                I("game-bar", "Xbox Game Bar removed", "Its overlay and background capture cost frame rate. Off: it comes back. (Always kept on AMD dual-CCD X3D CPUs, which need it.)"),
                I("game-recording", "Background game recording off", "Game DVR records every game in the background. Off: recording and clips work again."),
                I("windowed-games", "Optimizations for windowed games and VRR", "Lower input lag in borderless-window games, variable refresh rate where supported."),
                I("mouse-acceleration", "Mouse acceleration off", "The same hand movement always moves the cursor the same distance - better aim."),
                I("end-task", "\"End task\" in the taskbar menu", "Right-click a frozen game on the taskbar and close it - no Task Manager needed."),
                I("sticky-keys", "Sticky Keys pop-up off", "Pressing Shift five times in a game no longer opens the Sticky Keys prompt and throws you out of fullscreen. The feature itself stays in Accessibility."),
                I("power-plan", "Best power plan", "Desktops: Ultimate Performance (Balanced on AMD's dual-CCD X3D processors, as AMD recommends). Laptops: Balanced, full speed when plugged in. Off: your own plan."),
                I("network-defaults", "Network kept at Windows' defaults", "Some \"gaming tweak\" tools turn off network throttling and Nagle's algorithm - tests show that adds lag rather than removing it. Messiah puts Windows' own values back if a tool changes them. Off: left as other tools set them."),
                I("sysmain-off", "SysMain (app prefetch) off", "Off unless you turn it on. No measured gain on an SSD - Windows' default is to keep it. Off again: back as it was.", "off"),
                I("hibernation", "Hibernation off (desktops)", "Frees disk space and gives a clean start every time. Laptops always keep it.") }),
            ("Privacy and clutter", new[] {
                I("telemetry", "Telemetry, ads and Windows AI off", "No diagnostic data, ads, suggestions, Bing in search, Copilot, Recall or the AI parts of Notepad, Paint and Edge. May break: Xbox achievements in some games and the Feedback Hub (they need the diagnostics service). Off: all of it back as it was."),
                I("bloat-apps", "Preinstalled apps removed", "News, Weather, Teams, Clipchamp, Solitaire, TikTok and the like. Off: Messiah stops removing them (reinstall any from the Microsoft Store)."),
                I("onedrive", "OneDrive removed", "Off: OneDrive comes back and can sync again."),
                I("edge-remove", "Remove Edge completely", "Off unless you turn it on. Uninstalls the Edge browser and keeps it from coming back; WebView2 - the part apps and game launchers need - stays. Your Edge bookmarks stay on the PC. Off again: Edge is reinstalled.", "off"),
                I("edge", "Edge kept out of the way", "Edge stays installed (Windows and many apps need it), but no desktop icon, no taskbar pin, no prompts, and Chrome is your browser. Off: its icon and prompts come back."),
                I("notifications-off", "All app notifications off", "Off unless you turn it on. Silences every app's pop-ups (Discord, calendar, mail) - Windows' own suggestions are off either way. Off again: they come back.", "off"),
                I("start-menu", "Start menu recommendations and Task View off", "A cleaner Start menu and taskbar."),
                I("legacy", "Old Windows parts removed", "Internet Explorer's engine, the old Media Player, WordPad, Steps Recorder and the like; PowerShell 2.0 and Recall off; reserved storage (about 7 GB) freed. Never what updates need. Off: they come back."),
                I("vendor-installers", "Razer and Logitech apps don't install by themselves", "Plugging in one of their mice or headsets no longer makes Windows install Razer Synapse or Logitech's download assistant (drivers still come). Off: they can install again."),
                I("folder-types", "File Explorer doesn't guess folder types", "Every folder opens the same way instead of Explorer reading the files first to pick a layout - big folders open faster. Off: the guessing (Pictures, Music views) comes back."),
                I("startup-clutter", "Start-up clutter off", "Vendor updaters and promo tools don't start with Windows. Off: they start again."),
                I("transparency", "Transparency effects off", "Slightly less work for the graphics card. Off: see-through Start menu and windows again.") }),
            ("Windows Update", new[] {
                I("restart-block", "No Windows Update restarts while you're signed in", "Updates still install; the restart waits for yours."),
                I("feature-delay", "Big Windows upgrades wait 45 days", "The yearly new Windows version comes once its first problems are fixed; security and monthly updates still come right away. (Windows Pro and up; Home ignores it.)") }),
        };
        static Item I(string id, string title, string about, string dflt = "on") => new Item { Id = id, Title = title, About = about, Default = dflt };
        public static readonly Dictionary<string, string> Describe = Groups.SelectMany(g => g.Items).ToDictionary(i => i.Id, i => i.About);
    }

    // the settings in plain words (the Status tab's "Checks N settings"): by registry name, or "<key>\<name>" where a name
    // means different things in different places. Settings > General > "Show technical names" shows the registry names instead.
    static class PlainNames
    {
        public static readonly Dictionary<string, string> Map = new Dictionary<string, string>(System.StringComparer.OrdinalIgnoreCase) {
            ["NetworkThrottlingIndex"] = "Network throttling (Windows default)", ["DirectXUserGlobalSettings"] = "Windowed-games optimizations and VRR", ["ToastEnabled"] = "App notifications",
            ["AllowGameDVR"] = "Game DVR (policy)", ["GameDVR_Enabled"] = "Background game recording", ["AppCaptureEnabled"] = "Game capture",
            ["EnableVirtualizationBasedSecurity"] = "Virtualization-based security", [@"HypervisorEnforcedCodeIntegrity\Enabled"] = "Memory integrity",
            [@"Windows.SystemToast.Suggested\Enabled"] = "Windows' \"suggested\" pop-ups",
            ["DeferFeatureUpdates"] = "Hold back big upgrades", ["DeferFeatureUpdatesPeriodInDays"] = "Days to hold them (45)", ["IsContinuousInnovationOptedIn"] = "\"Get the latest updates first\"",
            ["EnableTransparency"] = "Transparency effects", ["NoAutoRebootWithLoggedOnUsers"] = "No update restart while signed in", ["SetActiveHours"] = "Active hours on",
            ["ActiveHoursStart"] = "Active hours start (8:00)", ["ActiveHoursEnd"] = "Active hours end (2:00)", ["TaskbarEndTask"] = "\"End task\" in the taskbar",
            ["EnablePeriodicBackup"] = "Registry backups", [@"StickyKeys\Flags"] = "Sticky Keys shortcut", [@"ToggleKeys\Flags"] = "Toggle Keys shortcut", [@"Keyboard Response\Flags"] = "Filter Keys shortcut",
            ["DisableFileSyncNGSC"] = "OneDrive sync (policy)", ["FolderType"] = "Folder type guessing", ["AutoGameModeEnabled"] = "Game Mode", ["HwSchMode"] = "Hardware GPU scheduling",
            ["DisableWpbtExecution"] = "Motherboard auto-installer (WPBT)", ["PreventDeviceMetadataFromNetwork"] = "Device companion-app downloads", ["CrashDumpEnabled"] = "Crash dumps",
            ["AlwaysKeepMemoryDump"] = "Keep the crash dump", ["DisplayParameters"] = "Blue screen names its cause", ["LongPathsEnabled"] = "Long file paths",
            [@"Application\MaxSize"] = "Application log size", [@"System\MaxSize"] = "System log size", [@"Windows PowerShell\MaxSize"] = "PowerShell log size",
            ["Install{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}"] = "Edge may not reinstall", ["MouseSpeed"] = "Mouse acceleration", ["MouseThreshold1"] = "Acceleration threshold 1", ["MouseThreshold2"] = "Acceleration threshold 2",
            ["HideFirstRunExperience"] = "Edge first-run pages", ["DefaultBrowserSettingEnabled"] = "Edge \"make me default\" prompts", ["CopilotPageContext"] = "Copilot reading pages",
            ["CopilotCDPPageContext"] = "Copilot page context", ["EdgeEntraCopilotPageContext"] = "Copilot page context (work)", ["EdgeHistoryAISearchEnabled"] = "AI history search",
            ["ComposeInlineEnabled"] = "Edge \"compose\" AI", ["NewTabPageBingChatEnabled"] = "Bing chat on new tab", ["NewTabPageContentEnabled"] = "News on new tab",
            ["EdgeShoppingAssistantEnabled"] = "Shopping assistant", ["ShowRecommendationsEnabled"] = "Edge recommendations", ["SpotlightExperiencesAndRecommendationsEnabled"] = "Edge spotlight suggestions",
            ["WalletDonationEnabled"] = "Donation upsell", ["ShowAcrobatSubscriptionButton"] = "Acrobat upsell", ["CreateDesktopShortcutDefault"] = "Edge desktop icon on update",
            ["CreateDesktopShortcut{56EB18F8-B008-4CBD-B6D2-8C97FE7E9062}"] = "Edge desktop icon (Edge)", ["ShowCopilotButton"] = "Copilot button", ["ShowTaskViewButton"] = "Task View button",
            ["Start_IrisRecommendations"] = "Start recommendations", ["Start_TrackDocs"] = "Recent files in Start", ["Start_AccountNotifications"] = "Account nags in Start",
            ["AllowTelemetry"] = "Telemetry level", ["DoNotShowFeedbackNotifications"] = "Feedback prompts", ["DisableWindowsConsumerFeatures"] = "Auto-installed promo apps",
            ["DisableSoftLanding"] = "Windows tips", ["DisableCloudOptimizedContent"] = "Cloud promo content", ["DisableTailoredExperiencesWithDiagnosticData"] = "Ads from diagnostic data (policy)",
            ["EnableActivityFeed"] = "Activity history", ["PublishUserActivities"] = "Publish activity", ["UploadUserActivities"] = "Upload activity", ["DisabledByGroupPolicy"] = "Advertising ID (policy)",
            ["AllowCortana"] = "Cortana", ["DisableWebSearch"] = "Web results in search", ["ConnectedSearchUseWeb"] = "Bing in search", ["TurnOffWindowsCopilot"] = "Copilot",
            ["DisableAIDataAnalysis"] = "Recall snapshots analysis", ["DisableClickToDo"] = "Click to Do", ["TurnOffSavingSnapshots"] = "Recall snapshots", ["AllowRecallEnablement"] = "Recall",
            ["DisableAIFeatures"] = "Notepad AI", ["DisableCocreator"] = "Paint Cocreator", ["DisableGenerativeFill"] = "Paint generative fill", ["DisableImageCreator"] = "Paint image creator",
            ["DisableGenerativeErase"] = "Paint generative erase", ["DisableRemoveBackground"] = "Paint background removal", ["DisableConsumerAccountStateContent"] = "Microsoft 365 ads in Settings",
            ["DODownloadMode"] = "Update sharing (home network only)", ["AllowNewsAndInterests"] = "Widgets", ["StartupBoostEnabled"] = "Edge startup boost", ["BackgroundModeEnabled"] = "Edge in the background",
            ["HubsSidebarEnabled"] = "Edge sidebar", ["DontSendAdditionalData"] = "Extra crash data to Microsoft", ["DisableSearchBoxSuggestions"] = "Search box suggestions",
            ["ContentDeliveryAllowed"] = "Promo content", ["OemPreInstalledAppsEnabled"] = "PC-maker promo apps", ["PreInstalledAppsEnabled"] = "Preinstalled promo apps",
            ["PreInstalledAppsEverEnabled"] = "Promo apps ever", ["SilentInstalledAppsEnabled"] = "Silently installed apps", ["SoftLandingEnabled"] = "Tips and tricks",
            ["SystemPaneSuggestionsEnabled"] = "Start suggestions", ["RotatingLockScreenOverlayEnabled"] = "Lock screen fun facts", ["SubscribedContent-310093Enabled"] = "Welcome experience",
            ["SubscribedContent-338388Enabled"] = "Start suggestions (2)", ["SubscribedContent-338389Enabled"] = "Tips about Windows", ["SubscribedContent-353694Enabled"] = "Suggested content in Settings",
            ["SubscribedContent-353696Enabled"] = "Suggested content in Settings (2)", ["SubscribedContent-338393Enabled"] = "Suggested content in Settings (3)",
            ["SubscribedContent-353698Enabled"] = "Timeline suggestions", ["SubscribedContent-338387Enabled"] = "Lock screen tips", ["ShowSyncProviderNotifications"] = "OneDrive / 365 ads in Explorer",
            ["ScoobeSystemSettingEnabled"] = "\"Finish setting up\" prompts", ["TailoredExperiencesWithDiagnosticDataEnabled"] = "Ads from diagnostic data", ["BingSearchEnabled"] = "Bing in Start search",
            [@"AdvertisingInfo\Enabled"] = "Advertising ID",
        };
        public static string Of(string full)
        {
            var p = (full ?? "").Split('\\'); var leaf = p[p.Length - 1]; var two = p.Length >= 2 ? p[p.Length - 2] + "\\" + leaf : null;
            if (Kit.Opt("technames", "off") == "on") return leaf;
            if (two != null && Map.TryGetValue(two, out var a)) return a;
            return Map.TryGetValue(leaf, out var b) ? b : leaf;
        }
    }
}
