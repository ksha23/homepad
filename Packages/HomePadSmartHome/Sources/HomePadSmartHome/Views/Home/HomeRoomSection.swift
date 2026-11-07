import HomePadCore
import HomePadUI
import SwiftUI

/// One group of the Home app (a room, Favorites or Other): the title with the
/// group's sensor readings beside it, then a tile for each accessory that has
/// something to control. On one room's page the room's cameras lead its tiles,
/// each as wide as a wide tile.
struct HomeRoomSection: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(\.proximity) private var proximity
    let title: String
    var systemImage: String?
    let accessories: [HomeAccessory]
    /// Snapshots shown before the accessory tiles. Each opens its camera full screen.
    var cameras: [HomeCamera] = []
    /// Names each sensor, for a group that mixes rooms.
    var namesSensors = false
    let onOpen: (HomeAccessory.ID) -> Void
    var onOpenCamera: (HomeCamera.ID) -> Void = { _ in }

    var body: some View {
        let sensors = accessories.filter { !AccessoryPresentation.isControllable($0) }
        let controls = accessories.filter(AccessoryPresentation.isControllable)
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                SectionHeader(title, systemImage: systemImage)
                if !sensors.isEmpty {
                    SensorStrip(sensors: sensors, showsNames: namesSensors, onOpen: onOpen)
                }
            }
            // Tiles tint themselves at night, the title and readings do not.
            .nightModeAware()
            if !controls.isEmpty || !cameras.isEmpty {
                // From arm's length seven columns on a 13-inch landscape screen and
                // six on an 11-inch, about as dense as Apple Home. Bigger from across the room.
                TileGridLayout(
                    minimumColumnWidth: proximity >= .mid ? 150 : 210,
                    rowHeight: proximity >= .mid ? 140 : 168,
                    spacing: Theme.Spacing.m
                ) {
                    ForEach(cameras) { camera in
                        // A snapshot, like the Cameras strip: live video starts full screen.
                        CameraTile(camera: camera, purpose: .still) { onOpenCamera(camera.id) }
                            .nightModeAware()
                            .tileSpan(TileSize.wide.columnSpan)
                    }
                    ForEach(controls) { accessory in
                        let size = service.layout.tileSize(for: accessory)
                        AccessoryTile(accessory: accessory, size: size) { onOpen(accessory.id) }
                            .tileSpan(size.columnSpan)
                    }
                }
            }
        }
    }
}
