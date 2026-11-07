import Foundation
import HomePadCore
import Observation

/// The Connect module's live objects, built once at launch. Views get it from
/// the environment, and App Intents reach it through `ConnectRuntime.current`.
@MainActor
@Observable
public final class ConnectRuntime {
    /// The running instance, for App Intents and other code outside SwiftUI.
    public private(set) static var current: ConnectRuntime?

    public let services: AppServices
    public let registry: ModuleRegistry
    public let link: PeerLink
    public let intercom: IntercomHub
    public let sharing: ShareCenter
    public let board: BoardStore
    public let remote: RemoteHomePads
    /// On a companion: the music of the HomePads it watches.
    public let music: RemoteMusic
    public let handoff: HandoffCenter
    public let shortcuts: ShortcutsLauncher
    public let alerts: AlertNotifier
    /// On a HomePad: Use Personal Device, installed as `services.personalDevices`.
    public let approver: PersonalDeviceApprover
    /// On a companion: answers approval requests and links this device to a member.
    public let approvals: ApprovalResponder
    /// On a HomePad: visits to the recognized person's own iPhone, one for every kind of data it shares.
    let phoneVisits: PhoneVisitClient
    /// On a HomePad: the recognized person's own iPhone photos, installed as `services.phonePhotos`.
    public let phonePhotos: PhonePhotosClient
    /// On a HomePad: their own iPhone calendars and lists, installed as `services.phoneCalendars`.
    public let phoneCalendars: PhoneCalendarsClient
    /// On an iPhone: opens visits from the HomePads its owner shares with.
    public let phoneVisitServer: PhoneVisitServer
    /// On an iPhone: serves its owner's photos to the HomePads they chose.
    public let photoSharing: PhoneLibraryServer
    /// On a HomePad: each member's own Apple Music, installed as `services.memberMusic`.
    public let appleMusicLinks: AppleMusicLinks
    /// On an iPhone: shares its owner's Apple Music with the HomePads they chose.
    public let appleMusicSharing: AppleMusicSharing
    /// On a HomePad: the household's setup, shared with its other HomePads.
    let setup: HouseholdSetupSync
    /// On an iPhone: serves the calendars and lists its owner chose for each HomePad.
    public let calendarSharing: PhoneCalendarServer
    /// On an iPhone: signs its owner in to Spotify and hands the sign-in to a HomePad.
    public let spotifySignIn: PhoneSpotifySignIn

    @ObservationIgnored private let deepLinks: DeepLinkHandler
    @ObservationIgnored private let server: RemoteControlServer
    @ObservationIgnored private let relay: AlertRelay
    @ObservationIgnored private let watch: WatchBridge
    @ObservationIgnored private let setupTransport: PeerLinkSetupTransport
    /// On a HomePad: keeps the Spotify sign-ins members hand over from their iPhones.
    @ObservationIgnored private let spotifyHandoff: SpotifyHandoffReceiver

