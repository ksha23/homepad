import HomePadCore
import HomePadUI
import SwiftUI

/// Sizes for the controls on an accessory's full-screen detail, at HomeView's
/// scale: a level control as tall as the room it has and at least half as
/// wide, with its value and a thermostat's setpoint about a fifth of the
/// screen tall, a power or lock circle well under half the height, and buttons
/// and swatches at least the walk-up target (`Theme.Size.tapTarget`) up close
/// and a size larger from across the room.
/// `AccessoryDetailView` measures the space its controls have and puts the
/// metrics in the environment.
struct DetailControlMetrics: Equatable {
    /// Brightness, speed and blind position (`LevelControl`).
    var slider: CGSize
    /// The power circle of a switch and the lock's circle.
    var circle: CGFloat
    /// Turn On, Open, Unlock, the thermostat's modes.
    var button: GlassCapsuleButtonStyle.Size
    /// Color and color temperature presets.
    var swatch: CGFloat
    /// A status line under a circle ("Off", "Locked").
    var statusSize: CGFloat
    /// The thermostat's target temperature.
    var thermostatSize: CGFloat
    /// A sensor's reading, which shares its screen with a chart.
    var readingSize: CGFloat
    /// The thermostat's arrows and a speaker's play button.
    var heroButton: CGFloat
    /// A speaker's previous and next buttons.
    var transportButton: CGFloat
    /// A group member's row.
    var memberRow: CGFloat

    init(space: CGSize, proximity: ProximityLevel) {
        let isNear = proximity >= .mid
        // On HomeView the whole screen is the level control. Here it takes the
        // full height and at least half the width, and no more than it is
        // tall, so its buttons and swatches keep a column beside it.
        let height = max(space.height, 0)
        slider = CGSize(width: max(space.width * 0.5, min(space.width * 0.6, height)), height: height)
        circle = max(min(isNear ? 200 : 240, space.height * 0.32), Theme.Size.heroControl)
        button = isNear ? .large : .extraLarge
        swatch = isNear ? Theme.Size.tapTarget : Theme.Size.roundControl
        statusSize = isNear ? 44 : 56
        // Digits about a fifth of the screen tall, as on HomeView, and narrow
        // enough in portrait for the arrows on either side.
        thermostatSize = max(min(space.height * 0.33, space.width * 0.3), 0)
        readingSize = isNear ? 160 : 200
        heroButton = isNear ? Theme.Size.roundControl : Theme.Size.heroControl
        transportButton = isNear ? Theme.Size.tapTarget : Theme.Size.roundControl
        memberRow = isNear ? Theme.Size.tapTarget : Theme.Size.roundControl
    }
}

extension EnvironmentValues {
    /// Set by `AccessoryDetailView` for the control it shows.
    @Entry var detailControlMetrics = DetailControlMetrics(space: CGSize(width: 1000, height: 800), proximity: .near)
}
