import Foundation
import HomePadCore
@testable import HomePadConnect

/// One HomePad in memory: a real `Household`, a registry with two kinds of
/// shared documents kept in dictionaries (a layout per owner, and a wallpaper
/// that can be a photo from this iPad), face data by member that never
/// travels, and its own `HouseholdSetupSync`. Its layouts keep each widget's
/// own settings where Same on All HomePads is off, as the Home Screen does,
/// unless it stands for an older HomePad that knows nothing of the switch.
@MainActor
final class TestHomePad {
    static let layoutKind = "test.layout"
    static let wallpaperKind = "test.wallpaper"

    let deviceID: String
    let household: Household
    let registry = ModuleRegistry()
    var layouts: [SharedDocumentOwner: JSONValue] = [:]
    /// "photo" is this iPad's own, as a photo wallpaper is.
    var wallpapers: [SharedDocumentOwner: String] = [:]
    /// Stands in for face templates: kept per member here, never shared.
    var faceData: [UUID: String] = [:]
    let transport: MemoryTransport
    let sync: HouseholdSetupSync
    /// This HomePad's clock, which a test moves.
    let clock: TestClock
    /// True for a HomePad from before Same on All HomePads: it shares and applies layouts as they come.
    let isOlderBuild: Bool

    init(_ deviceID: String, installedAt: Date, hosts: Bool = false, isOlderBuild: Bool = false, network: SetupNetwork,
         now: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        self.deviceID = deviceID
        self.isOlderBuild = isOlderBuild
        let defaults = UserDefaults(suiteName: "setup-test-\(UUID().uuidString)") ?? .standard
        household = Household(store: SettingsStore(defaults: defaults))
        transport = MemoryTransport(deviceID: deviceID, network: network)
        let householdID = network.householdID
        let clock = TestClock(now)
        self.clock = clock
        sync = HouseholdSetupSync(
            source: LiveSetupSource(household: household, registry: registry, deviceID: deviceID), file: SetupLedgerFile(url: nil),
            deviceID: deviceID, installedAt: installedAt, hostedHousehold: { hosts ? householdID : nil },
            clock: { clock.now }
        )
        sync.transport = transport
        registerDocuments()
        network.pads[deviceID] = self
    }

    private func registerDocuments() {
        registry.register(sharedDocument: SharedDocumentDescriptor(
            id: Self.layoutKind, owners: [.household, .members],
            read: { [unowned self] owner in readLayout(owner) },
            apply: { [unowned self] owner, content in applyLayout(content, for: owner) }
        ))
        registry.register(sharedDocument: SharedDocumentDescriptor(
            id: Self.wallpaperKind, owners: [.household, .members],
            read: { [unowned self] owner in
                guard let choice = wallpapers[owner] else { return .none }
                return choice == "photo" ? .onlyThisHomePad : .content(.string(choice))
            },
            apply: { [unowned self] owner, content in wallpapers[owner] = content?.stringValue }
        ))
        // As the modules do: a person's data here follows their new ID.
        household.onMemberIDChange { [unowned self] old, new in
            faceData[new] = faceData.removeValue(forKey: old)
            layouts[.member(new)] = layouts.removeValue(forKey: .member(old))
            wallpapers[.member(new)] = wallpapers.removeValue(forKey: .member(old))
        }
    }

    /// As the Home Screen reads a layout: widgets with Same on All HomePads off carry the shared copy.
    private func readLayout(_ owner: SharedDocumentOwner) -> SharedDocumentValue {
        guard let layout = layouts[owner] else { return .none }
        return .content(isOlderBuild ? layout : layout.sharingWidgetSettings())
    }

    /// As the Home Screen applies one: widgets with Same on All HomePads off keep this iPad's settings.
    private func applyLayout(_ content: JSONValue?, for owner: SharedDocumentOwner) {
        if isOlderBuild {
            layouts[owner] = content
        } else {
            layouts[owner] = content?.keepingOwnWidgetSettings(from: layouts[owner])
        }
    }

    @discardableResult
    func addPerson(_ name: String, enrolled: Bool = true) -> UUID {
        let member = HouseholdMember(name: name, hasFaceEnrollment: enrolled)
        household.add(member)
        if enrolled { faceData[member.id] = "\(name)'s face on \(deviceID)" }
        return member.id
    }

    func person(_ name: String) -> HouseholdMember? {
        household.members.first { $0.name == name }
    }

    /// Shares what changed here, then lets every message arrive.
    func edit(_ change: (TestHomePad) -> Void) {
        change(self)
        sync.shareLocalChanges()
        transport.network.deliverAll()
    }
}

/// A clock a test sets by hand.
final class TestClock: @unchecked Sendable {
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// Carries setup messages between test HomePads through `MessageCodec`, as
/// the wire would, one at a time and in order, so a test can count them.
@MainActor
final class SetupNetwork {
    let householdID = "household-1"
    var pads: [String: TestHomePad] = [:]
    /// Pairs that can reach each other now, smaller ID first.
    private(set) var links: Set<[String]> = []
    private var queue: [(from: String, to: String, message: PeerMessage)] = []
    /// Every message that arrived, in order.
    private(set) var delivered: [PeerMessageType] = []

    func canReach(_ a: String, _ b: String) -> Bool { links.contains([a, b].sorted()) }

    /// Opens a session between two HomePads: both say hello, and everything that follows arrives.
    func connect(_ a: TestHomePad, _ b: TestHomePad) {
        links.insert([a.deviceID, b.deviceID].sorted())
        a.sync.connected(to: b.deviceID)
        b.sync.connected(to: a.deviceID)
        deliverAll()
    }

    func disconnect(_ a: TestHomePad, _ b: TestHomePad) {
        links.remove([a.deviceID, b.deviceID].sorted())
    }

    func enqueue(_ message: SetupMessage, from: String, to: String) {
        guard canReach(from, to), let outgoing = try? message.peerMessage(sender: from) else { return }
        queue.append((from, to, outgoing))
    }

    func deliverAll() {
        while !queue.isEmpty {
            let (from, to, message) = queue.removeFirst()
            guard let data = try? MessageCodec.encode(message), let received = try? MessageCodec.decode(data),
                  let setup = SetupMessage(received), let pad = pads[to] else { continue }
            delivered.append(received.type)
            pad.sync.receive(setup, from: from, name: from)
        }
    }

    /// Forgets what was counted, to count what one step sends.
    func resetCount() { delivered = [] }
}

@MainActor
final class MemoryTransport: SetupTransport {
    let deviceID: String
    let network: SetupNetwork
    /// Nil before the HomePad is paired.
    var isPaired = true

    init(deviceID: String, network: SetupNetwork) {
        self.deviceID = deviceID
        self.network = network
    }

    var householdID: String? { isPaired ? network.householdID : nil }

    func send(_ message: SetupMessage, to peerID: String) {
        network.enqueue(message, from: deviceID, to: peerID)
    }

    func broadcast(_ message: SetupMessage) {
        for peer in network.pads.keys.sorted() where peer != deviceID {
            network.enqueue(message, from: deviceID, to: peer)
        }
    }
}
