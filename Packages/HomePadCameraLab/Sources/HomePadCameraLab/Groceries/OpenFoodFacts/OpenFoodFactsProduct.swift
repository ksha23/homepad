import Foundation

/// A product from the free Open Food Facts database.
struct OpenFoodFactsProduct: Decodable, Equatable, Sendable {
    var code: String?
    var productName: String?
    var productNameEnglish: String?
    var genericName: String?
    var brands: String?
    var quantity: String?
    var imageURL: URL?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case productNameEnglish = "product_name_en"
        case genericName = "generic_name"
        case brands
        case quantity
        case imageURL = "image_front_small_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        productName = try container.decodeIfPresent(String.self, forKey: .productName)
        productNameEnglish = try container.decodeIfPresent(String.self, forKey: .productNameEnglish)
        genericName = try container.decodeIfPresent(String.self, forKey: .genericName)
        brands = try container.decodeIfPresent(String.self, forKey: .brands)
        quantity = try container.decodeIfPresent(String.self, forKey: .quantity)
        imageURL = (try? container.decodeIfPresent(String.self, forKey: .imageURL)).flatMap { URL(string: $0) }
    }

    /// The best name for a shopping list: English name, then the local name,
    /// then the generic name, then the first brand.
    var displayName: String? {
        [productNameEnglish, productName, genericName, primaryBrand]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    /// The first brand in the comma-separated list.
    var primaryBrand: String? {
        brands?.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// The `/api/v2/product/<barcode>.json` response envelope.
struct OpenFoodFactsResponse: Decodable, Sendable {
    var code: String?
    /// True when the database knows the barcode.
    var found: Bool
    var statusVerbose: String?
    var product: OpenFoodFactsProduct?

    enum CodingKeys: String, CodingKey {
        case code, status, product
        case statusVerbose = "status_verbose"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decodeIfPresent(String.self, forKey: .code)
        statusVerbose = try container.decodeIfPresent(String.self, forKey: .statusVerbose)
        product = try container.decodeIfPresent(OpenFoodFactsProduct.self, forKey: .product)
        // v2 sends 1 or 0. Newer API versions send "success" or "failure".
        if let number = try? container.decode(Int.self, forKey: .status) {
            found = number == 1
        } else if let text = try? container.decode(String.self, forKey: .status) {
            found = text == "success" || text == "success_with_warnings"
        } else {
            found = false
        }
        if product == nil { found = false }
    }
}
