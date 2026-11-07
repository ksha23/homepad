import Foundation
import HomePadCore
import Observation

/// One saved recipe planned for a day.
public struct PlannedMeal: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var day: MealDay
    public var recipeID: Recipe.ID
    /// How many to cook for. Nil for a recipe that does not say how many it
    /// serves, which is cooked and shopped for as written.
    public var servings: Int?

    public init(id: UUID = UUID(), day: MealDay, recipeID: Recipe.ID, servings: Int?) {
        self.id = id
        self.day = day
        self.recipeID = recipeID
        self.servings = servings
    }
}

/// The household's meal plan, saved as JSON next to the recipe library in
/// Application Support, so it stays on this iPad and belongs to everyone in
/// the kitchen, like the recipes it points to.
@MainActor
@Observable
public final class MealPlanStore {
    /// In the order they were planned. Meals on one day keep that order.
    public private(set) var meals: [PlannedMeal] = []

    @ObservationIgnored private let directory: URL
    private let log = Log.make("Kitchen.MealPlan")

    /// - Parameter directory: Folder for `meal-plan.json`. Defaults to the
    ///   recipe library's folder.
    public init(directory: URL? = nil) {
        self.directory = directory ?? RecipeLibrary.defaultDirectory
        load()
    }

    private var fileURL: URL { directory.appending(path: "meal-plan.json") }

    // MARK: Queries

    public func meals(on day: MealDay) -> [PlannedMeal] {
        meals.filter { $0.day == day }
    }

    /// Meals from one day through another, by day and then in planned order.
    public func meals(from first: MealDay, through last: MealDay) -> [PlannedMeal] {
        meals.enumerated()
            .filter { first <= $0.element.day && $0.element.day <= last }
            .sorted { ($0.element.day, $0.offset) < ($1.element.day, $1.offset) }
            .map(\.element)
    }

    public func meal(_ id: PlannedMeal.ID) -> PlannedMeal? {
        meals.first { $0.id == id }
    }

    // MARK: Changes

    @discardableResult
    public func add(recipeID: Recipe.ID, on day: MealDay, servings: Int?) -> PlannedMeal {
        let meal = PlannedMeal(day: day, recipeID: recipeID, servings: servings)
        meals.append(meal)
        save()
        return meal
    }

    /// Changes a meal's servings, or moves it to another day, where it goes last.
    public func update(_ meal: PlannedMeal) {
        guard let index = meals.firstIndex(where: { $0.id == meal.id }) else { return }
        if meals[index].day != meal.day {
            meals.remove(at: index)
            meals.append(meal)
        } else {
            meals[index] = meal
        }
        save()
    }

    public func remove(_ id: PlannedMeal.ID) {
        meals.removeAll { $0.id == id }
        save()
    }

    public func removeAll(where shouldRemove: (PlannedMeal) -> Bool) {
        let before = meals.count
        meals.removeAll(where: shouldRemove)
        if meals.count != before { save() }
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            meals = try JSONDecoder().decode([PlannedMeal].self, from: data)
        } catch {
            log.error("Meal plan unreadable, keeping a backup: \(error.localizedDescription, privacy: .public)")
            try? FileManager.default.moveItem(at: fileURL, to: directory.appending(path: "meal-plan-unreadable.json"))
        }
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(meals).write(to: fileURL, options: .atomic)
        } catch {
            log.error("Saving the meal plan failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
