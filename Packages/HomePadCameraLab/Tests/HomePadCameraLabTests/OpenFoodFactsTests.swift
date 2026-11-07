import Foundation
import Testing
@testable import HomePadCameraLab

@Suite struct OpenFoodFactsTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    @Test func decodesAFoundProduct() throws {
        let product = try #require(try OpenFoodFactsClient.decode(fixture("off-found-nutella")))
        #expect(product.code == "3017624010701")
        #expect(product.displayName == "Nutella")
        #expect(product.primaryBrand == "Ferrero")
        #expect(product.quantity == "400.0 g")
        #expect(product.imageURL?.host == "images.openfoodfacts.org")
    }

    @Test func decodesAUPCProduct() throws {
        let product = try #require(try OpenFoodFactsClient.decode(fixture("off-found-upc-soup")))
        #expect(product.displayName == "Beef & Vegetable Soup")
        #expect(product.primaryBrand == "Progresso")
        #expect(product.quantity == "18.5 oz.")
    }

    @Test func notFoundIsNil() throws {
        #expect(try OpenFoodFactsClient.decode(fixture("off-not-found")) == nil)
        let response = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: fixture("off-not-found"))
        #expect(!response.found)
        #expect(response.statusVerbose == "product not found")
    }

    @Test func blankNamesFallBackToTheFirstBrand() throws {
        let product = try #require(try OpenFoodFactsClient.decode(fixture("off-found-brand-only")))
        #expect(product.displayName == "Fleischer")
    }

    @Test func acceptsNewerStringStatus() throws {
        let product = try #require(try OpenFoodFactsClient.decode(fixture("off-v3-success")))
        #expect(product.displayName == "Nutella")
        #expect(product.imageURL == nil)
    }

    @Test func malformedJSONThrows() {
        #expect(throws: DecodingError.self) { try OpenFoodFactsClient.decode(Data("{\"status\": 1, \"product\": 7}".utf8)) }
    }

    @Test func validatesGTINCheckDigits() {
        #expect(Barcode.isPlausibleGTIN("3017624010701"))   // EAN-13
        #expect(Barcode.isPlausibleGTIN("041196910759"))    // UPC-A
        #expect(Barcode.isPlausibleGTIN("96385074"))        // EAN-8
        #expect(!Barcode.isPlausibleGTIN("3017624010702"))  // wrong check digit
        #expect(!Barcode.isPlausibleGTIN("30176240107"))    // wrong length
        #expect(!Barcode.isPlausibleGTIN("30176240107a1"))  // not digits
    }

    @MainActor
    @Test func groceryItemTitleCountsRepeats() {
        var item = GroceryItem(barcode: "3017624010701", name: "Nutella", status: .added)
        #expect(item.reminderTitle == "Nutella")
        item.count = 3
        #expect(item.reminderTitle == "Nutella ×3")
        #expect(!item.canUndo)
        item.status = .pending(commitAt: Date())
        #expect(item.canUndo)
    }
}
