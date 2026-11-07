import Foundation
import HomePadCore
import Observation

/// Which screen the Recipes app shows.
public enum RecipesScreen: Equatable, Sendable {
    case library
    case recipe
    case cooking
    /// The week's meal plan.
    case mealPlan
}

/// Progress of the latest recipe import, shown as a banner in the Recipes app.
public enum RecipeImportStatus: Equatable, Sendable {
    case working(String)
    case imported(String)
    case failed(String)
}

/// Shared kitchen state behind the Recipes app, the assistant tools, the widgets
/// and the event handlers. Created once by `KitchenModule`.
@MainActor
@Observable
public final class KitchenContext {
    public let library: RecipeLibrary
    /// Recipes planned for days, saved beside the library.
    public let mealPlan: MealPlanStore
    /// Searching the online catalog, from the library's search field or the assistant.
    public let search: RecipeSearch
    /// The picks on the Discover shelf.
    public let discovery: RecipeDiscovery
    public var screen: RecipesScreen = .library
    /// The week the meal plan shows.
    public var mealPlanWeek = MealWeek.current()
    /// The week's merged shopping list is showing over the meal plan.
    public var showsMealPlanGroceries = false
    /// Where Back on a recipe's card goes: the library, or the meal plan it
    /// was opened from.
    public private(set) var recipeOrigin: RecipesScreen = .library
    public private(set) var session: RecipeSession?
    public var importStatus: RecipeImportStatus?
    /// A catalog recipe shown in the preview sheet, before anyone saves it.
    public var previewedResult: CatalogRecipe?
    /// Set by the Recipes app while it is on screen, so Handoff only offers a
    /// recipe someone is looking at.
    public var isRecipesAppVisible = false

    @ObservationIgnored let chime = ChimePlayer()
    @ObservationIgnored let catalog: any RecipeCatalog
    @ObservationIgnored private let importer: RecipeImporter
    @ObservationIgnored private(set) weak var services: AppServices?
    @ObservationIgnored private var preparing: Task<Void, Never>?
    @ObservationIgnored private var hasRestored = false

    /// - Parameter catalog: Where search, Discover and the starter recipes come from.
    ///   TheMealDB by default, with the optional supporter key from the keychain.
    public init(services: AppServices?, library: RecipeLibrary? = nil, mealPlan: MealPlanStore? = nil,
                importer: RecipeImporter? = nil, catalog: (any RecipeCatalog)? = nil) {
        self.services = services
        let library = library ?? RecipeLibrary()
        self.library = library
        self.mealPlan = mealPlan ?? MealPlanStore(directory: library.directory)
        let keychain = services?.keychain
        let catalog = catalog ?? MealDBCatalog(supporterKey: { keychain?.string(for: KitchenSecrets.mealDBKey) })
        self.catalog = catalog
        self.importer = importer ?? RecipeImporter(catalog: catalog)
        search = RecipeSearch(catalog: catalog)
        discovery = RecipeDiscovery(catalog: catalog)
    }

    /// Adds the starter recipes on first launch and fills Discover, in the
    /// background. Safe to call whenever the Recipes app appears.
    public func prepareRecipes() {
        guard preparing == nil else { return }
        preparing = Task { [weak self] in
            guard let self else { return }
            await RecipeStarterSet.add(to: library, from: catalog)
            await discovery.refreshIfStale()
            preparing = nil
        }
    }

    // MARK: Navigation

    /// Shows a recipe's card and asks the shell to bring the Recipes app forward.
    /// - Parameters:
    ///   - servings: Servings to show, such as a planned meal's. Nil keeps the
    ///     open recipe's, or starts from the default.
    ///   - origin: Where Back goes: the library, or the meal plan.
    public func open(_ recipe: Recipe, servings: Int? = nil, from origin: RecipesScreen = .library, bringToFront: Bool = false) {
        if session?.recipe.id != recipe.id {
            let settings = services?.settings
            session = RecipeSession(
                recipe: recipe,
                defaultServings: settings?[KitchenSettings.defaultServings] ?? 0,
                unitSystem: settings?[KitchenSettings.unitSystem] ?? .original)
        }
        if let servings, let session, session.canScale { session.servings = servings }
        recipeOrigin = origin == .mealPlan ? .mealPlan : .library
        screen = .recipe
        if bringToFront { services?.events.post(.openApp(id: KitchenModule.recipesAppID)) }
    }

