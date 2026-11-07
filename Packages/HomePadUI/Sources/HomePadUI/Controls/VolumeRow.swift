import SwiftUI

/// A volume slider between a quiet and a loud speaker symbol, the way iPadOS
/// draws volume. The caller supplies the slider, so it decides what the value
/// is bound to and when a change is sent.
///
///     VolumeRow {
///         Slider(value: $level, in: 0...1)
///             .accessibilityLabel("Kitchen volume")
///     }
public struct VolumeRow<Content: View>: View {
    private let slider: Content

    public init(@ViewBuilder slider: () -> Content) {
        self.slider = slider()
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            slider
            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }
}

/// How a volume slider is drawn.
public enum VolumeSliderStyle: Sendable, Equatable {
    /// The system slider in a `VolumeRow`, at least `Theme.Size.tapTarget` tall.
    /// Full-screen players and lists of speakers.
    case row
    /// A `BigSlider` along the axis with the speaker symbol for the level. The
    /// whole bar is the target and a drag anywhere on it moves the level, so it
    /// suits widgets and Control Center, used from a step back. Its drag also
    /// keeps the touch from the pages, taps and holds around it.
    case bar(Axis)
}

/// A volume from 0 to 1 drawn in a `VolumeSliderStyle`. Sliders that follow a
/// device's volume (`SystemVolumeSlider`, Now Playing's) bind it and decide
/// when a change is sent, and draw through this, so a row and a bar of the
/// same volume behave alike. Tint the row with `.tint(_:)`. The bar fills
/// with `.primary`, which follows the glass or page under it.
///
///     VolumeSlider(value: $level, style: .bar(.horizontal), label: "Kitchen volume") { editing in
///         if !editing { send(level) }
///     }
public struct VolumeSlider: View {
    @Binding private var value: Double
    private let style: VolumeSliderStyle
    private let label: String
    private let onEditingChanged: (Bool) -> Void

    /// - Parameters:
    ///   - value: The level, from 0 to 1.
    ///   - style: A row or a bar.
    ///   - label: What VoiceOver reads, such as "Kitchen volume".
    ///   - onEditingChanged: `true` when a drag starts and `false` when it ends.
    public init(value: Binding<Double>, style: VolumeSliderStyle = .row, label: String,
                onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self._value = value
        self.style = style
        self.label = label
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        switch style {
        case .row:
            VolumeRow {
                Slider(value: $value, in: 0...1, onEditingChanged: onEditingChanged)
                    .accessibilityLabel(label)
            }
            .frame(minHeight: Theme.Size.tapTarget)
        case .bar(let axis):
            BigSlider(value: $value, axis: axis, systemImage: Self.symbol(for: value), tint: .primary,
                      onEditingChanged: onEditingChanged)
                .accessibilityLabel(label)
        }
    }

    /// The speaker for a level: crossed out at zero, then one to three waves,
    /// as iPadOS shows volume.
    public static func symbol(for level: Double) -> String {
        switch level {
        case ..<0.01: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}
