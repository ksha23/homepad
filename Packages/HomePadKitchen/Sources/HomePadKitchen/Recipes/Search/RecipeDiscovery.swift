import Foundation
import Observation

/// The Discover shelf: a handful of random picks from the catalog that fills
/// itself in the background. Picks last a few hours, so opening the app again
/// does not fetch every time, and More Ideas swaps them for new ones.
@MainActor
@Observable
public final class RecipeDiscovery {
    public private(set) var picks: [CatalogRecipe] = []
    public private(set) var isLoading = false
    /// Why the last refresh failed, when there are no picks to show.
    public private(set) var failure: RecipeCatalogError?

    @ObservationIgnored let catalog: any RecipeCatalog
    @ObservationIgnored private var loadedAt: Date?
    static let count = 10
    static let freshness: TimeInterval = 6 * 3600

    init(catalog: any RecipeCatalog) {
        self.catalog = catalog
    }

    /// Loads picks when there are none or they are a few hours old.
    public func refreshIfStale(now: Date = Date()) async {
        if let loadedAt, !picks.isEmpty, now.timeIntervalSince(loadedAt) < Self.freshness { return }
        await refresh(now: now)
    }

    /// Replaces the picks with new ones. Keeps the old ones if that fails.
    public func refresh(now: Date = Date()) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fresh = try await catalog.discover(count: Self.count)
            if !fresh.isEmpty {
                picks = fresh
                loadedAt = now
            }
            failure = nil
        } catch {
            failure = error as? RecipeCatalogError ?? .unavailable(error.localizedDescription)
        }
    }
}
