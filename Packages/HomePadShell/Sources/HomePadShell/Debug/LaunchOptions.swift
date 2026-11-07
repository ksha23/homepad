import Foundation
import HomePadCore

/// Debug launch arguments, so every surface can be opened and screenshotted
/// from the command line (`xcrun simctl launch ... -HomePadOpenApp music`).
///
/// | Argument | Effect |
/// |---|---|
/// | `-HomePadOpenApp <appID>` | open an app |
/// | `-HomePadOpenAppDelay <seconds>` | open that app after a delay, from the Home Screen, to record the transition |
/// | `-HomePadShowFace <faceID>` | show a face in ambient mode |
/// | `-HomePadProximity far\|mid\|near` | pin the proximity level |
/// | `-HomePadShowHome YES` | start on the Home Screen |
/// | `-HomePadShowPanel controlCenter\|people\|appGrid` | open a panel |
/// | `-HomePadEditHomeScreen YES` | Home Screen edit mode |
/// | `-HomePadResetHomeScreen YES` | start from the default Home Screen layout, so UI tests that move items begin alike |
/// | `-HomePadHomeWidgets <id:size,...>` | put these widgets first on the Home Screen, for example `audio.nowplaying:small,smarthome.favorites:large`. IDs joined by `+` make a stack, such as `personal.upnext+personal.weather+audio.nowplaying:medium` |
/// | `-HomePadEditStack YES` | Home Screen edit mode with Edit Stack open for the first stack on the page |
/// | `-HomePadEditWidget <widgetID>` | Home Screen edit mode with Edit Widget open for the first copy of that widget on the page |
/// | `-HomePadHomePage <n>` | start the Home Screen on page n (0 is the first) |
/// | `-HomePadHeaderGlance off\|small\|medium\|large` | the glance as the header's mini widget at that size, or no mini widget |
/// | `-HomePadEditControlCenter YES` | Control Center edit mode |
/// | `-HomePadHomeSheet addItems\|addApps\|wallpaper` | Home Screen edit mode with the widget gallery, app picker or wallpaper picker |
/// | `-HomePadOnboardingStep <0-5>` | onboarding, starting at a step |
/// | `-HomePadShowGate <appID>` | the recognition gate for an app |
/// | `-HomePadSettingsPane <paneID>` | Settings, opened on a pane |
/// | `-HomePadShowOnboarding YES` | the first-launch onboarding |
/// | `-HomePadCondition active\|ambient\|dimmed\|night\|sleeping` | pin the display condition |
/// | `-HomePadMember <name>` | select a household member by name |
/// | `-HomePadRecognized YES` | treat that member as recognized |
/// | `-HomePadSimulateUnplugged YES` | pretend the iPad is on battery |
/// | `-HomePadDemoContent YES` | placeholder apps, widgets, people and music for screenshots |
struct LaunchOptions {
    var openApp: String?
    var openAppDelay: Double?
    var showFace: String?
    var proximity: ProximityLevel?
    var showHome = false
    var panel: ShellNavigator.Panel?
    var editHomeScreen = false
    var editStack = false
    var editWidget: String?
    var resetHomeScreen = false
    var homeWidgets: [HomeScreenItem] = []
    var homePage: Int?
    /// The header's mini widget: the glance at a size, or removed (nil inside). Nil leaves the saved one.
    var headerGlance: MiniWidgetPlacement??
    var editControlCenter = false
    var homeSheet: HomeScreenSheet?
    var onboardingStep: OnboardingStep?
    var gateAppID: String?
    var settingsPane: String?
    var showOnboarding = false
    var condition: DisplayCondition?
    var memberName: String?
    var recognized = false
    var simulateUnplugged = false
    var demoContent = false

    /// True when any argument asks for a specific screen. Onboarding then stays
    /// hidden, the screen does not time out back to the face, and every app
    /// starts from its defaults with its state kept in memory for this launch
    /// (`AppStateStore.startFresh()`), so screenshots and UI tests begin alike.
    var pinsNavigation: Bool {
        openApp != nil || showFace != nil || showHome || panel != nil || editHomeScreen || editStack || editWidget != nil
            || homePage != nil
            || editControlCenter || homeSheet != nil || gateAppID != nil || settingsPane != nil
    }

