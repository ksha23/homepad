import CloudKit
import Foundation
import HomePadCore
import Observation

/// Mirrors the Family Board to the iCloud private database (container
/// `iCloud.com.ksha23.homepad`, custom zone "FamilyBoard") so devices signed in
/// to the same Apple Account share notes even when they are not on the same Wi-Fi.
///
/// It never blocks the board: with no iCloud account, no entitlement or no
/// network it reports a status and the peer link keeps working.
@MainActor
@Observable
public final class CloudBoardSync {
    public enum Status: Equatable {
        case off
        case unavailable(String)
        case syncing
        case upToDate(Date)
        case failed(String)

        public var text: String {
            switch self {
            case .off: "Off"
            case .unavailable(let reason), .failed(let reason): reason
            case .syncing: "Syncing"
            case .upToDate(let date): "Up to date, \(date.formatted(date: .omitted, time: .shortened))"
            }
        }
    }

    public static let containerID = "iCloud.com.ksha23.homepad"
    public private(set) var status = Status.off

    /// Called with every note fetched from iCloud.
    @ObservationIgnored var onFetch: (([BoardNote]) -> Void)?
    @ObservationIgnored private var database: CKDatabase?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var zoneReady = false
    private let zoneID = CKRecordZone.ID(zoneName: "FamilyBoard", ownerName: CKCurrentUserDefaultName)
    private static let recordType = "BoardNote"
    private let log = Log.make("BoardCloud")

    /// Starts syncing, uploading `local` once, then polling every five minutes.
    func start(local: [BoardNote]) {
        guard loop == nil else { return }
        // Checking the identity token first avoids touching CloudKit with no account at all.
        guard FileManager.default.ubiquityIdentityToken != nil else {
            status = .unavailable("Sign in to iCloud to sync notes across your devices.")
            return
        }
        let database = CKContainer(identifier: Self.containerID).privateCloudDatabase
        self.database = database
        loop = Task { [weak self] in
            guard let self, await self.accountAvailable() else { return }
            await self.save(local)
            while !Task.isCancelled {
                await self.fetch()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
        status = .off
    }

    /// Uploads changed notes (fire and forget).
    func push(_ notes: [BoardNote]) {
        guard database != nil, !notes.isEmpty else { return }
        Task { await save(notes) }
    }

    // MARK: Private

    private func accountAvailable() async -> Bool {
        do {
            let account = try await CKContainer(identifier: Self.containerID).accountStatus()
            guard account == .available else {
                status = .unavailable("iCloud is not available on this device right now.")
                return false
            }
            return true
        } catch {
            status = .unavailable("iCloud is not available: \(error.localizedDescription)")
            return false
        }
    }

    private func ensureZone() async throws {
        guard !zoneReady, let database else { return }
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        zoneReady = true
    }

    private func fetch() async {
        guard let database else { return }
        status = .syncing
        do {
            try await ensureZone()
            var token: CKServerChangeToken?
            var notes: [BoardNote] = []
            var more = true
            while more {
                let changes = try await database.recordZoneChanges(inZoneWith: zoneID, since: token)
                notes += changes.modificationResultsByID.values.compactMap { try? Self.note(from: $0.get().record) }
                token = changes.changeToken
                more = changes.moreComing
            }
            onFetch?(notes)
            status = .upToDate(Date())
        } catch {
            fail(error)
        }
    }

    private func save(_ notes: [BoardNote]) async {
        guard let database, !notes.isEmpty else { return }
        do {
            try await ensureZone()
            let records = notes.map(record(for:))
            _ = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .allKeys, atomically: false)
            status = .upToDate(Date())
        } catch {
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        log.error("Board iCloud sync failed: \(error.localizedDescription, privacy: .public)")
        if let ckError = error as? CKError, [.notAuthenticated, .permissionFailure, .badContainer, .missingEntitlement].contains(ckError.code) {
            status = .unavailable("iCloud sync is not available for HomePad on this device.")
            loop?.cancel()
            loop = nil
        } else {
            status = .failed("iCloud sync will retry: \(error.localizedDescription)")
        }
    }

    private func record(for note: BoardNote) -> CKRecord {
        let record = CKRecord(recordType: Self.recordType, recordID: CKRecord.ID(recordName: note.id.uuidString, zoneID: zoneID))
        record["text"] = note.text
        record["color"] = note.color.rawValue
        record["author"] = note.author
        record["isPinned"] = note.isPinned
        record["createdAt"] = note.createdAt
        record["modifiedAt"] = note.modifiedAt
        record["modifiedBy"] = note.modifiedBy
        record["isDeleted"] = note.isDeleted
        return record
    }

    private static func note(from record: CKRecord) -> BoardNote? {
        guard let id = UUID(uuidString: record.recordID.recordName),
              let text = record["text"] as? String,
              let createdAt = record["createdAt"] as? Date,
              let modifiedAt = record["modifiedAt"] as? Date else { return nil }
        return BoardNote(id: id, text: text, color: (record["color"] as? String).flatMap(NoteColor.init(rawValue:)) ?? .yellow,
                         author: record["author"] as? String ?? "", isPinned: record["isPinned"] as? Bool ?? false,
                         createdAt: createdAt, modifiedAt: modifiedAt, modifiedBy: record["modifiedBy"] as? String ?? "",
                         isDeleted: record["isDeleted"] as? Bool ?? false)
    }
}
