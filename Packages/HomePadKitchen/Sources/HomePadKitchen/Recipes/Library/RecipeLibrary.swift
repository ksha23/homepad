import Foundation
import HomePadCore
import Observation

/// The household's saved recipes, persisted as JSON in Application Support.
/// The first launch seeds the bundled sample recipes, then `RecipeStarterSet`
/// adds everyday recipes from the online catalog. Deleted recipes with a source
/// link are remembered, so nothing automatic brings them back.
@MainActor
@Observable
public final class RecipeLibrary {
    /// Pinned first, then newest first.
    public private(set) var recipes: [Recipe] = []

    /// Where the library lives. The meal plan is saved beside it.
    @ObservationIgnored let directory: URL
    @ObservationIgnored private var state = LibraryState()
    private let log = Log.make("Kitchen.Library")

    /// - Parameter directory: Folder for `recipes.json` and picked photos.
    ///   Defaults to Application Support/Kitchen.
    public init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory
        load()
    }

    nonisolated public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Kitchen", directoryHint: .isDirectory)
    }

    private var fileURL: URL { directory.appending(path: "recipes.json") }
    private var stateURL: URL { directory.appending(path: "library-state.json") }

    // MARK: Queries

    public func recipe(_ id: Recipe.ID) -> Recipe? {
        recipes.first { $0.id == id }
    }

    /// The saved recipe that came from this page, if any.
    public func recipe(withSource url: URL?) -> Recipe? {
        guard let url else { return nil }
        return recipes.first { $0.sourceURL == url }
    }

    /// True when someone deleted the recipe from this page. Automatic additions skip it.
    public func wasDeleted(source url: URL) -> Bool {
        state.deletedSources.contains(url)
    }

    /// True once every starter recipe was added or skipped.
    public var hasStarterSet: Bool { state.hasStarterSet }

    func markStarterSetDone() {
        state.hasStarterSet = true
        saveState()
    }

    /// Best match for a spoken name: exact, then contains, then most shared words.
    public func find(named query: String) -> Recipe? {
        let needle = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if let exact = recipes.first(where: { $0.title.lowercased() == needle }) { return exact }
        if let contained = recipes.first(where: { $0.title.lowercased().contains(needle) || needle.contains($0.title.lowercased()) }) {
            return contained
        }
        let words = Set(needle.split(separator: " ").map(String.init).filter { $0.count > 2 })
        let scored = recipes.map { recipe in
            (recipe, Set(recipe.title.lowercased().split(separator: " ").map(String.init)).intersection(words).count)
        }
        return scored.filter { $0.1 > 0 }.max { $0.1 < $1.1 }?.0
    }

    /// One recipe per day, stable for the whole day, preferring pinned recipes.
    public func recipeOfTheDay(on date: Date = Date(), calendar: Calendar = .current) -> Recipe? {
        let pinned = recipes.filter(\.isPinned)
        let pool = pinned.count > 1 ? pinned : recipes
        guard !pool.isEmpty else { return nil }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        let ordered = pool.sorted { $0.id.uuidString < $1.id.uuidString }
        return ordered[day % ordered.count]
    }

    // MARK: Changes

    /// Adds a recipe, replacing an earlier import of the same page. Returns the stored recipe.
    /// Adding a page that was deleted before is a deliberate choice, so it is no longer remembered as deleted.
    @discardableResult
    public func add(_ recipe: Recipe) -> Recipe {
        if let url = recipe.sourceURL, state.deletedSources.remove(url) != nil { saveState() }
        var stored = recipe
        if let url = recipe.sourceURL, let existing = recipes.firstIndex(where: { $0.sourceURL == url }) {
            stored.id = recipes[existing].id
            stored.isPinned = recipes[existing].isPinned
            stored.localImageName = recipes[existing].localImageName
            recipes.remove(at: existing)
        }
        recipes.append(stored)
        sortAndSave()
        return stored
    }

    public func update(_ recipe: Recipe) {
        guard let index = recipes.firstIndex(where: { $0.id == recipe.id }) else { return }
        recipes[index] = recipe
        sortAndSave()
    }

    public func delete(_ id: Recipe.ID) {
        if let name = recipe(id)?.localImageName {
            try? FileManager.default.removeItem(at: directory.appending(path: name))
        }
        if let url = recipe(id)?.sourceURL {
            state.deletedSources.insert(url)
            saveState()
        }
        recipes.removeAll { $0.id == id }
        save()
    }

    public func togglePin(_ id: Recipe.ID) {
        guard var recipe = recipe(id) else { return }
        recipe.isPinned.toggle()
        update(recipe)
    }

    /// Stores a photo picked for a recipe and makes it the hero image.
    public func setPhoto(_ data: Data, for id: Recipe.ID) {
        guard var recipe = recipe(id) else { return }
        let name = "photo-\(id.uuidString).jpg"
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appending(path: name)
            try data.write(to: url, options: .atomic)
            // A replaced photo keeps its file name, so the decoded copy must go.
            RecipePhotoLoader.shared.forget(url)
            recipe.localImageName = name
            update(recipe)
        } catch {
            log.error("Saving recipe photo failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Where a recipe's picked photo lives, if it has one.
    public func localImageURL(for recipe: Recipe) -> URL? {
        recipe.localImageName.map { directory.appending(path: $0) }
    }

    /// Puts the bundled samples back, keeping everything else.
    public func restoreSamples() {
        for sample in Self.bundledSamples() where recipe(sample.id) == nil {
            recipes.append(sample)
        }
        sortAndSave()
    }

    // MARK: Persistence

    private func load() {
        if let data = try? Data(contentsOf: stateURL), let saved = try? Self.decoder.decode(LibraryState.self, from: data) {
            state = saved
        }
        guard let data = try? Data(contentsOf: fileURL) else {
            recipes = Self.bundledSamples()
            sortAndSave()
            return
        }
        do {
            recipes = try Self.decoder.decode([Recipe].self, from: data)
            sort()
        } catch {
            log.error("Recipe library unreadable, keeping a backup: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.moveItem(at: fileURL, to: directory.appending(path: "recipes-unreadable.json"))
            recipes = Self.bundledSamples()
            sortAndSave()
        }
    }

    private func sortAndSave() {
        sort()
        save()
    }

    private func sort() {
        recipes.sort { lhs, rhs in
            lhs.isPinned != rhs.isPinned ? lhs.isPinned : lhs.addedAt > rhs.addedAt
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(recipes).write(to: fileURL, options: .atomic)
        } catch {
            log.error("Saving recipes failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func saveState() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Self.encoder.encode(state).write(to: stateURL, options: .atomic)
        } catch {
            log.error("Saving library state failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func bundledSamples() -> [Recipe] {
        guard let url = Bundle.module.url(forResource: "SampleRecipes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([Recipe].self, from: data)) ?? []
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// What the library remembers besides the recipes: deleted pages and whether
/// the starter set was added.
private struct LibraryState: Codable {
    var deletedSources: Set<URL> = []
    var hasStarterSet = false
}