    /// Brings the Recipes app forward on its library, where search results
    /// show. Cooking mode stays put so a search never interrupts it.
    public func showLibrary() {
        if screen != .cooking { screen = .library }
        services?.events.post(.openApp(id: KitchenModule.recipesAppID))
    }

    public func startCooking() {
        guard session != nil else { return }
        screen = .cooking
    }

    public func stopCooking() {
        screen = session == nil ? .library : .recipe
    }

    /// Back from a recipe's card, to the library or the meal plan it came from.
    public func closeRecipe() {
        session = nil
        screen = recipeOrigin
        recipeOrigin = .library
    }

    /// Shows the meal plan, on a week when one is given. Cooking mode stays
    /// put, so the assistant planning a meal never interrupts it.
    public func showMealPlan(_ week: MealWeek? = nil, bringToFront: Bool = false) {
        if let week { mealPlanWeek = week }
        if screen != .cooking {
            session = nil
            recipeOrigin = .library
            screen = .mealPlan
        }
        if bringToFront { services?.events.post(.openApp(id: KitchenModule.recipesAppID)) }
    }

    /// Back from the meal plan to the library.
    public func closeMealPlan() {
        screen = .library
    }

    // MARK: Reopening

    /// Reopens the recipe left open before HomePad last quit, in cooking mode
    /// on the same step while that is still recent. Once per launch, and only
    /// when nothing else (the assistant, an import, a launch argument) has
    /// opened a recipe since.
    func restoreIfNeeded() {
        guard !hasRestored else { return }
        hasRestored = true
        guard session == nil, screen == .library, let appState = services?.appState else { return }
        if let start = appState[KitchenAppState.mealPlanWeek] { mealPlanWeek = MealWeek(containing: start) }
        let wasPlanning = appState[KitchenAppState.mealPlanOpen]
        guard let id = appState[KitchenAppState.openRecipe], let recipe = library.recipe(id) else {
            if wasPlanning { screen = .mealPlan }
            return
        }
        open(recipe, from: wasPlanning ? .mealPlan : .library)
        if let step = appState[KitchenAppState.cookingStep] {
            startCooking()
            session?.go(to: step)
        }
    }

    /// Saves the open recipe, the cooking step and the meal plan's week, for
    /// the next launch. The Recipes app calls it as it appears and whenever
    /// any of them changes.
    func saveOpenRecipe() {
        guard let appState = services?.appState else { return }
        let showsRecipe = screen == .recipe || screen == .cooking
        appState[KitchenAppState.openRecipe] = showsRecipe ? session?.recipe.id : nil
        appState[KitchenAppState.cookingStep] = screen == .cooking ? session?.stepIndex : nil
        appState[KitchenAppState.mealPlanOpen] = screen == .mealPlan || (showsRecipe && recipeOrigin == .mealPlan)
        appState[KitchenAppState.mealPlanWeek] = mealPlanWeek == .current() ? nil : mealPlanWeek.start
    }

    // MARK: Saving

    /// Where every way in ends: a link, scanned text, a search result and the
    /// assistant. Saves into the library, says so in the status line and opens
    /// the card unless the person is still browsing.
    @discardableResult
    public func save(_ recipe: Recipe, open shouldOpen: Bool = true) -> Recipe {
        var recipe = recipe
        recipe.addedAt = Date()
        let stored = library.add(recipe)
        importStatus = .imported(stored.title)
        if shouldOpen { open(stored, bringToFront: true) }
        return stored
    }

    /// The saved copy of a catalog recipe, if it is in the library.
    public func savedRecipe(for result: CatalogRecipe) -> Recipe? {
        library.recipe(withSource: result.recipe.sourceURL)
    }

