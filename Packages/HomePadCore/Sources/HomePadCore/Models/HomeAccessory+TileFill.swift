import Foundation

extension HomeAccessory {
    /// How much of the accessory's tile its "on" color covers, from 0 to 1,
    /// given whether the tile shows it as on. A light or fan with brightness
    /// fills to its level and a blind with a position fills to how far it is
    /// open. Anything else that is on fills the whole tile, and nothing fills
    /// when off. A sliver stays at the lowest levels, so a light on at 1
    /// percent still reads as on. The Home app, its widgets and the Home face
    /// all draw tiles this way.
    public func tileFill(isOn: Bool) -> Double {
        guard isOn else { return 0 }
        let level: Double? = switch kind {
        case .light, .fan: capabilities.contains(.brightness) ? state.brightness ?? 1 : nil
        case .cover: capabilities.contains(.position) ? state.position ?? 1 : nil
        default: nil
        }
        return level.map { max($0, 0.08) } ?? 1
    }
}
