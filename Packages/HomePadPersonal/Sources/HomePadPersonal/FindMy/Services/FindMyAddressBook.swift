import CoreLocation
import Foundation
import MapKit
import Observation

/// Street addresses for device locations, by reverse geocoding with MapKit.
/// Results are kept per spot (about 10 meters), so a device that has not moved
/// is never looked up twice, and only the card and the assistant ask, never
/// every list row. MapKit limits how often an app may geocode.
@MainActor
@Observable
final class FindMyAddressBook {
    /// Looks up one coordinate. Swapped for a fixed table in demo mode and tests.
    typealias Lookup = @MainActor (_ latitude: Double, _ longitude: Double) async -> String?

    private(set) var addresses: [String: String] = [:]
    @ObservationIgnored private var pending: [String: Task<String?, Never>] = [:]
    @ObservationIgnored private let lookup: Lookup

    init(lookup: @escaping Lookup = FindMyAddressBook.mapKitAddress) {
        self.lookup = lookup
    }

    /// The address already known for a spot, without looking it up.
    func cached(latitude: Double, longitude: Double) -> String? {
        addresses[Self.key(latitude, longitude)]
    }

    /// The address for a spot, looked up once and then kept.
    func address(latitude: Double, longitude: Double) async -> String? {
        let key = Self.key(latitude, longitude)
        if let known = addresses[key] { return known }
        if let running = pending[key] { return await running.value }
        let task = Task { await lookup(latitude, longitude) }
        pending[key] = task
        let result = await task.value
        pending[key] = nil
        if let result { addresses[key] = result }
        return result
    }

    /// Four decimals is about 11 meters, closer than the GPS is sure anyway.
    nonisolated static func key(_ latitude: Double, _ longitude: Double) -> String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }

    /// "120 State St, Madison" from MapKit, or nil offline.
    nonisolated static func mapKitAddress(latitude: Double, longitude: Double) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        guard let item = try? await MKReverseGeocodingRequest(location: location)?.mapItems.first else { return nil }
        return item.address?.shortAddress ?? item.addressRepresentations?.cityWithContext ?? item.name
    }
}
