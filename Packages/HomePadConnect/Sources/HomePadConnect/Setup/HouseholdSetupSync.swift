import Foundation
import HomePadCore
import Observation

/// How the household setup sync reaches the household's other HomePads. The
/// live one is the peer link (`PeerLinkSetupTransport`). Tests join two
/// HomePads in memory.
@MainActor
protocol SetupTransport: AnyObject {
    /// The household this HomePad belongs to now, nil before it is paired.
    var householdID: String? { get }
    func send(_ message: SetupMessage, to peerID: String)
    /// Sends to every HomePad of the household it can reach.
    func broadcast(_ message: SetupMessage)
}

/// Shares the household's setup between its HomePads: the people, each
/// person's and the guest Home Screen and wallpaper, the saved faces and
/// Smart Rotation. Modules describe their documents (`SharedDocumentDescriptor`),
/// and this keeps a versioned copy of each (`SetupLedger`) and trades them over
/// the peer link.
///
/// - A change on this iPad gets a new version (`SetupVersion`) and goes to the
///   other HomePads at once. One that is off catches up when its session opens:
///   both send a hello with the versions they hold, then each sends what the
///   other lacks or holds older.
/// - The last writer wins per document, deletions included. A document that
///   arrives is applied and recorded as read back, so it is never sent back as
///   a change of this iPad's own, and an older one is answered with the newer.
///   Nothing goes back and forth.
/// - A HomePad that does not share the household's setup yet, such as one that
///   was set up on its own, joins it: the household's setup wins, its people
///   are matched by name (`SetupJoinPlan`), and what the household lacks is added.
@MainActor
@Observable
final class HouseholdSetupSync {
    /// Long enough to fold a burst of edits, such as paging through faces, into one message.
    static let localChangeDelay = Duration.milliseconds(600)

    /// The HomePads this one synced with, most recent first.
    private(set) var syncedPeers: [SetupPeer] = []
    /// True once this HomePad shares the household's setup.
    private(set) var sharesSetup = false

    @ObservationIgnored weak var transport: SetupTransport?
    /// Told how many HomePads this one synced with whenever that number
    /// changes. Connect passes it on as `AppServices.homePadsSharingSetup`.
    @ObservationIgnored var onPeerCountChange: (@MainActor (Int) -> Void)?
    @ObservationIgnored private(set) var ledger: SetupLedger
    @ObservationIgnored private let source: SharedSetupSource
    @ObservationIgnored private let file: SetupLedgerFile
    @ObservationIgnored private let deviceID: String
    @ObservationIgnored private let installedAt: Int64
    /// The household this HomePad hosts, if any (`ConnectSettings.hostedHousehold`).
    @ObservationIgnored private let hostedHousehold: @MainActor () -> String?
    @ObservationIgnored private let clock: () -> Date
    /// Where each HomePad stood in its last hello.
    @ObservationIgnored private var standings: [String: SetupStanding] = [:]
    @ObservationIgnored private var pendingScan: Task<Void, Never>?
    @ObservationIgnored private let log = Log.make("HouseholdSetup")

    init(source: SharedSetupSource, file: SetupLedgerFile, deviceID: String, installedAt: Date,
         hostedHousehold: @escaping @MainActor () -> String?, clock: @escaping () -> Date = Date.init) {
        self.source = source
        self.file = file
        self.deviceID = deviceID
        self.installedAt = SetupVersion.milliseconds(installedAt)
        self.hostedHousehold = hostedHousehold
        self.clock = clock
        self.ledger = file.load()
    }

    /// Takes in this iPad's setup and starts watching it for changes.
    func start() {
        publishStatus()
        watchLocalChanges()
    }

    /// When the setup was last traded with another HomePad.
    var lastSync: Date? { syncedPeers.first?.lastSync }

    // MARK: Where this HomePad stands

    /// True when this HomePad shares the setup of the household it belongs to now.
    var isJoined: Bool {
        guard let householdID = transport?.householdID else { return false }
        return ledger.householdID == householdID
    }

