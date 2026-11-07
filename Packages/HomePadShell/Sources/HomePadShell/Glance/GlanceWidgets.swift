import HomePadCore
import HomePadUI
import SwiftUI

/// The glance as widgets, for faces and the Home Screen: Glance (everything:
/// the day, messages, home and timers) and Home Status (what is on at home
/// by kind and what needs a look). Both land top leading when added to a
/// face (`WidgetAnchor.topLeading`).
///
/// Neither is personal as a whole, since home and timers are for everyone.
/// Glance leaves out calendar, reminders and messages until someone is
/// recognized (`GlanceReader`).
@MainActor
enum GlanceWidgets {
    static let glanceID = "shell.glance"
    static let homeStatusID = "shell.homestatus"
    /// Tall lists more, with the detail under each.
    static let sizes: [WidgetSize] = [.small, .medium, .large, .tall]

    static func register(in registry: ModuleRegistry) {
        registry.register(widget: WidgetDescriptor(
            id: glanceID, title: "Glance", systemImage: "square.text.square", supportedSizes: sizes,
            opensApp: GlanceAppID.calendar, anchor: .topLeading
        ) { size in
            GlanceWidgetView(kind: .everything, size: size)
        })
        registry.register(widget: WidgetDescriptor(
            id: homeStatusID, title: "Home Status", systemImage: "house.fill", supportedSizes: sizes,
            opensApp: GlanceAppID.home, anchor: .topLeading,
            relevance: { homeStatusRelevance($0.services.smartHome.accessories) }
        ) { size in
            GlanceWidgetView(kind: .home, size: size)
        })
    }

    /// Home Status asks a stack to show it while something at home needs a
    /// look, the states it lists first: smoke, a leak, an unlocked lock, or an
    /// open garage, door or window. It holds while that lasts.
    static func homeStatusRelevance(_ accessories: [HomeAccessory]) -> WidgetRelevance? {
        let devices = accessories.withoutGroups.filter(\.state.isReachable)
        return devices.contains { GlanceSummary.attention(of: $0) != nil } ? .needsLook() : nil
    }
}

/// One of the glance widgets at a size, on glass that follows the backdrop.
///
/// - Small: a symbol and a count for each thing, two to a row.
/// - Medium: short words too ("3 events", "5 lights on"), two to a row.
/// - Large and tall: a row for each thing with its detail under it (the next
///   event, the rooms or accessories that are on), and the weather on top of
///   Glance. Each row opens its app. Tall has room for about twice as many.
///
/// Every size shows as many things as fit, the most pressing first. Small
/// and medium open the widget's own app (`WidgetDescriptor.opensAppID`),
/// since their parts are too small to tap one by one.
struct GlanceWidgetView: View {
    enum Kind {
        /// Glance: everything the header shows, timers and the weather too.
        case everything
        /// Home Status: what needs a look and what is on, by accessory.
        case home
    }

    let kind: Kind
    let size: WidgetSize

    var body: some View {
        GlanceReader { summary in
            GlanceWidgetContent(
                items: kind == .everything ? summary.items(includingTimers: true) : summary.homeItems(namingAccessories: true),
                weather: kind == .everything ? summary.weather : nil,
                quiet: kind == .everything ? "All quiet" : "All quiet at home",
                size: size
            )
        }
    }
}

struct GlanceWidgetContent: View {
    let items: [GlanceItem]
    let weather: GlanceSummary.Weather?
    let quiet: String
    let size: WidgetSize
    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry
    @Environment(\.proximity) private var proximity
    @Environment(\.displayCondition) private var condition

    var body: some View {
        GlassTile {
            switch size {
            case .small, .medium:
                if items.isEmpty {
                    quietView
                } else {
                    grid(showsWords: size == .medium)
                }
            case .large, .tall:
                rows
            }
        }
        .animation(Theme.Motion.standard, value: items)
    }

    // MARK: Small and medium

