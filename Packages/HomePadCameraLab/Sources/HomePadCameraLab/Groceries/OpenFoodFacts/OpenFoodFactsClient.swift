import Foundation

/// Looks up grocery barcodes in Open Food Facts, a free and open database.
/// No account or key is needed. Only the barcode leaves the iPad.
struct OpenFoodFactsClient: Sendable {
    enum LookupError: LocalizedError {
        case invalidBarcode
        case network(String)

        var errorDescription: String? {
            switch self {
            case .invalidBarcode: "That does not look like a grocery barcode."
            case .network(let message): message
            }
        }
    }

    var session: URLSession = .shared
    var baseURL = URL(string: "https://world.openfoodfacts.org/api/v2/product/")!
    /// Open Food Facts asks apps to identify themselves.
    static let userAgent = "HomePad/0.1 (iPadOS smart display)"
    static let fields = "code,product_name,product_name_en,generic_name,brands,quantity,image_front_small_url"

    /// The product, or nil when the database does not know the barcode.
    func product(for barcode: String) async throws -> OpenFoodFactsProduct? {
        guard Barcode.isPlausibleGTIN(barcode) else { throw LookupError.invalidBarcode }
        var components = URLComponents(url: baseURL.appendingPathComponent("\(barcode).json"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]
        guard let url = components?.url else { throw LookupError.invalidBarcode }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await session.data(for: request)
            // A missing product comes back as HTTP 404 with a normal JSON body.
            return try Self.decode(data)
        } catch let error as DecodingError {
            throw LookupError.network("Open Food Facts sent an unexpected answer. \(error.localizedDescription)")
        } catch {
            throw LookupError.network(error.localizedDescription)
        }
    }

    static func decode(_ data: Data) throws -> OpenFoodFactsProduct? {
        let response = try JSONDecoder().decode(OpenFoodFactsResponse.self, from: data)
        return response.found ? response.product : nil
    }
}

/// Barcode helpers for grocery GTINs (EAN-8, UPC-A, EAN-13, GTIN-14).
enum Barcode {
    /// Digits only, a GTIN length, and a valid check digit.
    static func isPlausibleGTIN(_ code: String) -> Bool {
        let digits = code.compactMap(\.wholeNumberValue)
        guard digits.count == code.count, [8, 12, 13, 14].contains(digits.count) else { return false }
        let body = digits.dropLast()
        let sum = body.reversed().enumerated().reduce(0) { total, item in
            total + item.element * (item.offset.isMultiple(of: 2) ? 3 : 1)
        }
        return (10 - sum % 10) % 10 == digits.last
    }
}