    var standing: SetupStanding {
        let householdID = transport?.householdID
        return SetupStanding(sharesSetup: isJoined, hostsHousehold: householdID != nil && hostedHousehold() == householdID,
                             installedAt: installedAt, deviceID: deviceID)
    }

    // MARK: Changes on this iPad

    /// Gives every document that changed on this iPad since the last scan a
    /// new version, and returns them. A document that is this iPad's own for
    /// now is left as it was shared.
    @discardableResult
    func scan() -> [SetupDocument] {
        let kinds = source.kinds
        var keys = Set(source.currentKeys)
        keys.formUnion(ledger.documents.keys.filter { kinds[$0.kind] != nil })
        var changed: [SetupDocument] = []
        for key in keys.sorted() {
            let held = ledger.documents[key]
            let content: JSONValue?
            switch source.read(key) {
            case .onlyThisHomePad: continue
            case .none: content = nil
            case .content(let value): content = value
            }
            if let held, held.content == content { continue }
            if held == nil, content == nil { continue }
            let document = SetupDocument(key: key, version: .next(after: held?.version, device: deviceID, now: clock()),
                                         content: content)
            ledger.documents[key] = document
            changed.append(document)
        }
        if !changed.isEmpty { save() }
        return changed
    }

    /// Scans and sends what changed to the household's other HomePads.
    func shareLocalChanges() {
        send(changes: scan())
    }

    private func send(changes: [SetupDocument]) {
        guard isJoined, !changes.isEmpty else { return }
        log.info("Sharing \(changes.count) changed documents")
        transport?.broadcast(.documents(SetupDocuments(documents: changes)))
    }

