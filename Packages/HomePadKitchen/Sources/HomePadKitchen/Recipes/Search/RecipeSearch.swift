import Foundation
import Observation

/// Where a catalog search stands, for the Recipes app and the assistant.
public enum RecipeSearchPhase: Equatable, Sendable {
    case idle
    case searching
    case results([CatalogRecipe])
    case noResults
    case failed(message: String, isOffline: Bool)
}

/// Searches the online catalog for the library's search field and the
/// assistant. Typing waits for a short pause, a newer query replaces an older
/// one, and the last results stay available for "save the second one".
@MainActor
@Observable
public final class RecipeSearch {
    /// The words searched for. Empty when no search is showing.
    public private(set) var query = ""
    public private(set) var phase: RecipeSearchPhase = .idle

    @ObservationIgnored let catalog: any RecipeCatalog
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let typingPause: Duration

    init(catalog: any RecipeCatalog, typingPause: Duration = .milliseconds(450)) {
        self.catalog = catalog
        self.typingPause = typingPause
    }

    /// True while the library shows search instead of the saved recipes.
    public var isActive: Bool { !query.isEmpty }

    /// The results of the last finished search.
    public var results: [CatalogRecipe] {
        if case .results(let results) = phase { return results }
        return []
    }

    /// Searches once typing pauses. Short queries wait for more letters.
    public func update(query newQuery: String) {
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != query else { return }
        guard !trimmed.isEmpty else { return clear() }
        query = trimmed
        task?.cancel()
        guard trimmed.count >= 3 else {
            phase = .idle
            return
        }
        phase = .searching
        task = Task { [weak self, typingPause] in
            try? await Task.sleep(for: typingPause)
            guard !Task.isCancelled else { return }
            await self?.perform(trimmed)
        }
    }

    /// Searches now and returns the results: the Search key, Try Again and the assistant.
    @discardableResult
    public func run(_ newQuery: String) async -> [CatalogRecipe] {
        let trimmed = newQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        task?.cancel()
        query = trimmed
        await perform(trimmed)
        return results
    }

    /// Goes back to the library.
    public func clear() {
        task?.cancel()
        task = nil
        query = ""
        phase = .idle
    }

    private func perform(_ searched: String) async {
        phase = .searching
        let outcome: RecipeSearchPhase
        do {
            let found = try await catalog.search(searched)
            outcome = found.isEmpty ? .noResults : .results(found)
        } catch let error as RecipeCatalogError {
            outcome = .failed(message: error.localizedDescription, isOffline: error == .offline)
        } catch {
            outcome = .failed(message: error.localizedDescription, isOffline: false)
        }
        // A newer query or a cleared field wins over a late answer.
        guard query == searched else { return }
        phase = outcome
    }
}
