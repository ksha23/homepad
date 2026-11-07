import Foundation
import Observation
import SwiftUI

// What a module can contribute to the shell. Modules never import each other.
// They describe screens, faces, widgets, settings, overlays, assistant tools and
// what their screens show here, and the shell (and assistant) discover them at runtime.

/// Groups apps on the app grid.
public enum AppCategory: String, Sendable, CaseIterable {
    case home, media, communication, kitchen, productivity, camera, system
}

/// A full-screen "app" inside HomePad, like HomeView's Music, Home or Timers.
public struct AppDescriptor: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let tint: Color
    public let category: AppCategory
    /// Order on the app grid, lower first.
    public let sortOrder: Int
    /// Hide from guests, and show a recognition gate before opening (HomeView's
    /// "Recognition Required to Open Messages").
    public let requiresRecognizedMember: Bool
    /// Shows over the app that opened it, which the shell keeps alive
    /// underneath, as iPadOS Music shows its full-screen player over the
    /// library: Now Playing over Music. A swipe down reveals that app, and
    /// going back finds it as it was, on the same page and scroll position.
    public let presentsOverOpener: Bool
    /// The number on the app's icon, like unread messages. Nil or zero shows no
    /// badge. It runs inside the icon's body, so reading an `@Observable` model
    /// there redraws the icon when the count changes.
    public let badgeCount: (@MainActor () -> Int?)?
    public let makeView: @MainActor () -> AnyView

    public init<V: View>(
        id: String, title: String, systemImage: String, tint: Color = .accentColor,
        category: AppCategory, sortOrder: Int = 100, requiresRecognizedMember: Bool = false,
        presentsOverOpener: Bool = false, badgeCount: (@MainActor () -> Int?)? = nil,
        @ViewBuilder view: @escaping @MainActor () -> V
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.category = category
        self.sortOrder = sortOrder
        self.requiresRecognizedMember = requiresRecognizedMember
        self.presentsOverOpener = presentsOverOpener
        self.badgeCount = badgeCount
        self.makeView = { AnyView(view()) }
    }
}

/// An app ID that opens another app. It keeps deep links working (widgets,
/// faces, intents, `homepad://app/<id>`) after a screen moves inside an app:
/// "cameras" opens the Home app on its cameras. It never shows as an app.
public struct AppRedirect: Identifiable {
    public let id: String
    /// The app that opens instead.
    public let appID: String
    /// Runs just before the app opens, so it can show the right screen.
    public let prepare: @MainActor () -> Void

    public init(id: String, opens appID: String, prepare: @escaping @MainActor () -> Void = {}) {
        self.id = id
        self.appID = appID
        self.prepare = prepare
    }
}

/// An always-on full-screen face (clock, photos, home controls, cameras...).
public struct FaceDescriptor: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let sortOrder: Int
    /// Faces that can render themselves in the red night palette.
    public let supportsNightMode: Bool
    public let makeView: @MainActor () -> AnyView

    public init<V: View>(
        id: String, title: String, systemImage: String, sortOrder: Int = 100,
        supportsNightMode: Bool = true, @ViewBuilder view: @escaping @MainActor () -> V
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.sortOrder = sortOrder
        self.supportsNightMode = supportsNightMode
        self.makeView = { AnyView(view()) }
    }
}

/// How many grid cells a widget covers. The Home Screen and the faces lay
/// widgets out on cells of the same shape.
public enum WidgetSize: String, Sendable, CaseIterable {
    case small      // 1x1 tile
    case medium     // 2x1
    case large      // 2x2
    case tall       // 2x3

    /// The sizes a widget supports unless it lists its own. Tall is left out:
    /// a widget opts into it when its extra height shows more, such as a
    /// longer list, rather than the same content drawn bigger.
    public static let standard: [WidgetSize] = [.small, .medium, .large]

    /// Columns the widget covers.
    public var columns: Int {
        switch self {
        case .small: 1
        case .medium, .large, .tall: 2
        }
    }

    /// Rows the widget covers.
    public var rows: Int {
        switch self {
        case .small, .medium: 1
        case .large: 2
        case .tall: 3
        }
    }

    /// The size's name in the widget gallery and in VoiceOver.
    public var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        case .tall: "Tall"
        }
    }
}

/// Where a widget lands on a face's grid while it has no cell of its own,
/// such as when it is just added.
public enum WidgetAnchor: Sendable {
    /// With the face's other widgets, along the edge the face fills from.
    case faceFill
    /// In the open area nearest the face's top leading corner, where a
    /// summary is read first, like the glance.
    case topLeading
}

