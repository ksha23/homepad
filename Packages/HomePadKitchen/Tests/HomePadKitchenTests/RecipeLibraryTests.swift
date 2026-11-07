import Foundation
import HomePadCore
import Testing
@testable import HomePadKitchen

@MainActor
@Suite struct RecipeLibraryTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "kitchen-library-\(UUID().uuidString)")

    @Test func firstLaunchSeedsSamples() {
        let library = RecipeLibrary(directory: directory)
        #expect(library.recipes.map(\.title).contains("Butternut Squash Soup"))
        #expect(library.recipes.first?.isPinned == true)
        let soup = library.find(named: "butternut squash soup")
        #expect(soup?.servings == 4)
        #expect(soup?.displayTime == 2100)
    }

    @Test func libraryPersistsAcrossLaunches() {
        let first = RecipeLibrary(directory: directory)
        let added = first.add(Recipe(title: "Tacos", sourceURL: URL(string: "https://tacos.example/a"),
                                     ingredients: ["1 lb beef"], sections: [RecipeSection(steps: ["Cook."])]))
        first.togglePin(added.id)
        let second = RecipeLibrary(directory: directory)
        #expect(second.recipe(added.id)?.title == "Tacos")
        #expect(second.recipe(added.id)?.isPinned == true)
    }

    @Test func reimportingAPageReplacesItAndKeepsPin() {
        let library = RecipeLibrary(directory: directory)
        let url = URL(string: "https://pie.example/apple")
        let first = library.add(Recipe(title: "Apple Pie", sourceURL: url, sections: [RecipeSection(steps: ["Bake."])]))
        library.togglePin(first.id)
        let second = library.add(Recipe(title: "Apple Pie (updated)", sourceURL: url, sections: [RecipeSection(steps: ["Bake."])]))
        #expect(second.id == first.id)
        #expect(second.isPinned)
        #expect(library.recipes.filter { $0.sourceURL == url }.count == 1)
    }

    @Test func findsBySpokenName() {
        let library = RecipeLibrary(directory: directory)
        #expect(library.find(named: "french toast")?.title == "Brioche French Toast")
        #expect(library.find(named: "the squash soup please")?.title == "Butternut Squash Soup")
        #expect(library.find(named: "lasagna") == nil)
    }

    @Test func recipeOfTheDayIsStableWithinADay() {
        let library = RecipeLibrary(directory: directory)
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        let evening = morning.addingTimeInterval(6 * 3600)
        #expect(library.recipeOfTheDay(on: morning)?.id == library.recipeOfTheDay(on: evening)?.id)
    }

    @Test func photoIsStoredNextToLibrary() throws {
        let library = RecipeLibrary(directory: directory)
        let recipe = try #require(library.recipes.first)
        library.setPhoto(Data([0xFF, 0xD8, 0xFF]), for: recipe.id)
        let updated = try #require(library.recipe(recipe.id))
        let url = try #require(library.localImageURL(for: updated))
        #expect(FileManager.default.fileExists(atPath: url.path()))
        library.delete(recipe.id)
        #expect(!FileManager.default.fileExists(atPath: url.path()))
    }

    @Test func sampleRecipesHaveTimersAndAmountsInSteps() throws {
        let soup = try #require(RecipeLibrary.bundledSamples().first)
        let durations = soup.steps.flatMap { DurationExtractor.extract(from: $0.text) }
        #expect(durations.count >= 5)
        let amounts = soup.steps.flatMap { QuantityParser.findMeasured(in: $0.text) }
        #expect(amounts.count >= 4)
    }
}
