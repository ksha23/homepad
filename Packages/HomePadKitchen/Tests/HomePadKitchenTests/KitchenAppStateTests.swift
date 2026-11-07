import Foundation
import HomePadCore
import Testing
@testable import HomePadKitchen

/// After a relaunch the Recipes app reopens the recipe that was open, and
/// cooking mode on its step while that is recent. Anything that opened a
/// recipe first wins.
@MainActor
@Suite struct KitchenAppStateTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "kitchen-appstate-\(UUID().uuidString)")
    let defaults = UserDefaults(suiteName: "test.kitchen.appstate.\(UUID())")!
    /// The context holds its services weakly, as the app keeps them for good.
    private let launched = Launches()

    private final class Launches {
        var services: [AppServices] = []
    }

    /// A context as after a launch: new services over the same saved settings,
    /// and the same recipe library on disk.
    private func launch() -> (KitchenContext, AppServices) {
        let services = AppServices(settings: SettingsStore(defaults: defaults))
        launched.services.append(services)
        return (KitchenContext(services: services, library: RecipeLibrary(directory: directory)), services)
    }

    private func recipe(_ context: KitchenContext, _ title: String) throws -> Recipe {
        try #require(context.library.find(named: title))
    }

    @Test func aRelaunchReopensTheOpenRecipe() throws {
        let (first, _) = launch()
        first.open(try recipe(first, "butternut squash soup"))
        first.saveOpenRecipe()
        let (second, _) = launch()
        second.restoreIfNeeded()
        #expect(second.screen == .recipe)
        #expect(second.session?.recipe.title == "Butternut Squash Soup")
    }

    @Test func cookingModeComesBackOnItsStepWhileRecent() throws {
        let (first, _) = launch()
        first.open(try recipe(first, "butternut squash soup"))
        first.startCooking()
        first.session?.go(to: 2)
        first.saveOpenRecipe()
        let (second, _) = launch()
        second.restoreIfNeeded()
        #expect(second.screen == .cooking)
        #expect(second.session?.stepIndex == 2)
    }

    @Test func anOldCookingStepReopensTheCardInstead() throws {
        let (first, services) = launch()
        let soup = try recipe(first, "butternut squash soup")
        services.appState[KitchenAppState.openRecipe] = soup.id
        services.appState.set(2, for: KitchenAppState.cookingStep, now: Date().addingTimeInterval(-AppStateStore.timePositionLifetime - 60))
        let (second, _) = launch()
        second.restoreIfNeeded()
        #expect(second.screen == .recipe)
        #expect(second.session?.recipe.id == soup.id)
    }

    @Test func aClosedRecipeReopensTheLibrary() throws {
        let (first, _) = launch()
        first.open(try recipe(first, "butternut squash soup"))
        first.saveOpenRecipe()
        first.closeRecipe()
        first.saveOpenRecipe()
        let (second, _) = launch()
        second.restoreIfNeeded()
        #expect(second.screen == .library)
        #expect(second.session == nil)
    }

    /// The assistant, an import or a launch argument opened something before
    /// the Recipes app appeared: that stays.
    @Test func aRecipeOpenedByRequestWins() throws {
        let (first, _) = launch()
        first.open(try recipe(first, "butternut squash soup"))
        first.saveOpenRecipe()
        let (second, _) = launch()
        let other = try #require(second.library.recipes.first { $0.title != "Butternut Squash Soup" })
        second.open(other)
        second.restoreIfNeeded()
        #expect(second.session?.recipe.id == other.id)
    }
}
