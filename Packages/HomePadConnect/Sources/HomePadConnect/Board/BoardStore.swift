import Foundation
import HomePadCore
import HomePadShareKit
import Observation

/// The Family Board: sticky notes shared by the household.
///
/// Notes are saved on device, spread to every paired device over the peer
/// link, and mirrored to the iCloud private database for devices on the same
/// Apple Account. All three paths use `BoardMerge`, so they converge.
@MainActor
@Observable
public final class BoardStore {
    public private(set) var notes: [BoardNote] = []
    /// Live notes, pinned first, then newest. Worked out when the notes change,
    /// not on every redraw of the board and its widget.
    public private(set) var visibleNotes: [BoardNote] = []

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let link: PeerLink
    @ObservationIgnored let cloud: CloudBoardSync
    @ObservationIgnored private let fileURL: URL
    private let log = Log.make("Board")

    init(services: AppServices, link: PeerLink) {
        self.services = services
        self.link = link
        self.cloud = CloudBoardSync()
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: ShareOutbox.appGroup)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.fileURL = base.appendingPathComponent("FamilyBoard.json")
        load()
    }

    func start() {
        link.on(.boardSync) { [weak self] message, peer in self?.receive(message, from: peer) }
        link.onConnect { [weak self] peer in self?.push(to: peer.id) }
        cloud.onFetch = { [weak self] remote in self?.absorb(remote, pushBack: false) }
        if services.settings[ConnectSettings.boardICloudSync] { cloud.start(local: notes) }
    }

    // MARK: Editing

    /// Who a new note is signed by: the active household member, or this room.
    public var author: String {
        services.household.activeMember?.name ?? link.identity.name
    }

    /// Adds a note signed by `author`.
    @discardableResult
    public func add(_ text: String, color: NoteColor) -> BoardNote? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let note = BoardNote(text: trimmed, color: color, author: author, modifiedBy: link.identity.deviceID)
        commit([note])
        return note
    }

    public func update(_ id: BoardNote.ID, text: String? = nil, color: NoteColor? = nil, isPinned: Bool? = nil) {
        guard var note = notes.first(where: { $0.id == id }) else { return }
        if let text { note.text = text }
        if let color { note.color = color }
        if let isPinned { note.isPinned = isPinned }
        note.touch(by: link.identity.deviceID)
        commit([note])
    }

    public func delete(_ id: BoardNote.ID) {
        guard var note = notes.first(where: { $0.id == id }) else { return }
        note.isDeleted = true
        note.touch(by: link.identity.deviceID)
        commit([note])
    }

    #if DEBUG
    /// Puts exactly these notes on the board, for simulator screenshots
    /// (`DemoData`). Nothing goes to other devices or iCloud.
    func replaceForDemo(_ demo: [BoardNote]) {
        replaceNotes(demo)
        save()
    }
    #endif

    /// Turns iCloud mirroring on or off (from Settings).
    public func setICloudSync(_ enabled: Bool) {
        services.settings[ConnectSettings.boardICloudSync] = enabled
        enabled ? cloud.start(local: notes) : cloud.stop()
    }

    // MARK: Sync

    private func commit(_ changed: [BoardNote]) {
        replaceNotes(BoardMerge.merge(notes, changed))
        save()
        Task { await broadcast() }
        if services.settings[ConnectSettings.boardICloudSync] { cloud.push(changed) }
    }

    private func receive(_ message: PeerMessage, from peer: PeerDevice) {
        guard let incoming = try? message.content([BoardNote].self) else { return }
        let reply = BoardMerge.hasNewerThan(incoming, local: notes)
        absorb(incoming, pushBack: true)
        if reply { push(to: peer.id) }
    }

    /// Merges notes from elsewhere. Changed notes go on to iCloud when they came from a peer.
    private func absorb(_ incoming: [BoardNote], pushBack: Bool) {
        let merged = BoardMerge.merge(notes, incoming)
        guard merged != notes else { return }
        let changed = merged.filter { !notes.contains($0) }
        replaceNotes(merged)
        save()
        if pushBack, services.settings[ConnectSettings.boardICloudSync] { cloud.push(changed) }
    }

    private func replaceNotes(_ new: [BoardNote]) {
        notes = new
        visibleNotes = BoardMerge.visible(new)
    }

    private func push(to peerID: String) {
        guard let message = try? link.message(.boardSync, notes) else { return }
        Task { try? await link.send(message, to: peerID) }
    }

    private func broadcast() async {
        guard let message = try? link.message(.boardSync, notes) else { return }
        await link.broadcast(message)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let saved = try? PeerCoding.decoder().decode([BoardNote].self, from: data) else { return }
        replaceNotes(BoardMerge.pruned(saved))
    }

    private func save() {
        do {
            try PeerCoding.encoder().encode(notes).write(to: fileURL, options: .atomic)
        } catch {
            log.error("Could not save the board: \(error.localizedDescription, privacy: .public)")
        }
    }
}
