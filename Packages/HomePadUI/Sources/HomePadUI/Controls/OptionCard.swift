import SwiftUI

/// A card in an `OptionCarousel`: an icon or swatch above a title, outlined
/// in the tint color when selected.
///
///     OptionCard(title: "Ocean", isSelected: isSelected) { Circle().fill(.blue) }
///
/// A card can show a picture of the result instead of an icon, such as a
/// face with that style applied. Give it the picture's size:
///
///     OptionCard(title: "Digital", isSelected: isSelected, iconSize: CGSize(width: 180, height: 124)) { thumbnail }
public struct OptionCard<Icon: View>: View {
    /// The icon area of a card that names no size: an 84 point square.
    public static var defaultIconSize: CGSize { CGSize(width: 84, height: 84) }

    private let title: String
    private let isSelected: Bool
    private let iconSize: CGSize
    private let icon: Icon

    /// - Parameters:
    ///   - title: The option's name.
    ///   - isSelected: Draws the selected outline and full size.
    ///   - icon: An 84 point preview of the option.
    public init(title: String, isSelected: Bool, @ViewBuilder icon: () -> Icon) {
        self.init(title: title, isSelected: isSelected, iconSize: Self.defaultIconSize, icon: icon)
    }

    /// - Parameters:
    ///   - title: The option's name.
    ///   - isSelected: Draws the selected outline and full size.
    ///   - iconSize: The size of the preview above the title.
    ///   - icon: A preview of the option, drawn at `iconSize`.
    public init(title: String, isSelected: Bool, iconSize: CGSize, @ViewBuilder icon: () -> Icon) {
        self.title = title
        self.isSelected = isSelected
        self.iconSize = iconSize
        self.icon = icon()
    }

    public var body: some View {
        VStack(spacing: Theme.Spacing.s) {
            icon
                .frame(width: iconSize.width, height: iconSize.height)
            Text(title)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.25)) : AnyShapeStyle(.ultraThinMaterial))
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(0.15)), lineWidth: isSelected ? 3 : 1)
        }
        .scaleEffect(isSelected ? 1 : 0.92)
        .animation(Theme.Motion.standard, value: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
