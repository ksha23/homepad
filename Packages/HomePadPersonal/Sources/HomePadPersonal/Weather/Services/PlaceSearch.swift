import CoreLocation
import Foundation
import MapKit

/// City search and naming through MapKit geocoding. Results carry a time zone,
/// so the World Clock uses the same search to add cities.
@MainActor
enum PlaceSearch {
    /// One search hit with a disambiguating second line ("Madison, WI").
    struct Result: Identifiable, Hashable {
        var id: String { "\(place.name)|\(Int(place.latitude * 10))|\(Int(place.longitude * 10))" }
        let place: WeatherPlace
        let detail: String?
    }

    /// Places matching a typed query such as "Madison" or "Kyoto, Japan".
    static func search(_ query: String) async -> [Result] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, let request = MKGeocodingRequest(addressString: trimmed) else { return [] }
        let items = (try? await request.mapItems) ?? []
        var seen = Set<String>()
        return items.compactMap { item in
            let result = Result(place: place(from: item, fallbackName: trimmed), detail: item.addressRepresentations?.cityWithContext)
            return seen.insert(result.id).inserted ? result : nil
        }
    }

    /// Names a coordinate ("Madison") by reverse geocoding. Falls back to "Current Location".
    static func place(for location: CLLocation) async -> WeatherPlace {
        let item = try? await MKReverseGeocodingRequest(location: location)?.mapItems.first
        guard let item else {
            return WeatherPlace(name: "Current Location", latitude: location.coordinate.latitude,
                                longitude: location.coordinate.longitude, timeZoneID: TimeZone.current.identifier)
        }
        var place = place(from: item, fallbackName: "Current Location")
        place.latitude = location.coordinate.latitude
        place.longitude = location.coordinate.longitude
        return place
    }

    private static func place(from item: MKMapItem, fallbackName: String) -> WeatherPlace {
        let representations = item.addressRepresentations
        let name = representations?.cityName ?? item.name ?? fallbackName
        return WeatherPlace(
            name: name,
            latitude: item.location.coordinate.latitude,
            longitude: item.location.coordinate.longitude,
            timeZoneID: item.timeZone?.identifier
        )
    }
}
