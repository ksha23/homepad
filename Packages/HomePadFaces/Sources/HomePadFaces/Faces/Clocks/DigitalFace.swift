import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.digital`: the time in big rounded digits. From across the room
/// that is all, as large as the face allows. Step closer and the time
/// glances smaller as the date above it and the seconds and weather under
/// it fade in.
struct DigitalFace: View {
    static let style = FaceOption.style([
        FaceChoice("rounded", "Rounded", systemImage: "textformat"),
        FaceChoice("tall", "Tall", systemImage: "arrow.up.and.down.text.horizontal"),
        FaceChoice("thin", "Thin", systemImage: "character"),
    ])
    static let color = FaceOption.color([.graphite, .midnight, .ocean, .sage, .coral, .sand, .lavender, .porcelain], default: .graphite)

    static let definition = FaceDefinition(
        id: "faces.digital", title: "Digital", summary: "Big rounded digits you can read from anywhere",
        systemImage: "textformat.123", sortOrder: 42, options: [style, color],
        widgets: .besideWidgets()
    ) { DigitalFace() }

    @Environment(\.faceInsets) private var faceInsets
    @Environment(\.faceKeepClear) private var keepClear

    @Environment(\.faceConfiguration) private var configuration
    @Environment(\.displayCondition) private var condition
    @Environment(\.proximity) private var proximity

    var body: some View {
        let palette = FacePalette.resolve(configuration.colors(Self.color), condition: condition)
        let style = configuration.value(Self.style)
        let isNear = proximity >= .mid
        FaceTimeline(isNear ? .second : .minute) { date in
            GeometryReader { proxy in
                let parts = ClockText.parts(for: date, uses24Hour: ClockText.localeUses24Hour())
                // As large as the face allows clear of its widgets and the Now Playing pill.
                let far = Self.farSize(style: style, in: proxy.size.leaving(keepClear))
                ZStack {
                    Rectangle().fill(palette.background).ignoresSafeArea()
                    VStack(spacing: Theme.Spacing.m) {
                        if isNear {
                            Text(date, format: .dateTime.weekday(.wide).month(.wide).day())
                                .font(.display(far * 0.11, weight: .semibold))
                                .foregroundStyle(palette.secondary)
                                .transition(.proximityDetail)
                        }
                        // One view at both distances. Its size animates, so the
                        // date and the detail row move with it as it shrinks.
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(parts.hours)
                            Text(":").foregroundStyle(palette.accent)
                            Text(parts.minutes)
                        }
                        .modifier(DigitFont(style: style, size: isNear ? far * Self.nearScale : far))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        if isNear {
                            NearDetailRow(date: date, period: parts.period, palette: palette)
                                .font(.display(far * 0.09, weight: .medium))
                                .transition(.proximityDetail)
                        }
                    }
                    .padding(faceInsets)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
        }
        .faceBackdrop(tone: palette.tone) { palette.background.ignoresSafeArea() }
    }

    /// How much smaller the time is up close.
    static let nearScale: CGFloat = 0.6

    /// The time's font size from across the room: as wide as the face allows
    /// for the style, and at most most of its height.
    static func farSize(style: String, in size: CGSize) -> CGFloat {
        min(size.width * (style == "tall" ? 0.46 : 0.32), size.height * 0.62)
    }
}

/// The digits' font for a style, at a size that animates.
private struct DigitFont: ViewModifier {
    let style: String
    let size: CGFloat

    func body(content: Content) -> some View {
        switch style {
        case "tall": content.displayFont(size, weight: .semibold, width: .compressed)
        case "thin": content.displayFont(size, weight: .ultraLight)
        default: content.displayFont(size, weight: .semibold)
        }
    }
}