/// A widget for the Home Screen and the faces.
///
/// A widget can have settings of its own, like iPadOS's Edit Widget. Each
/// placed copy keeps its own `WidgetSettings`, which the widget reads from
/// `\.widgetSettings`, and `settings` draws the page that changes them:
///
///     static let list = WidgetSettingKey<String?>("list", default: nil)
///
///     WidgetDescriptor(id: "personal.reminders", title: "Reminders", systemImage: "checklist") { size in
///         RemindersWidgetView(size: size)        // reads settings[list] from \.widgetSettings
///     } settings: { settings in
///         RemindersWidgetSettingsView(settings: settings)
///     }
///
/// A widget can also say how relevant it is right now (`relevance`), so a
/// widget stack's Smart Rotate turns to it, as iPadOS widgets tell a Smart
/// Stack: Timers while a timer runs, Now Playing while music plays.
public struct WidgetDescriptor: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    /// The sizes it can be placed at, in the order the gallery shows them.
    public let supportedSizes: [WidgetSize]
    public let isPersonal: Bool     // hidden unless the member is recognized
    /// The app a tap on the widget opens (outside its own buttons), like HomeView.
    public let opensAppID: String?
    /// Where it lands on a face when it has no cell of its own yet.
    public let anchor: WidgetAnchor
    public let makeView: @MainActor (WidgetSize) -> AnyView
    /// The Edit Widget page, or nil for a widget without settings. It gets the
    /// placed widget's settings, and the place that holds the widget saves each
    /// change as it is made, so the page has no Save or Done.
    public let makeSettingsView: (@MainActor (Binding<WidgetSettings>) -> AnyView)?
    /// How relevant the widget is right now, for Smart Rotate in a widget
    /// stack (`WidgetRelevance`), or nil for a widget that never asks to be
    /// shown. A stack calls it inside a view, so reading `@Observable` models
    /// here asks again when they change.
    public let relevance: WidgetRelevanceHook?

    /// True when the widget has settings to change in Edit Widget.
    public var hasSettings: Bool { makeSettingsView != nil }

    public init<V: View>(
        id: String, title: String, systemImage: String, supportedSizes: [WidgetSize] = WidgetSize.standard,
        isPersonal: Bool = false, opensApp opensAppID: String? = nil, anchor: WidgetAnchor = .faceFill,
        relevance: WidgetRelevanceHook? = nil,
        @ViewBuilder view: @escaping @MainActor (WidgetSize) -> V
    ) {
        self.init(id: id, title: title, systemImage: systemImage, supportedSizes: supportedSizes, isPersonal: isPersonal,
                  opensAppID: opensAppID, anchor: anchor, relevance: relevance, makeView: { AnyView(view($0)) },
                  makeSettingsView: nil)
    }

    /// A widget with settings: `settings` draws its Edit Widget page.
    public init<V: View, S: View>(
        id: String, title: String, systemImage: String, supportedSizes: [WidgetSize] = WidgetSize.standard,
        isPersonal: Bool = false, opensApp opensAppID: String? = nil, anchor: WidgetAnchor = .faceFill,
        relevance: WidgetRelevanceHook? = nil,
        @ViewBuilder view: @escaping @MainActor (WidgetSize) -> V,
        @ViewBuilder settings: @escaping @MainActor (Binding<WidgetSettings>) -> S
    ) {
        self.init(id: id, title: title, systemImage: systemImage, supportedSizes: supportedSizes, isPersonal: isPersonal,
                  opensAppID: opensAppID, anchor: anchor, relevance: relevance, makeView: { AnyView(view($0)) },
                  makeSettingsView: { AnyView(settings($0)) })
    }

    private init(
        id: String, title: String, systemImage: String, supportedSizes: [WidgetSize], isPersonal: Bool,
        opensAppID: String?, anchor: WidgetAnchor, relevance: WidgetRelevanceHook?,
        makeView: @escaping @MainActor (WidgetSize) -> AnyView,
        makeSettingsView: (@MainActor (Binding<WidgetSettings>) -> AnyView)?
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.supportedSizes = supportedSizes
        self.isPersonal = isPersonal
        self.opensAppID = opensAppID
        self.anchor = anchor
        self.relevance = relevance
        self.makeView = makeView
        self.makeSettingsView = makeSettingsView
    }
}

