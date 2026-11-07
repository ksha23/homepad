import HomePadCore
import HomePadUI
import SwiftUI

/// A device on the map: a round icon in its owner's color, larger and named
/// while selected, like Apple's Find My. Names on every pin would cover each
/// other where devices sit together. It has no motion of its own.
struct FindMyPin: View {
    let device: FindMyDevice
    let isSelected: Bool

    var body: some View {
        FindMyDeviceIcon(device: device, size: isSelected ? Theme.Size.tapTarget : Theme.Size.minTapTarget)
            .overlay {
                Circle().strokeBorder(.white, lineWidth: isSelected ? 3 : 2)
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    Text(device.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.6), in: Capsule())
                        .offset(y: Theme.Spacing.l)
                }
            }
        .animation(Theme.Motion.standard, value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(device.title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

/// A device's symbol on a circle in its owner's color, for pins, rows and the card.
///
/// At night it is dark with a light symbol and a ring in the owner's color, like
/// `AppIcon`: night mode turns everything red, and a symbol on a bright circle
/// came out the same red as the circle.
struct FindMyDeviceIcon: View {
    let device: FindMyDevice
    var size: CGFloat = Theme.Size.minTapTarget
    @Environment(\.displayCondition) private var condition

    var body: some View {
        let isNight = condition == .night
        Circle()
            .fill(isNight ? AnyShapeStyle(Color(white: 0.14)) : AnyShapeStyle(device.tint.gradient))
            .overlay {
                if isNight { Circle().strokeBorder(device.tint, lineWidth: 2) }
            }
            .overlay {
                Image(systemName: device.kind.systemImage)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(isNight ? .white : symbolColor)
            }
            .frame(width: size, height: size)
    }

    /// Black on white (nobody's) and on yellow, like `GlassIconButton`, else white.
    private var symbolColor: Color {
        guard let hex = device.colorHex else { return .black }
        return Theme.Palette.swatch(forHex: hex)?.id == "yellow" ? .black : .white
    }
}

/// The house drawn at the center of the home zone.
struct FindMyHomeMarker: View {
    var body: some View {
        Image(systemName: "house.fill")
            .font(.footnote.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(.black.opacity(0.6), in: Circle())
            .overlay { Circle().strokeBorder(.white.opacity(0.6), lineWidth: 1) }
            .accessibilityLabel("Home")
    }
}
