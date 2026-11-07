import HomePadCore
import HomePadUI
import SwiftUI
import UIKit

/// The glance as a mini widget (`GlanceMiniWidget`): a compact line of what
/// is going on, right of the Home Screen header's lines in their own white
/// capitals, or in a face's top left corner on glass.
///
/// - Small: a symbol and a count for each thing.
/// - Medium: short words too ("3 events", "5 lights on").
/// - Large: a second line under each with the detail (the next event, the
///   rooms that are lit, the door that is open).
///
/// It takes the room it is offered. When that is too little, the first
/// things keep the chosen size and the rest shrink to a symbol and a count,
/// then things drop from the end, then it shows nothing, so nothing beside
/// it is ever cut off. Timers are left out, since the timer pill sits in the
/// same row. Each thing opens its app where the context allows it.
struct MiniGlanceView: View {
    let context: MiniWidgetContext

    var body: some View {
        GlanceReader { summary in
            MiniGlanceContent(items: summary.items(includingTimers: false), size: context.size,
                              textSize: context.textSize, surface: context.surface, leadingGap: context.leadingGap,
                              keepsSomething: context.keepsSomething, open: context.openApp)
        }
    }
}

/// The variants the glance tries, largest first, and the first that fits.
struct MiniGlanceContent: View {
    let items: [GlanceItem]
    let size: MiniWidgetSize
    let textSize: CGFloat
    var surface: MiniWidgetSurface = .wallpaper
    var leadingGap: CGFloat = 0
    /// True where the glance must stay (edit mode, its own glass on a face):
    /// at the least it shows its first thing small.
    var keepsSomething = false
    let open: (@MainActor (String) -> Void)?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Self.variants(items: items, size: size)) { variant in
                MiniGlanceRow(items: variant.items, size: variant.size, fullCount: variant.fullCount,
                              textSize: textSize, surface: surface, open: open)
                    .padding(.leading, leadingGap)
            }
            if !keepsSomething {
                Color.clear.frame(width: 0, height: 0)
            }
        }
        .animation(Theme.Motion.standard, value: items)
    }

    /// One way to draw the glance: the things it shows, the first
    /// `fullCount` of them at `size` and the rest small.
    struct Variant: Identifiable, Equatable {
        var size: MiniWidgetSize
        var fullCount: Int
        var items: [GlanceItem]
        var id: String { "\(size.rawValue)-\(fullCount)-\(items.count)" }
    }

    /// Every thing at the chosen size, then one thing fewer at that size and
    /// the rest small, down to every thing small, then fewer things small,
    /// dropping from the end, down to the first alone. So the most pressing
    /// things keep their words and detail longest, and nothing is dropped
    /// while a symbol and a count still fit.
    static func variants(items: [GlanceItem], size: MiniWidgetSize) -> [Variant] {
        let count = items.count
        var variants: [Variant] = []
        if size != .small {
            variants += (1...max(count, 1)).reversed().map { Variant(size: size, fullCount: min($0, count), items: items) }
        }
        variants.append(Variant(size: .small, fullCount: count, items: items))
        if count > 1 {
            variants += (1..<count).reversed().map { Variant(size: .small, fullCount: $0, items: Array(items.prefix($0))) }
        }
        return variants
    }
}

/// The glance drawn one way, in capitals like the header's lines. The first
/// `fullCount` things are at `size`, the rest small.
struct MiniGlanceRow: View {
    let items: [GlanceItem]
    let size: MiniWidgetSize
    let fullCount: Int
    let textSize: CGFloat
    var surface: MiniWidgetSurface = .wallpaper
    let open: (@MainActor (String) -> Void)?

    var body: some View {
        let isSmall = size == .small || fullCount == 0
        HStack(alignment: size == .large ? .top : .center, spacing: isSmall ? Theme.Spacing.m : Theme.Spacing.l) {
            if items.isEmpty {
                quiet
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    entry(item, size: index < fullCount ? size : .small)
                }
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    private func entry(_ item: GlanceItem, size: MiniWidgetSize) -> some View {
        let label = VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: item.systemImage)
                Text(size == .small ? "\(item.count)" : item.phrase)
                    .contentTransition(.numericText())
            }
            .font(.system(size: textSize, weight: .semibold))
            if size == .large, let detail = item.detail {
                Text(detail)
                    .font(.system(size: textSize, weight: .regular))
                    .frame(maxWidth: detailWidth, alignment: .leading)
            }
        }
        .modifier(MiniGlanceText(surface: surface))
        if let open {
            Button { open(item.appID) } label: {
                label
                    // The whole height of the row is the target, as on the pills beside it.
                    .frame(minHeight: Theme.Size.minTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            // The app grows out of the item and closes back into it.
            .zoomSource("glance/\(item.id)", shape: .surface(cornerRadius: Theme.Radius.tileControl))
            .accessibilityLabel(item.spokenLabel)
            .accessibilityHint("Opens \(Self.appName(item.appID))")
        } else {
            label
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(item.spokenLabel)
        }
    }

    /// Nothing to say: a check, with words from medium up.
    private var quiet: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "checkmark.circle")
            if size != .small {
                Text("All quiet")
            }
        }
        .font(.system(size: textSize, weight: .regular))
        .modifier(MiniGlanceText(surface: surface))
        .opacity(0.75)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Nothing going on")
    }

    /// A detail is cut off past about sixteen digits of the text, so one long
    /// event title cannot crowd the rest out of the row.
    private var detailWidth: CGFloat {
        let digit = ("0" as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: textSize)]).width
        return (digit * Self.detailDigits).rounded()
    }

    private static let detailDigits: CGFloat = 16

    private static func appName(_ appID: String) -> String {
        switch appID {
        case GlanceAppID.calendar: "Calendar"
        case GlanceAppID.reminders: "Reminders"
        case GlanceAppID.messages: "Messages"
        default: "Home"
        }
    }
}

/// The glance's look: capitals on one line. On the wallpaper they are white
/// with the header lines' shadow for a bright wallpaper. On glass they take
/// the glass's primary color, which follows the glass.
private struct MiniGlanceText: ViewModifier {
    let surface: MiniWidgetSurface

    func body(content: Content) -> some View {
        let text = content
            .textCase(.uppercase)
            .lineLimit(1)
        switch surface {
        case .wallpaper:
            text
                .foregroundStyle(.white)
                .wallpaperLabelShadow()
        case .glass:
            text
                .foregroundStyle(.primary)
        }
    }
}