/// A mini widget: a widget that fits the header row, one row as tall as the
/// profile button. It sits right of the Home Screen header's lines, and in a
/// face's top left corner on glass, mirroring the profile button. The glance
/// is the first one.
///
/// It draws itself from a `MiniWidgetContext`: its size, what it sits on,
/// its text size and whether a tap opens an app. It fits the width it is
/// offered, showing less before anything is cut off. A mini widget with
/// personal parts leaves them out until someone is recognized
/// (`Household.isPersonalContentUnlocked`), as the glance does.
///
///     registry.register(miniWidget: MiniWidgetDescriptor(id: "shell.glance.mini", title: "Glance",
///                                                        systemImage: "square.text.square") { context in
///         MiniGlanceView(context: context)
///     })
public struct MiniWidgetDescriptor: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    /// The sizes it can show at, smallest first. The size button steps through them.
    public let supportedSizes: [MiniWidgetSize]
    public let makeView: @MainActor (MiniWidgetContext) -> AnyView

    public init<V: View>(
        id: String, title: String, systemImage: String, supportedSizes: [MiniWidgetSize] = MiniWidgetSize.allCases,
        @ViewBuilder view: @escaping @MainActor (MiniWidgetContext) -> V
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.supportedSizes = supportedSizes.isEmpty ? [.small] : supportedSizes
        self.makeView = { AnyView(view($0)) }
    }

    /// The size the size button steps to from `size`, back to the first after the last.
    public func size(after size: MiniWidgetSize) -> MiniWidgetSize {
        guard let index = supportedSizes.firstIndex(of: size) else { return supportedSizes[0] }
        return supportedSizes[(index + 1) % supportedSizes.count]
    }

    /// The size it shows at for a saved `size`: that one when it supports it, else its first.
    public func shownSize(_ size: MiniWidgetSize) -> MiniWidgetSize {
        supportedSizes.contains(size) ? size : supportedSizes[0]
    }
}

/// A page in Settings.
public struct SettingsPaneDescriptor: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    /// Background of the pane's icon in the Settings sidebar, iOS Settings style.
    /// Usually the module's app color.
    public let tint: Color
    public let sortOrder: Int
    /// Only admins (verified by Face ID or passcode) can open it.
    public let adminOnly: Bool
    public let makeView: @MainActor () -> AnyView

    public init<V: View>(
        id: String, title: String, systemImage: String, tint: Color = .gray, sortOrder: Int = 100, adminOnly: Bool = false,
        @ViewBuilder view: @escaping @MainActor () -> V
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.sortOrder = sortOrder
        self.adminOnly = adminOnly
        self.makeView = { AnyView(view()) }
    }
}

/// A view layered above everything (doorbell popup, assistant orb, camera-in-use dot).
/// The overlay decides its own visibility, so return an empty view when idle.
public struct OverlayDescriptor: Identifiable {
    public let id: String
    /// Higher draws on top.
    public let zIndex: Double
    public let makeView: @MainActor () -> AnyView

    public init<V: View>(id: String, zIndex: Double = 0, @ViewBuilder view: @escaping @MainActor () -> V) {
        self.id = id
        self.zIndex = zIndex
        self.makeView = { AnyView(view()) }
    }
}

/// How much room a Control Center tile takes, in grid cells.
public enum ControlSize: String, Sendable, CaseIterable {
    case small      // 1x1 round toggle
    case wide       // 2x1
    case tall       // 1x2 slider
    case large      // 2x2

    public var columns: Int { self == .wide || self == .large ? 2 : 1 }
    public var rows: Int { self == .tall || self == .large ? 2 : 1 }
}

/// A tile in Control Center (pull down from the top-right corner).
public struct ControlDescriptor: Identifiable {
    public let id: String
    public let title: String
    /// Shown in the Control Center gallery when adding tiles.
    public let systemImage: String
    public let size: ControlSize
    public let sortOrder: Int
    public let makeView: @MainActor () -> AnyView

    public init<V: View>(
        id: String, title: String, systemImage: String = "square.grid.2x2.fill", size: ControlSize = .wide,
        sortOrder: Int = 100, @ViewBuilder view: @escaping @MainActor () -> V
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.size = size
        self.sortOrder = sortOrder
        self.makeView = { AnyView(view()) }
    }
}

/// A function the assistant (any AI provider) can call.
/// `parameters` is a JSON Schema object, built with `Schema.object(...)`.
public struct AssistantTool: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String
    public let parameters: JSONValue
    /// Refuse when nobody is recognized (unlock doors, read messages...).
    public let requiresRecognizedMember: Bool
    public let handler: @MainActor @Sendable (JSONValue) async throws -> String

    public init(
        name: String, description: String, parameters: JSONValue = Schema.object([:]),
        requiresRecognizedMember: Bool = false,
        handler: @escaping @MainActor @Sendable (JSONValue) async throws -> String
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.requiresRecognizedMember = requiresRecognizedMember
        self.handler = handler
    }
}