    /// Two to a row, as many rows as fit.
    private func grid(showsWords: Bool) -> some View {
        ViewThatFits(in: .vertical) {
            ForEach(Array(Self.counts(items.count, step: 2).reversed()), id: \.self) { count in
                Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.s, verticalSpacing: Theme.Spacing.controlGap) {
                    ForEach(Self.pairs(Array(items.prefix(count)))) { pair in
                        GridRow {
                            cell(pair.first, showsWords: showsWords)
                            if let second = pair.second {
                                cell(second, showsWords: showsWords)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: showsWords ? .leading : .center)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func cell(_ item: GlanceItem, showsWords: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: item.systemImage)
                .foregroundStyle(tint(item))
            Text(showsWords ? item.phrase : "\(item.count)")
                .contentTransition(.numericText())
        }
        .font(showsWords ? .tileTitle : .tileValue)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.spokenLabel)
    }

    // MARK: Large and tall

    /// The weather, then a row per thing, as many as fit. Up close each row
    /// shows its detail too. Rows that do not fit with their detail are tried
    /// without it before any is left out.
    private var rows: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let weather {
                HStack(spacing: Theme.Spacing.s) {
                    Image(systemName: weather.symbolName)
                        .symbolRenderingMode(.multicolor)
                    Text("\(weather.temperature)°")
                    Text(weather.condition)
                        .font(.tileDetail)
                        .foregroundStyle(.secondary)
                }
                .font(.tileTitle)
                .lineLimit(1)
                .accessibilityElement(children: .combine)
            }
            if items.isEmpty {
                quietView
            }
            ViewThatFits(in: .vertical) {
                ForEach(rowVariants, id: \.self) { variant in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(items.prefix(variant.count)) { item in
                            row(item, showsDetail: variant.showsDetail)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    private struct RowVariant: Hashable {
        var count: Int
        var showsDetail: Bool
    }

    /// Every row with its detail, every row without, then one row fewer, and so on.
    private var rowVariants: [RowVariant] {
        let detail = proximity != .far
        return (1...max(items.count, 1)).reversed().flatMap { count in
            detail ? [RowVariant(count: count, showsDetail: true), RowVariant(count: count, showsDetail: false)]
                : [RowVariant(count: count, showsDetail: false)]
        }
    }

    private func row(_ item: GlanceItem, showsDetail: Bool) -> some View {
        Button {
            services.events.post(.openApp(id: item.appID))
        } label: {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: item.systemImage)
                    .font(.tileTitle)
                    .foregroundStyle(tint(item))
                    .frame(width: symbolWidth)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.phrase)
                        .font(.tileTitle)
                        .contentTransition(.numericText())
                    if showsDetail, let detail = item.detail {
                        Text(detail)
                            .font(.tileDetail)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            // Each row is a walk-up target of its own.
            .frame(minHeight: Theme.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable(scale: 0.98))
        .accessibilityLabel(item.spokenLabel)
    }

    /// The symbols' column, as wide as the widest symbol at the title size.
    @ScaledMetric(relativeTo: .title3) private var symbolWidth: CGFloat = 28

    // MARK: Nothing to say

    private var quietView: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "checkmark.circle")
                .font(.tileValue)
                .foregroundStyle(.secondary)
            Text(quiet)
                .font(size == .small ? .headline : .tileTitle)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Helpers

    /// Home things take their accessory kind's tint, what needs a look orange,
    /// and the rest the color of the app they open. At night every symbol is
    /// the text's color: the red tint keeps only a color's red, so a cyan
    /// purifier or a green Messages symbol went black.
    private func tint(_ item: GlanceItem) -> Color {
        if condition == .night { return .primary }
        return switch item.id {
        case .home(let kind): Theme.tint(for: kind.accessoryKind)
        case .attention: .orange
        default: registry.app(item.appID)?.tint ?? .secondary
        }
    }

    /// 2, 4, 6... up to `total`, and `total` itself when it is odd.
    static func counts(_ total: Int, step: Int) -> [Int] {
        guard total > 0 else { return [0] }
        var counts = Array(stride(from: step, through: total, by: step))
        if counts.last != total { counts.append(total) }
        return counts
    }

    /// Two items side by side in the grid.
    struct Pair: Identifiable {
        var first: GlanceItem
        var second: GlanceItem?
        var id: GlanceItem.ID { first.id }
    }

    /// The items two by two, the last one alone when there is an odd number.
    static func pairs(_ items: [GlanceItem]) -> [Pair] {
        stride(from: 0, to: items.count, by: 2).map { index in
            Pair(first: items[index], second: index + 1 < items.count ? items[index + 1] : nil)
        }
    }
}
