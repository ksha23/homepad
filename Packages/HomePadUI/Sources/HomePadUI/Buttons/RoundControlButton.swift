import SwiftUI

/// A one-shot round button that matches `ToggleTile(style: .round)`, for
/// actions in Control Center style rows (open Mirror, start a scene).
///
///     RoundControlButton("Mirror", systemImage: "person.crop.square") { open("mirror") }
public struct RoundControlButton: View {
    private let title: String
    private let systemImage: String
    private let isEnabled: Bool
    private let action: () -> Void

    /// - Parameters:
    ///   - title: Label under the circle.
    ///   - systemImage: SF Symbol in the circle.
    ///   - isEnabled: Draws the button dimmed and ignores taps when false.
    ///   - action: Called on tap.
    public init(_ title: String, systemImage: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: Theme.Size.roundControl, height: Theme.Size.roundControl)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .editPulseBorder(in: Circle())
                Text(title)
                    .font(ToggleTile.roundLabelFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.pressable)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
    }
}