    static func current(defaults: UserDefaults = .standard) -> LaunchOptions {
        var options = LaunchOptions()
        options.openApp = defaults.string(forKey: "HomePadOpenApp")
        options.openAppDelay = defaults.object(forKey: "HomePadOpenAppDelay") == nil ? nil : defaults.double(forKey: "HomePadOpenAppDelay")
        options.showFace = defaults.string(forKey: "HomePadShowFace")
        options.proximity = defaults.string(forKey: "HomePadProximity").flatMap(Self.proximity)
        options.showHome = defaults.bool(forKey: "HomePadShowHome")
        options.panel = defaults.string(forKey: "HomePadShowPanel").flatMap(ShellNavigator.Panel.init(rawValue:))
        options.editHomeScreen = defaults.bool(forKey: "HomePadEditHomeScreen")
        options.editStack = defaults.bool(forKey: "HomePadEditStack")
        options.editWidget = defaults.string(forKey: "HomePadEditWidget")
        options.resetHomeScreen = defaults.bool(forKey: "HomePadResetHomeScreen")
        options.homeWidgets = (defaults.string(forKey: "HomePadHomeWidgets") ?? "")
            .split(separator: ",").enumerated().compactMap { Self.widgetItem($1, index: $0) }
        options.homePage = defaults.object(forKey: "HomePadHomePage") == nil ? nil : defaults.integer(forKey: "HomePadHomePage")
        options.headerGlance = defaults.string(forKey: "HomePadHeaderGlance").flatMap(Self.glance)
        options.editControlCenter = defaults.bool(forKey: "HomePadEditControlCenter")
        options.homeSheet = defaults.string(forKey: "HomePadHomeSheet").flatMap(HomeScreenSheet.init(rawValue:))
        options.onboardingStep = defaults.object(forKey: "HomePadOnboardingStep") == nil
            ? nil : OnboardingStep(rawValue: defaults.integer(forKey: "HomePadOnboardingStep"))
        options.gateAppID = defaults.string(forKey: "HomePadShowGate")
        options.settingsPane = defaults.string(forKey: "HomePadSettingsPane")
        options.showOnboarding = defaults.bool(forKey: "HomePadShowOnboarding")
        options.condition = defaults.string(forKey: "HomePadCondition").flatMap(DisplayCondition.init(rawValue:))
        options.memberName = defaults.string(forKey: "HomePadMember")
        options.recognized = defaults.bool(forKey: "HomePadRecognized")
        options.simulateUnplugged = defaults.bool(forKey: "HomePadSimulateUnplugged")
        options.demoContent = defaults.bool(forKey: "HomePadDemoContent")
        return options
    }

    /// "audio.nowplaying:medium" becomes that widget at that size. Without a
    /// size it is small. IDs joined by "+" make a stack of those widgets, with a
    /// fixed ID for its place in the list, so a relaunch draws the same stack.
    private static func widgetItem(_ entry: Substring, index: Int) -> HomeScreenItem? {
        let parts = entry.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let id = parts.first, !id.isEmpty else { return nil }
        let size = parts.count > 1 ? WidgetSize(rawValue: parts[1]) ?? .small : .small
        let ids = id.split(separator: "+").map(String.init)
        guard ids.count > 1 else { return .widget(id, size: size) }
        let members = ids.enumerated().map { WidgetStack.Member(id: "debug.\(index).\($0)", widgetID: $1) }
        return .stack(WidgetStack(members: members), size: size, instance: "debug.\(index)")
    }

    /// "off" removes the header's mini widget, a size shows the glance there at that size.
    private static func glance(_ value: String) -> MiniWidgetPlacement?? {
        if value == "off" { return .some(nil) }
        return MiniWidgetSize(rawValue: value).map { .some(MiniWidgetPlacement(widgetID: GlanceMiniWidget.id, size: $0)) }
    }

    private static func proximity(_ value: String) -> ProximityLevel? {
        switch value {
        case "far": .far
        case "mid": .mid
        case "near": .near
        default: nil
        }
    }
}