/// Everything modules contributed. Read by the shell and the assistant.
@MainActor
@Observable
public final class ModuleRegistry {
    public private(set) var apps: [AppDescriptor] = []
    public private(set) var redirects: [AppRedirect] = []
    public private(set) var faces: [FaceDescriptor] = []
    public private(set) var widgets: [WidgetDescriptor] = []
    /// Mini widgets, for the Home Screen's header and a face's top left corner, in the order registered.
    public private(set) var miniWidgets: [MiniWidgetDescriptor] = []
    public private(set) var settingsPanes: [SettingsPaneDescriptor] = []
    public private(set) var overlays: [OverlayDescriptor] = []
    public private(set) var controls: [ControlDescriptor] = []
    public private(set) var tools: [AssistantTool] = []
    /// What each app shows right now, for the assistant (see `ScreenContextProvider`).
    public private(set) var screenContexts: [ScreenContextProvider] = []
    /// The household's setup that HomePads in one household share (see `SharedDocumentDescriptor`).
    public private(set) var sharedDocuments: [SharedDocumentDescriptor] = []
    /// What each HomePad shares about itself (see `HomePadDocumentDescriptor`).
    public private(set) var homePadDocuments: [HomePadDocumentDescriptor] = []
    public private(set) var moduleIDs: [String] = []
    /// Draws the cover of what plays now, with the given corner radius, from
    /// the module that plays it. The shell's Now Playing pill and Control
    /// Center tile use it, so they show the module's own cover. Apple Music
    /// and library covers come from their players and have no address to load.
    public private(set) var nowPlayingArtwork: (@MainActor (NowPlaying, CGFloat) -> AnyView)?

    public init() {}

    public func register(app: AppDescriptor) { upsert(&apps, app); apps.sort { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) } }
    public func register(redirect: AppRedirect) { upsert(&redirects, redirect) }
    public func register(face: FaceDescriptor) { upsert(&faces, face); faces.sort { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) } }
    public func register(widget: WidgetDescriptor) { upsert(&widgets, widget) }
    public func register(miniWidget: MiniWidgetDescriptor) { upsert(&miniWidgets, miniWidget) }
    public func register(settings: SettingsPaneDescriptor) { upsert(&settingsPanes, settings); settingsPanes.sort { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) } }
    public func register(overlay: OverlayDescriptor) { upsert(&overlays, overlay); overlays.sort { $0.zIndex < $1.zIndex } }
    public func register(control: ControlDescriptor) { upsert(&controls, control); controls.sort { ($0.sortOrder, $0.title) < ($1.sortOrder, $1.title) } }
    public func register(tool: AssistantTool) { upsert(&tools, tool) }
    public func register(tools newTools: [AssistantTool]) { newTools.forEach { register(tool: $0) } }
    public func register(screenContext: ScreenContextProvider) { upsert(&screenContexts, screenContext) }
    public func register(sharedDocument: SharedDocumentDescriptor) { upsert(&sharedDocuments, sharedDocument) }
    public func register(homePadDocument: HomePadDocumentDescriptor) { upsert(&homePadDocuments, homePadDocument) }
    public func register<V: View>(nowPlayingArtwork view: @escaping @MainActor (NowPlaying, CGFloat) -> V) {
        nowPlayingArtwork = { AnyView(view($0, $1)) }
    }

    public func app(_ id: String) -> AppDescriptor? { apps.first { $0.id == id } }
    public func redirect(_ id: String) -> AppRedirect? { redirects.first { $0.id == id } }

    /// The app to open for an ID: the app itself when one is registered, else the
    /// app a redirect names, after running the redirect's `prepare`.
    public func followingRedirect(_ id: String) -> String {
        guard app(id) == nil, let redirect = redirect(id) else { return id }
        redirect.prepare()
        return redirect.appID
    }
    public func face(_ id: String) -> FaceDescriptor? { faces.first { $0.id == id } }
    public func widget(_ id: String) -> WidgetDescriptor? { widgets.first { $0.id == id } }
    public func miniWidget(_ id: String) -> MiniWidgetDescriptor? { miniWidgets.first { $0.id == id } }

    func noteModule(_ id: String) {
        if !moduleIDs.contains(id) { moduleIDs.append(id) }
    }

    private func upsert<T: Identifiable>(_ array: inout [T], _ item: T) where T.ID == String {
        array.removeAll { $0.id == item.id }
        array.append(item)
    }
}
