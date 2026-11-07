import SwiftUI

/// A row in a sidebar, such as Settings' sections, Music's sections and
/// Messages' conversations. The whole row is the target: as wide as the
/// sidebar and at least `Theme.Size.tapTarget` tall, so a finger at arm's
/// length lands on it. The chosen row has a quiet highlight, and a row shows a
/// fainter one while it is pressed, so the finger sees which row it is on
/// before it lets go. Stack rows `Theme.Spacing.sidebarRowGap` apart.
///
/// The highlight is the one shape every sidebar uses: `Theme.Radius.card`
/// with continuous corners. Never let a `List` draw its own selection in a
/// sidebar, since its radius is not on HomePad's scale.
///
///     Button { selection = section } label: { Label(section.title, systemImage: section.systemImage) }
///         .buttonStyle(.sidebarRow(isSelected: section == selection))
public struct SidebarRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    let tint: Color?

    /// - Parameters:
    ///   - isSelected: Whether this row is the one showing.
    ///   - tint: Fills the chosen row with this color and turns its label
    ///     black or white to read on it, as Messages on iPadOS does in blue.
    ///     Nil keeps the quiet gray highlight.
    public init(isSelected: Bool, tint: Color? = nil) {
        self.isSelected = isSelected
        self.tint = tint
    }

    public func makeBody(configuration: Configuration) -> some View {
        SidebarRowLabel(configuration: configuration, isSelected: isSelected, tint: tint)
    }
}

public extension ButtonStyle where Self == SidebarRowButtonStyle {
    /// A sidebar row, highlighted while it is the one showing. See `SidebarRowButtonStyle`.
    static func sidebarRow(isSelected: Bool, tint: Color? = nil) -> SidebarRowButtonStyle {
        SidebarRowButtonStyle(isSelected: isSelected, tint: tint)
    }
}

private struct SidebarRowLabel: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let tint: Color?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        if let fill = selectedTint {
            row(in: shape)
                .background(shape.fill(fill))
                .foregroundStyle(Color.foreground(on: fill, in: colorScheme))
        } else {
            row(in: shape)
                .background(shape.fill(.primary.opacity(highlight)))
        }
    }

    private func row(in shape: RoundedRectangle) -> some View {
        configuration.label
            .padding(.horizontal, Theme.Spacing.m)
            .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget, alignment: .leading)
            .contentShape(shape)
            .animation(Theme.Motion.standard, value: configuration.isPressed)
    }

    /// The chosen row's fill when the sidebar has a tint of its own.
    private var selectedTint: Color? {
        isSelected ? tint : nil
    }

    /// Lighter in Light, where the same gray reads heavier on the page.
    private var highlight: Double {
        let selected = colorScheme == .light ? 0.08 : 0.14
        if isSelected {
            return selected
        }
        return configuration.isPressed ? selected * 0.6 : 0
    }
}
