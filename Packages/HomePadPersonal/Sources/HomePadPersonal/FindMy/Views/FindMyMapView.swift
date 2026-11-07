import HomePadCore
import HomePadUI
import MapKit
import SwiftUI

/// The live map: a pin for each device with a location, the zones as faint
/// circles with a house at home, and the selected device's accuracy circle.
///
/// MapKit draws only when something changes, and the pins have no motion of
/// their own, so the map is still while nothing moves. A tracker update from
/// Home Assistant moves its pin once. Pins that would overlap at the current
/// zoom fan out (`FindMyPinSpread`), worked out each time the map stops moving.
struct FindMyMapView: View {
    let devices: [FindMyDevice]
    let zones: [HomeZone]
    @Binding var selection: TrackedDevice.ID?
    @Binding var position: MapCameraPosition
    /// Told where the map came to rest after it moved.
    var onSettle: (MKCoordinateRegion) -> Void = { _ in }
    @State private var metersPerPoint: Double = 0
    @State private var mapWidth: CGFloat = 0
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let spread = FindMyPinSpread.coordinates(for: pins, metersPerPoint: metersPerPoint)
        Map(position: $position, selection: $selection) {
            ForEach(zones) { zone in
                MapCircle(center: zone.coordinate, radius: zone.radius)
                    .foregroundStyle(zoneInk.opacity(0.08))
                    .stroke(zoneInk.opacity(0.35), lineWidth: 1)
                if zone.isHome {
                    Annotation(zone.name, coordinate: zone.coordinate) { FindMyHomeMarker() }
                        .annotationTitles(.hidden)
                }
            }
            if let selected = devices.first(where: { $0.id == selection }), let coordinate = selected.tracked.coordinate,
               let accuracy = selected.tracked.accuracy {
                MapCircle(center: coordinate, radius: accuracy)
                    .foregroundStyle(selected.tint.opacity(0.18))
                    .stroke(selected.tint.opacity(0.6), lineWidth: 1)
            }
            ForEach(devices) { device in
                if let coordinate = spread[device.id].map(\.coordinate) ?? device.tracked.coordinate {
                    Annotation(device.title, coordinate: coordinate, anchor: .center) {
                        FindMyPin(device: device, isSelected: device.id == selection)
                    }
                    .annotationTitles(.hidden)
                    .tag(device.id)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { mapWidth = $0 }
        .onMapCameraChange(frequency: .onEnd) { context in
            onSettle(context.region)
            guard mapWidth > 0 else { return }
            let meters = context.rect.width / MKMapPointsPerMeterAtLatitude(context.region.center.latitude)
            metersPerPoint = meters / Double(mapWidth)
        }
    }

    /// Zones are drawn in the ink of the map: white on the dark map, black on
    /// the light one. MapKit content takes plain colors, not `.primary`.
    private var zoneInk: Color { colorScheme == .dark ? .white : .black }

    private var pins: [FindMyPinSpread.Pin] {
        devices.compactMap { device in
            guard let latitude = device.tracked.latitude, let longitude = device.tracked.longitude else { return nil }
            return FindMyPinSpread.Pin(id: device.id, latitude: latitude, longitude: longitude)
        }
    }
}

extension FindMyPinSpread.Pin {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension TrackedDevice {
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension HomeZone {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

extension FindMyDevice {
    /// The owner's member color, else white.
    var tint: Color {
        colorHex.map { Color(hex: $0) } ?? .white
    }
}

/// The camera positions Find My moves between.
enum FindMyCamera {
    /// Every device in view, with some room around them. Zones count only
    /// when no device has a location.
    static func overview(devices: [FindMyDevice], zones: [HomeZone]) -> MapCameraPosition {
        var coordinates = devices.compactMap(\.tracked.coordinate)
        if coordinates.isEmpty { coordinates = zones.map(\.coordinate) }
        guard let first = coordinates.first else { return .automatic }
        var minLatitude = first.latitude, maxLatitude = first.latitude
        var minLongitude = first.longitude, maxLongitude = first.longitude
        for coordinate in coordinates {
            minLatitude = min(minLatitude, coordinate.latitude)
            maxLatitude = max(maxLatitude, coordinate.latitude)
            minLongitude = min(minLongitude, coordinate.longitude)
            maxLongitude = max(maxLongitude, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLatitude - minLatitude) * 1.6, 0.008),
                                    longitudeDelta: max((maxLongitude - minLongitude) * 1.6, 0.008))
        return .region(MKCoordinateRegion(center: center, span: span))
    }

    /// Close on one device: a few blocks across, or more when its location is rough.
    static func focus(on device: TrackedDevice) -> MapCameraPosition? {
        guard let coordinate = device.coordinate else { return nil }
        let span = max(800, (device.accuracy ?? 0) * 6)
        return .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: span, longitudinalMeters: span))
    }
}