    init(services: AppServices, registry: ModuleRegistry) {
        let link = PeerLink(services: services)
        let sharing = ShareCenter(services: services, link: link)
        let remote = RemoteHomePads(link: link)
        let intercom = IntercomHub(services: services, link: link)
        self.services = services
        self.registry = registry
        self.link = link
        self.intercom = intercom
        self.sharing = sharing
        self.board = BoardStore(services: services, link: link)
        self.remote = remote
        self.music = RemoteMusic(link: link, remote: remote)
        self.handoff = HandoffCenter(services: services)
        self.shortcuts = ShortcutsLauncher(services: services)
        self.alerts = AlertNotifier(link: link)
        let approver = PersonalDeviceApprover(services: services, link: link)
        let approvals = ApprovalResponder(services: services, link: link)
        self.approver = approver
        self.approvals = approvals
        // Calendars come first in a visit: a few small answers that Up Next
        // and the glance show at once, before the photos' many images.
        let phoneVisits = PhoneVisitClient(services: services, link: link, approver: approver)
        let phoneCalendars = PhoneCalendarsClient(visits: phoneVisits)
        let phonePhotos = PhonePhotosClient(visits: phoneVisits)
        phoneVisits.add(phoneCalendars)
        phoneVisits.add(phonePhotos)
        self.phoneVisits = phoneVisits
        self.phoneCalendars = phoneCalendars
        self.phonePhotos = phonePhotos
        let phoneVisitServer = PhoneVisitServer(services: services, link: link, approvals: approvals)
        let photoSharing = PhoneLibraryServer(visit: phoneVisitServer)
        let calendarSharing = PhoneCalendarServer(visit: phoneVisitServer)
        phoneVisitServer.add(photoSharing)
        phoneVisitServer.add(calendarSharing)
        self.phoneVisitServer = phoneVisitServer
        self.photoSharing = photoSharing
        self.calendarSharing = calendarSharing
        self.appleMusicLinks = AppleMusicLinks(services: services, link: link, approver: approver)
        self.appleMusicSharing = AppleMusicSharing(services: services, link: link, approvals: approvals)
        self.spotifySignIn = PhoneSpotifySignIn(services: services, link: link, approvals: approvals)
        self.spotifyHandoff = SpotifyHandoffReceiver(services: services, link: link, approver: approver)
        self.deepLinks = DeepLinkHandler(services: services, link: link, sharing: sharing)
        self.server = RemoteControlServer(services: services, registry: registry, link: link)
        self.relay = AlertRelay(services: services, link: link)
        self.watch = WatchBridge(services: services, link: link, remote: remote, intercom: intercom)
        let settings = services.settings
        let setupTransport = PeerLinkSetupTransport(link: link)
        self.setupTransport = setupTransport
        self.setup = HouseholdSetupSync(
            source: LiveSetupSource(household: services.household, registry: registry, deviceID: link.identity.deviceID),
            file: .standard(),
            deviceID: link.identity.deviceID, installedAt: LocalDevice.installedAt(),
            hostedHousehold: {
                let id = settings[ConnectSettings.hostedHousehold]
                return id.isEmpty ? nil : id
            }
        )
        setup.transport = setupTransport
        // Edit Widget shows Same on All HomePads only while another HomePad shares the setup.
        setup.onPeerCountChange = { [weak services] count in
            services?.homePadsSharingSetup = count
        }
        // Before the person changes, or the approver and phone photos would drop their links as a removed person's.
        services.household.onMemberIDChange {
            [weak approver, weak phoneVisits = self.phoneVisits, weak music = self.appleMusicLinks] old, new in
            music?.moveMember(from: old, to: new)
            approver?.moveLinks(from: old, to: new)
            phoneVisits?.moveMember(from: old, to: new)
        }
        Self.current = self
    }

    /// True on the iPad kiosk, false on iPhone and Mac companions.
    public var isHomePad: Bool { link.identity.kind == .homePad }

    /// Wires handlers and starts the network link.
    func start() {
        intercom.start()
        sharing.start()
        board.start()
        handoff.start()
        deepLinks.start()
        alerts.start()
        if isHomePad {
            server.start()
            relay.start()
            approver.start()
            phonePhotos.start()
            appleMusicLinks.start()
            setupTransport.connect(setup)
            setup.start()
            phoneCalendars.start()
            phoneVisits.start()
            spotifyHandoff.start()
        } else {
            remote.start()
            approvals.start()
            photoSharing.start()
            appleMusicSharing.start()
            calendarSharing.start()
            phoneVisitServer.start()
            spotifySignIn.start()
            music.start()
            watch.start()
        }
        if services.settings[ConnectSettings.linkEnabled] { link.start() }
        #if DEBUG
        DemoData.seed(self)
        DebugPairing.start(self)
        ApprovalDebug.start(self)
        PhonePhotosDebug.start(self)
        AppleMusicDebug.start(self)
        PhoneCalendarsDebug.start(self)
        #endif
        // Siri learns scene, accessory and face names once the smart home has loaded.
        Task {
            try? await Task.sleep(for: .seconds(10))
            ConnectModule.updateShortcutParameters()
        }
    }
}
