import Foundation
import Observation

/// The service container shared by every module. Starts with demo services,
/// and each module swaps in its real implementation during registration.
///
/// Views get it from the environment: `@Environment(AppServices.self) var services`.
@MainActor
@Observable
public final class AppServices {
    public var smartHome: any SmartHomeService
    public var media: any MediaService
    public var assistant: any AssistantService
    public var timers: any TimerService
    public var presence: any PresenceService
    public var calendar: any CalendarService
    public var weather: any WeatherService
    public var intercom: any IntercomService
    /// Members' own iPhones and Macs, for the recognition gate's Use Personal Device.
    public var personalDevices: any PersonalDeviceService
    /// The recognized person's own iPhone photo library, for the Photos app.
    public var phonePhotos: any PhonePhotosService
    /// Each member's own Apple Music, linked from their iPhone, for the Music app.
    public var memberMusic: any MemberMusicService
    /// The recognized person's own iPhone calendars and reminders lists, for the calendar service.
    public var phoneCalendars: any PhoneCalendarsService

    /// Current display state, owned by the shell's kiosk controller.
    public var displayCondition: DisplayCondition = .ambient

    /// The app on screen, nil on a face and on the Home Screen. Owned by the
    /// shell's navigator. The assistant reads it to know what "this" is.
    public var visibleAppID: String?

    /// What fills the screen, the face, brightness and power. Owned by the
    /// shell's kiosk controller, for modules that report the iPad's state.
    public var kioskStatus = KioskStatus()

    /// Features keeping the display active (no dimming, no return to the face),
    /// for example cooking mode. Use the `.keepsDisplayActive(_:)` view modifier.
    public private(set) var displayHolds: Set<String> = []

    public func holdDisplayActive(_ owner: String) { displayHolds.insert(owner) }
    public func releaseDisplayActive(_ owner: String) { displayHolds.remove(owner) }

    public let events: EventBus
    public let settings: SettingsStore
    public let household: Household
    /// What each app was showing, so it reopens there. Views use `@AppState`.
    public let appState: AppStateStore
    public let keychain: KeychainStore
    public let capture: CaptureCoordinator
    /// What each widget stack remembers while HomePad runs: the widget the
    /// person flipped to and what Smart Rotate shows. The Home Screen and the
    /// faces share it, so a stack drawn in two places shows the same widget.
    public let widgetStacks = WidgetStackMemory()
    /// How many other HomePads share the household's setup with this one, as
    /// Settings > Devices & Sharing counts them ("Synced with 2 HomePads").
    /// Owned by Connect. Zero on a HomePad on its own, which shows no Same on
    /// All HomePads switch on Edit Widget.
    public var homePadsSharingSetup = 0
    /// Tasks modules run while nobody needs the screen, and in the background.
    /// The shell starts and drives it on the iPad that shows HomePad.
    public let backgroundWork: BackgroundWork
    #if os(iOS)
    public let audioSession: AudioSessionCoordinator
    public let microphone: MicrophoneHub
    #endif

    /// The running app's container, for code that cannot receive it through
    /// SwiftUI (App Intents, notification handlers). Set once at launch.
    public private(set) static weak var current: AppServices?

    public func makeCurrent() {
        AppServices.current = self
    }

    public init(settings: SettingsStore? = nil, keychain: KeychainStore = KeychainStore(),
                backgroundWork: BackgroundWork? = nil) {
        let events = EventBus()
        let settings = settings ?? SettingsStore()
        self.events = events
        self.settings = settings
        self.keychain = keychain
        let household = Household(store: settings)
        self.household = household
        self.appState = AppStateStore(settings: settings, household: household)
        self.capture = CaptureCoordinator()
        self.backgroundWork = backgroundWork ?? BackgroundWork()
        #if os(iOS)
        let audioSession = AudioSessionCoordinator()
        self.audioSession = audioSession
        self.microphone = MicrophoneHub(audioSession: audioSession)
        #endif
        self.smartHome = DemoSmartHomeService()
        self.media = NoopMediaService()
        self.assistant = NoopAssistantService()
        self.timers = InMemoryTimerService(events: events)
        self.presence = NoopPresenceService()
        self.calendar = DemoCalendarService()
        self.weather = DemoWeatherService()
        self.intercom = NoopIntercomService()
        self.personalDevices = NoPersonalDevices()
        self.phonePhotos = NoPhonePhotos()
        self.memberMusic = NoMemberMusic()
        // The photo library's owner is a person on this iPad, so they stay its owner under their household ID.
        household.onMemberIDChange { [settings] old, new in
            if settings[PhotoLibraryOwner.setting] == old { settings[PhotoLibraryOwner.setting] = new }
        }
        self.phoneCalendars = NoPhoneCalendars()
    }

    /// Convenience for previews and tests.
    public static func preview() -> AppServices {
        AppServices(settings: SettingsStore(defaults: UserDefaults(suiteName: "homepad.preview") ?? .standard),
                    backgroundWork: BackgroundWork(recordsURL: nil))
    }
}
