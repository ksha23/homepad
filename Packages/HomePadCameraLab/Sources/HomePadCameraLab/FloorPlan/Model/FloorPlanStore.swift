import Foundation
import HomePadCore
import Observation

/// Loads and saves the household's floor plan as JSON under Application Support.
@MainActor
@Observable
final class FloorPlanStore {
    private(set) var plan: FloorPlan?
    private(set) var lastError: String?

    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private let log = Log.make("CameraLab.FloorPlan")

    nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CameraLab/floorplan.json")
    }

    init(fileURL: URL = FloorPlanStore.defaultFileURL) {
        self.fileURL = fileURL
        plan = Self.load(from: fileURL)
    }

    static func load(from url: URL) -> FloorPlan? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(FloorPlan.self, from: data)
    }

    /// Replaces the plan and writes it to disk.
    func save(_ newPlan: FloorPlan) {
        var stamped = newPlan
        // Whole seconds, so the ISO 8601 file round-trips to an equal plan.
        stamped.updatedAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        plan = stamped
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(stamped).write(to: fileURL, options: .atomic)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            log.error("Could not save the floor plan: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Swaps in new geometry from a scan, keeping where accessories were placed.
    func replaceGeometry(with scanned: FloorPlan) {
        var merged = scanned
        merged.placements = plan?.placements ?? scanned.placements
        save(merged)
    }

    func place(_ accessoryID: String, at position: PlanPoint) {
        guard var current = plan else { return }
        current.place(accessoryID, at: position)
        save(current)
    }

    func removePlacement(_ accessoryID: String) {
        guard var current = plan else { return }
        current.removePlacement(accessoryID)
        save(current)
    }

    func useDemo(accessories: [HomeAccessory]) {
        save(DemoFloorPlan.make(accessories: accessories))
    }

    /// Forgets the plan and deletes the file.
    func reset() {
        plan = nil
        try? FileManager.default.removeItem(at: fileURL)
    }
}
