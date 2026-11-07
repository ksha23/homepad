import Foundation
import HomePadCore
import Observation

/// One thing scanned into the grocery list.
struct GroceryItem: Identifiable, Equatable {
    enum Status: Equatable {
        case lookingUp
        /// Waiting out the undo window before going to Reminders.
        case pending(commitAt: Date)
        case adding
        case added
        case notFound
        case failed(String)
    }

    let id = UUID()
    var barcode: String?
    var name: String
    var brand: String?
    var quantity: String?
    var imageURL: URL?
    var count = 1
    var status: Status

    /// The reminder title, with a count when the same item was scanned twice.
    var reminderTitle: String { count > 1 ? "\(name) ×\(count)" : name }

    var canUndo: Bool {
        switch status {
        case .lookingUp, .pending, .notFound, .failed: true
        case .adding, .added: false
        }
    }
}

/// The running list of a grocery scanning session. Each item waits a few
/// seconds before it is added to Reminders, so Undo really takes it back.
@MainActor
@Observable
final class GrocerySession {
    static let undoWindow: TimeInterval = 5
    /// The same barcode within this window is the scanner seeing it again, not a second item.
    static let rescanWindow: TimeInterval = 3

    private(set) var items: [GroceryItem] = []
    private(set) var message: String?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let client: OpenFoodFactsClient
    @ObservationIgnored private var lastSeen: [String: Date] = [:]

    init(services: AppServices, client: OpenFoodFactsClient = OpenFoodFactsClient()) {
        self.services = services
        self.client = client
    }

    var listName: String { services.settings[CameraLabSettings.groceryListName] }
    var addedCount: Int { items.filter { $0.status == .added }.count }
    var hasPending: Bool { items.contains(where: \.isPending) }

    // MARK: Scanning

    func add(barcode: String) {
        let now = Date()
        if let seen = lastSeen[barcode], now.timeIntervalSince(seen) < Self.rescanWindow { return }
        lastSeen[barcode] = now
        if let index = items.firstIndex(where: { $0.barcode == barcode && $0.isPending }) {
            items[index].count += 1
            items[index].status = .pending(commitAt: now.addingTimeInterval(Self.undoWindow))
            return
        }
        let item = GroceryItem(barcode: barcode, name: barcode, status: .lookingUp)
        items.insert(item, at: 0)
        Task { await lookUp(item.id, barcode: barcode) }
    }

    func add(text: String) {
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !name.isEmpty else { return }
        let item = GroceryItem(name: name.prefix(1).uppercased() + name.dropFirst(), status: .pending(commitAt: Date().addingTimeInterval(Self.undoWindow)))
        items.insert(item, at: 0)
        scheduleCommit(item.id)
    }

    /// Takes back the newest item that has not reached Reminders yet.
    func undo() {
        guard let index = items.firstIndex(where: \.canUndo) else {
            message = "Items already in Reminders stay there. Remove them in Reminders."
            return
        }
        let removed = items.remove(at: index)
        message = "Removed \(removed.name)."
    }

    /// Skips the undo window for everything waiting.
    func addAllNow() {
        for item in items where item.isPending { Task { await commit(item.id) } }
    }

    // MARK: Work

    private func lookUp(_ id: GroceryItem.ID, barcode: String) async {
        do {
            let product = try await client.product(for: barcode)
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            guard let product, let name = product.displayName else {
                items[index].status = .notFound
                items[index].name = "Unknown product"
                return
            }
            items[index].name = name
            items[index].brand = product.primaryBrand
            items[index].quantity = product.quantity
            items[index].imageURL = product.imageURL
            items[index].status = .pending(commitAt: Date().addingTimeInterval(Self.undoWindow))
            scheduleCommit(id)
        } catch {
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].status = .failed(error.localizedDescription)
        }
    }

    private func scheduleCommit(_ id: GroceryItem.ID) {
        Task { [weak self] in
            while let self, let item = self.items.first(where: { $0.id == id }), case .pending(let commitAt) = item.status {
                let wait = commitAt.timeIntervalSinceNow
                if wait <= 0 {
                    await self.commit(id)
                    return
                }
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    private func commit(_ id: GroceryItem.ID) async {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].isPending else { return }
        items[index].status = .adding
        let calendar = services.calendar
        if !calendar.hasAccess, !(await calendar.requestAccess()) {
            setStatus(.failed("HomePad needs access to Reminders. Allow it in Settings."), for: id)
            return
        }
        guard let title = items.first(where: { $0.id == id })?.reminderTitle else { return }
        do {
            try await calendar.addReminder(title: title, due: nil, listName: listName)
            setStatus(.added, for: id)
        } catch {
            setStatus(.failed(error.localizedDescription), for: id)
        }
    }

    private func setStatus(_ status: GroceryItem.Status, for id: GroceryItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = status
    }
}

private extension GroceryItem {
    var isPending: Bool {
        if case .pending = status { return true }
        return false
    }
}
