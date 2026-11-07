import SwiftUI

/// A Control Center style toggle. `.round` is the circular button row
/// (Wi-Fi, mute, camera), `.wide` is a rounded tile with a title and status
/// line (a door lock, a scene).
///
///     ToggleTile("Camera", systemImage: "video.fill", isOn: $cameraOn)
///     ToggleTile("Front Door", subtitle: "Locked", systemImage: "lock.fill",
///                isOn: $locked, style: .wide, onTint: .teal)
public struct ToggleTile: View {
    /// Visual style of the toggle.
    public enum Style: Sendable {
        /// Circular button with the title underneath.
        case round
        /// Rounded rectangle with icon, title and subtitle side by side.
        case wide
    }

    private let title: String
    private let subtitle: String?
    private let systemImage: String
    @Binding private var isOn: Bool
    private let style: Style
    private let onTint: Color
    private let isEnabled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// - Parameters:
    ///   - title: Label, also the accessibility label.
    ///   - subtitle: Status line for `.wide` tiles, for example "Locked".
    ///   - systemImage: SF Symbol.
    ///   - isOn: Toggle state.
    ///   - style: `.round` or `.wide`.
    ///   - onTint: Fill color when on.
    ///   - isEnabled: Draws the tile dimmed and ignores taps when false.
    public init(
        _ title: String, subtitle: String? = nil, systemImage: String, isOn: Binding<Bool>,
        style: Style = .round, onTint: Color = .white, isEnabled: Bool = true
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self._isOn = isOn
        self.style = style
        self.onTint = onTint
        self.isEnabled = isEnabled
    }

    public var body: some View {
        Button {
            isOn.toggle()
        } label: {
            switch style {
            case .round: roundLabel
            case .wide: wideLabel
            }
        }
        // Lit glass gives no press response of its own, so the tile sinks instead.
        .buttonStyle(.pressable)
        // The fill fades in and out with the state, also when it changes elsewhere.
        .animation(Theme.Motion.standard, value: isOn)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .sensoryFeedback(.selection, trigger: isOn)
    }

    /// Black or white on the lit fill, and `.primary` on the glass when off.
    private var iconColor: Color {
        isOn ? Color.foreground(on: onTint, in: colorScheme) : .primary
    }

    private var roundLabel: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: Theme.Size.roundControl, height: Theme.Size.roundControl)
                .background {
                    if isOn { Circle().fill(onTint) }
                }
                .glassEffect(isOn ? .identity : .regular.interactive(), in: Circle())
                .editPulseBorder(in: Circle())
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce.down, options: .nonRepeating, value: reduceMotion ? false : isOn)
            Text(title)
                .font(Self.roundLabelFont)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    /// The label under a round toggle or `RoundControlButton`: body text, the
    /// smallest that carries information on a walk-up surface.
    static let roundLabelFont: Font = .body.weight(.medium)

    private var wideLabel: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(isOn ? onTint : .primary)
                .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                .background(Circle().fill(isOn ? Color.white : Color.primary.opacity(0.15)))
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce.down, options: .nonRepeating, value: reduceMotion ? false : isOn)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.tileTitle).foregroundStyle(isOn ? .black : .primary)
                if let subtitle {
                    Text(subtitle).font(.tileDetail).foregroundStyle(isOn ? .black.opacity(0.6) : .secondary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.s)
        .frame(maxWidth: .infinity, minHeight: Theme.Size.roundControl)
        .background {
            if isOn {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(onTint.opacity(0.9))
            }
        }
        .glassEffect(isOn ? .identity : .regular.interactive(),
                     in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .editPulseBorder(in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
