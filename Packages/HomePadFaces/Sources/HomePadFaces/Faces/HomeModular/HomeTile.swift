import HomePadCore
import SwiftUI

/// One tile on the Home Modular face.
enum HomeTile: Identifiable {
    case clock
    case accessory(HomeAccessory)
    case camera(HomeCamera)
    case intercom
    case scene(HomeScene)
    case home

    var id: String {
        switch self {
        case .clock: "clock"
        case .accessory(let accessory): "accessory:\(accessory.id)"
        case .camera(let camera): "camera:\(camera.id)"
        case .intercom: "intercom"
        case .scene(let scene): "scene:\(scene.id)"
        case .home: "home"
        }
    }

    /// Thermostats take two cells so their up and down buttons are easy to hit.
    var width: Int {
        if case .accessory(let accessory) = self, accessory.kind == .thermostat { return 2 }
        return 1
    }

    /// The tiles for a home, in the order HomeView fills its grid: the clock,
    /// favorite accessories, a camera, Intercom, scenes, then the Home app.
    ///
    /// - Parameters:
    ///   - chosen: Tile IDs from the face's slots, in slot order. Accessories
    ///     and scenes that no longer exist are skipped. When none is left, the
    ///     face shows the favorites and the first scenes, as it always has.
    ///   - camera: The camera the clock and camera style shows. Nil, or one that
    ///     no longer exists, shows the first camera.
    static func tiles(favorites: [HomeAccessory], cameras: [HomeCamera], scenes: [HomeScene],
                      includesClockAndCamera: Bool, accessories: [HomeAccessory] = [],
                      chosen: [String] = [], camera cameraID: String? = nil) -> [HomeTile] {
        var tiles: [HomeTile] = []
        if includesClockAndCamera { tiles.append(.clock) }
        let picked = resolve(chosen, accessories: accessories, scenes: scenes)
        let camera = includesClockAndCamera ? Self.camera(cameraID, in: cameras) : nil
        if picked.isEmpty {
            let thermostats = favorites.filter { $0.kind == .thermostat }
            tiles += thermostats.prefix(1).map(HomeTile.accessory)
            tiles.append(.intercom)
            if let camera { tiles.append(.camera(camera)) }
            tiles += favorites.filter { $0.kind != .thermostat }.map(HomeTile.accessory)
            tiles += scenes.prefix(3).map(HomeTile.scene)
        } else {
            tiles.append(.intercom)
            if let camera { tiles.append(.camera(camera)) }
            tiles += picked
        }
        tiles.append(.home)
        return tiles
    }

    /// The accessories and scenes for tile IDs, in order, each once, skipping
    /// IDs that match nothing.
    static func resolve(_ ids: [String], accessories: [HomeAccessory], scenes: [HomeScene]) -> [HomeTile] {
        let candidates = accessories.map(HomeTile.accessory) + scenes.map(HomeTile.scene)
        var seen = Set<String>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else { return nil }
            return candidates.first { $0.id == id }
        }
    }

    /// The chosen camera, or the first one when none is chosen or it is gone.
    static func camera(_ id: String?, in cameras: [HomeCamera]) -> HomeCamera? {
        cameras.first { $0.id == id } ?? cameras.first
    }

    /// A saved tile ID as this HomePad knows it. A face picked on another
    /// HomePad names that HomePad's HomeKit IDs (`SmartHomeService.localID(for:)`).
    @MainActor
    static func localID(_ tileID: String, in home: any SmartHomeService) -> String {
        for prefix in ["accessory:", "scene:"] where tileID.hasPrefix(prefix) {
            return prefix + home.localID(for: String(tileID.dropFirst(prefix.count)))
        }
        return tileID
    }
}