    /// Scans while tracking what the documents read, so the next change on
    /// this iPad (a Home Screen edit, a face swiped to) shares again shortly after.
    private func watchLocalChanges() {
        let changes = withObservationTracking {
            scan()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in self?.scheduleScan() }
        }
        send(changes: changes)
    }

    private func scheduleScan() {
        guard pendingScan == nil else { return }
        pendingScan = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.localChangeDelay)
            self?.pendingScan = nil
            self?.watchLocalChanges()
        }
    }

    // MARK: Other HomePads

    /// A session with another HomePad of the household opened: say what this one holds.
    func connected(to peerID: String) {
        guard let householdID = transport?.householdID else { return }
        scan()
        transport?.send(.hello(hello(householdID)), to: peerID)
    }

    func receive(_ message: SetupMessage, from peerID: String, name: String) {
        guard let householdID = transport?.householdID else { return }
        // What this HomePad compares and sends is always its current setup.
        scan()
        switch message {
        case .hello(let hello):
            receive(hello, from: peerID, householdID: householdID)
        case .documents(let set):
            receive(set, from: peerID, householdID: householdID)
        }
        if isJoined { notePeer(peerID, name: name) }
    }

    private func hello(_ householdID: String) -> SetupHello {
        let manifest = isJoined ? Dictionary(ledger.documents.map { ($0.key.description, $0.value.version) },
                                             uniquingKeysWith: max) : [:]
        return SetupHello(householdID: householdID, standing: standing, manifest: manifest)
    }

    private func receive(_ hello: SetupHello, from peerID: String, householdID: String) {
        guard hello.householdID == householdID, hello.version == SetupHello.currentVersion else { return }
        standings[peerID] = hello.standing
        if !isJoined {
            // The other HomePad's setup wins: wait for its complete set.
            if standing < hello.standing { return }
            // This HomePad's setup wins, so the household's shared setup starts from it.
            log.info("Starting the household's shared setup from this HomePad")
            if ledger.householdID != householdID { ledger.peers = [:] }
            ledger.householdID = householdID
            save()
            publishStatus()
        }
        if !hello.standing.sharesSetup {
            let everything = ledger.documents.values.sorted { $0.key < $1.key }
            transport?.send(.documents(SetupDocuments(documents: everything, isComplete: true, standing: standing)), to: peerID)
            return
        }
        // What it holds newer goes to this HomePad the same way, in answer to this one's hello.
        let newer = SetupMerge.newer(in: ledger.documents, than: hello.versions)
        if !newer.isEmpty { transport?.send(.documents(SetupDocuments(documents: newer)), to: peerID) }
    }

    private func receive(_ set: SetupDocuments, from peerID: String, householdID: String) {
        guard isJoined else {
            guard set.isComplete, let theirs = set.standing ?? standings[peerID], standing < theirs else { return }
            join(with: set.documents, householdID: householdID)
            return
        }
        var newer: [SetupDocument] = []
        for document in Self.applyOrder(set.documents.filter { source.accepts($0.key.kind) }) {
            if let held = ledger.documents[document.key] {
                if held.version > document.version { newer.append(held) }
                if held.version >= document.version { continue }
            }
            apply(document)
        }
        save()
        if !newer.isEmpty { transport?.send(.documents(SetupDocuments(documents: newer)), to: peerID) }
    }

    /// Joins the household's setup from its complete set: this iPad's people
    /// take the household's IDs for them by name, the household's documents
    /// replace this iPad's, and what the household lacks is shared from here.
    private func join(with documents: [SetupDocument], householdID: String) {
        let usable = documents.filter { source.accepts($0.key.kind) }
        let people = usable.compactMap { document -> SharedMember? in
            guard document.key.kind == SetupKey.memberKind else { return nil }
            return try? document.content?.decoded(as: SharedMember.self)
        }
        let plan = SetupJoinPlan.make(local: source.members, household: people)
        for match in plan.matches {
            source.changeMemberID(from: match.local, to: match.household)
        }
        ledger.documents = [:]
        ledger.peers = [:]
        for document in Self.applyOrder(usable) { apply(document) }
        ledger.householdID = householdID
        save()
        log.info("Joined the household's setup: \(plan.matches.count) people matched, \(plan.newcomers.count) added")
        // What the household lacks is this HomePad's to share now: its other
        // people, and their Home Screens and faces where the household had none.
        send(changes: scan())
        publishStatus()
    }

    /// People first, so their documents land on someone who exists, and
    /// removed people last.
    private static func applyOrder(_ documents: [SetupDocument]) -> [SetupDocument] {
        func rank(_ document: SetupDocument) -> Int {
            guard document.key.kind == SetupKey.memberKind else { return 1 }
            return document.isDeleted ? 2 : 0
        }
        return documents.sorted { (rank($0), $0.key) < (rank($1), $1.key) }
    }

    /// Applies a document and records it as it reads back, under the version
    /// it came with, so the next scan finds nothing changed.
    private func apply(_ document: SetupDocument) {
        if isThisHomePadsOwn(document.key) {
            // Only this HomePad writes it. Recorded as it came, so the next scan
            // finds this HomePad's own copy different and sends it as newer.
            ledger.documents[document.key] = document
            return
        }
        source.apply(document.content, to: document.key)
        switch source.read(document.key) {
        case .content(let value):
            ledger.documents[document.key] = SetupDocument(key: document.key, version: document.version, content: value)
        case .none where document.isDeleted, .onlyThisHomePad:
            ledger.documents[document.key] = document
        case .none:
            // This HomePad could not show it, as from a newer HomePad with a format it cannot read.
            // It stays unrecorded, so the other HomePad sends it again after the next hello.
            log.error("Could not apply \(document.key.description, privacy: .public)")
        }
    }

    /// True for a document only this HomePad writes (`HomePadDocumentKind`).
    private func isThisHomePadsOwn(_ key: SetupKey) -> Bool {
        HomePadDocumentKind.split(key.kind)?.homePad == deviceID
    }

    // MARK: Status

    private func notePeer(_ peerID: String, name: String) {
        ledger.peers[peerID] = SetupPeer(name: name, lastSync: clock())
        save()
        publishStatus()
    }

    private func publishStatus() {
        let peers = ledger.peers.values.sorted { $0.lastSync > $1.lastSync }
        if peers.count != syncedPeers.count { onPeerCountChange?(peers.count) }
        if peers != syncedPeers { syncedPeers = peers }
        if sharesSetup != isJoined { sharesSetup = isJoined }
    }

    private func save() {
        do {
            try file.save(ledger)
        } catch {
            log.error("Could not save the household setup: \(error.localizedDescription, privacy: .public)")
        }
    }
}