    /// Shows a catalog recipe's preview sheet in the Recipes app.
    public func preview(_ result: CatalogRecipe, bringToFront: Bool = false) {
        previewedResult = result
        if bringToFront { services?.events.post(.openApp(id: KitchenModule.recipesAppID)) }
    }

    // MARK: Importing

    /// Imports from a link, saves it and opens it. Errors show in the status line.
    @discardableResult
    public func importRecipe(link: String) async -> Recipe? {
        importStatus = .working("Reading the recipe…")
        do {
            return save(try await importer.importRecipe(from: link))
        } catch {
            importStatus = .failed(error.localizedDescription)
            return nil
        }
    }

    /// Imports from scanned or pasted text, with the AI provider when one is set up.
    @discardableResult
    public func importRecipe(text: String) async -> Recipe? {
        importStatus = .working("Organizing the recipe…")
        do {
            return save(try await importer.importRecipe(fromText: text, assistant: services?.assistant))
        } catch {
            importStatus = .failed(error.localizedDescription)
            return nil
        }
    }

    // MARK: Cooking helpers

    /// Starts a labeled timer for a time found in a step.
    @discardableResult
    public func startTimer(for duration: DetectedDuration, in step: RecipeStep) -> HomeTimer? {
        guard let services, let session else { return nil }
        let choice = services.settings[KitchenSettings.rangedTime]
        let seconds = choice == .longest ? duration.upperBound : duration.lowerBound
        return services.timers.start(duration: seconds, label: session.timerLabel(for: step, duration: duration))
    }

    /// Adds every unticked ingredient to the Groceries reminders list. Returns how many were added.
    public func addMissingToGroceries() async throws -> Int {
        guard session != nil else { return 0 }
        return try await addToGroceries(session?.missingIngredients ?? [])
    }

    /// The reminders list Kitchen adds to, the same one the grocery scanner and
    /// the assistant fill out of the box. Personal shares it with everyone.
    public static let groceryListName = "Groceries"

    /// Adds each line to the Groceries list, in order. Returns how many were added.
    @discardableResult
    public func addToGroceries(_ titles: [String]) async throws -> Int {
        guard let services else { return 0 }
        for title in titles {
            try await services.calendar.addReminder(title: title, due: nil, listName: Self.groceryListName)
        }
        return titles.count
    }

    /// The matching keys (`GroceryMerger.key(forListItem:)`) of what is still
    /// to buy on the Groceries list. Checked-off items do not count.
    public func openGroceryKeys() async -> Set<String> {
        guard let calendar = services?.calendar else { return [] }
        let lists = await calendar.reminderLists()
        guard let list = lists.first(where: { $0.title.localizedCaseInsensitiveCompare(Self.groceryListName) == .orderedSame }) else {
            return []
        }
        let open = await calendar.reminders(includeCompleted: false).filter { $0.listID == list.id && !$0.isCompleted }
        return Set(open.compactMap { GroceryMerger.key(forListItem: $0.title) })
    }

    // MARK: Events

    /// Reacts to imports requested by other modules and to a raised palm.
    func handle(_ event: HomePadEvent) {
        switch event {
        case .custom(name: KitchenModule.importURLEvent, payload: .string(let link)):
            Task { await importRecipe(link: link) }
        case .custom(name: KitchenModule.importTextEvent, payload: .string(let text)):
            Task { await importRecipe(text: text) }
        case .gesture(.openPalm):
            // A raised palm stops ringing timers, like the Stop button. It wins over
            // the assistant and music, which leave it alone while one rings.
            guard let services else { return }
            for timer in services.timers.timers where timer.status == .finished { services.timers.cancel(timer.id) }
        default:
            break
        }
    }

    // MARK: Handoff

    /// Tells the Connect module which recipe is on screen, so a nearby iPhone or
    /// Mac can continue it (Handoff). Stops advertising when no recipe is shown.
    func updateHandoff() {
        guard let services else { return }
        if isRecipesAppVisible, screen != .library, let recipe = session?.recipe {
            services.events.post(.handoffRecipe(title: recipe.title, url: recipe.sourceURL))
        } else {
            services.events.post(.custom(name: ConnectEventName.handoffRecipe, payload: .null))
        }
    }
}
