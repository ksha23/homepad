import HomePadCore
import SwiftUI

/// One widget in a `WidgetStackView`, as the place drawing it resolved it.
public struct WidgetStackItem: Identifiable {
    public let member: WidgetStack.Member
    public let widget: WidgetDescriptor
    /// False for a widget that may not show its content now, such as a
    /// personal one drawn locked. It keeps its page but asks for nothing.
    public let isAvailable: Bool
    public var id: String { member.id }

    public init(member: WidgetStack.Member, widget: WidgetDescriptor, isAvailable: Bool = true) {
        self.member = member
        self.widget = widget
        self.isAvailable = isAvailable
    }
}

/// A widget stack, as iPadOS draws a Smart Stack: one widget at a time in
/// the stack's frame, a vertical swipe flips to the next or the one before
/// with paging, and small page dots show beside its trailing edge while it
/// moves. Smart Rotate turns it to the most relevant widget and back
/// (`WidgetStackRotation`), and a widget the person flipped to stays a while.
///
///     WidgetStackView(stackID: id, items: items, smartRotate: stack.smartRotate) { item in
///         item.widget.makeView(size).environment(\.widgetSettings, item.member.settings ?? WidgetSettings())
///     }
///
/// The swipe is a vertical paging scroll view, the way the Home Screen's and
/// the face's pages are horizontal ones. Each takes only drags along its own
/// axis, so a sideways swipe on a stack still turns the page, and a swipe up
/// or down never does. The shell's edge swipes start in strips along the
/// screen's edges, outside every stack. A widget's own controls keep their
/// drags: the Now Playing volume takes the touch as the finger lands, so the
/// stack never sees it. A swipe is not a tap, so it opens no app, and in edit
/// mode the place drawing the stack turns its touches off (`isInteractive`),
/// so a press lifts the whole stack.
///
/// Draw it unclipped: it rounds its own frame (`Theme.Radius.tile`) and draws
/// the dots outside it. In a thumbnail (`\.isThumbnail`) it draws the widget
/// on top and nothing else.
public struct WidgetStackView<Page: View>: View {
    public typealias Item = WidgetStackItem

    private let stackID: String
    private let items: [Item]
    private let smartRotate: Bool
    private let isInteractive: Bool
    private let page: (Item) -> Page

    @Environment(AppServices.self) private var services
    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The page on screen.
    @State private var position: String?
    @State private var phase: ScrollPhase = .idle
    /// True from the moment the person's finger moves the stack until it rests.
    @State private var isFlipping = false
    /// The widget Smart Rotate shows, to turn to once the stack is at rest.
    @State private var target: String?
    @State private var showsDots = false
    /// When the stack last looked again on time alone (`Decision.nextCheck`).
    @State private var checkedAt = Date()

    /// - Parameters:
    ///   - stackID: The stack's ID where it is placed, which keeps what it remembers (`WidgetStackMemory`).
    ///   - items: Its widgets in order, without those that may not show at all.
    ///   - smartRotate: Turns to the most relevant widget and back.
    ///   - isInteractive: False in edit mode: it holds still and takes no touches.
    ///   - page: Draws one widget to fill the stack's frame.
    public init(stackID: String, items: [Item], smartRotate: Bool, isInteractive: Bool = true,
                @ViewBuilder page: @escaping (Item) -> Page) {
        self.stackID = stackID
        self.items = items
        self.smartRotate = smartRotate
        self.isInteractive = isInteractive
        self.page = page
    }

    /// How long the dots stay once the stack comes to rest, as on iPadOS.
    static var dotsLinger: Duration { .seconds(1) }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
    }

    public var body: some View {
        if isThumbnail {
            // Previews show what the stack shows where it sits, and ask nothing.
            let shown = services.widgetStacks.shownMemberID(in: stackID)
            if let item = items.first(where: { $0.id == shown }) ?? items.first {
                page(item).clipShape(shape)
            }
        } else {
            stack
        }
    }

    private var stack: some View {
        let memory = services.widgetStacks
        let now = max(Date(), checkedAt)
        let live = liveRelevance(at: now)
        let choice = memory.choices[stackID]
        let decision = WidgetStackRotation.decide(
            memberIDs: items.map(\.id),
            relevance: WidgetStackRotation.standing(live: live, held: memory.held[stackID] ?? [:], now: now),
            chosenID: choice?.memberID, chosenAt: choice?.date, smartRotate: smartRotate, now: now
        )
        let shown = decision?.memberID
        return ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    page(item)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(item.id)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $position)
        // A starting id alone is ignored before the lazy pages exist, so the
        // first layout is placed on the page shown by its offset, as the Home Screen's pages are.
        .defaultScrollAnchor(anchor(for: shown), for: .initialOffset)
        .scrollIndicators(.hidden)
        .scrollDisabled(!isInteractive || items.count < 2)
        .clipShape(shape)
        .onScrollPhaseChange { _, new in scrolled(to: new) }
        .overlay(alignment: .trailing) {
            if showsDots, items.count > 1 {
                StackDots(count: items.count, current: items.firstIndex { $0.id == position } ?? 0)
                    .fixedSize()
                    // Beside the trailing edge, in the gutter, so it never covers the
                    // widget's own controls there, such as Now Playing's volume.
                    .alignmentGuide(HorizontalAlignment.trailing) { $0[.leading] - Theme.Spacing.xs }
                    .transition(.opacity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityActions {
            if isInteractive, items.count > 1 {
                Button("Next Widget") { flip(by: 1) }
                Button("Previous Widget") { flip(by: -1) }
            }
        }
        .onAppear {
            if position == nil || !items.contains(where: { $0.id == position }) {
                position = shown ?? items.first?.id
            }
            if let position { memory.show(position, in: stackID) }
        }
        .onChange(of: shown, initial: true) { _, id in
            target = id
            turn(to: id)
        }
        .onChange(of: items.map(\.id)) { _, ids in
            // A widget removed in Edit Stack: rest on the one Smart Rotate shows.
            if let position, ids.contains(position) { return }
            position = shown ?? ids.first
        }
        .onChange(of: position) { _, id in
            if let id { memory.show(id, in: stackID) }
        }
        // Edit mode over: catch up with what Smart Rotate shows.
        .onChange(of: isInteractive) { _, _ in turn(to: target) }
        // From the first draw, so a doorbell ring already showing is kept once its banner closes.
        .onChange(of: live, initial: true) { _, live in
            memory.keep(WidgetStackRotation.holding(live: live, held: memory.held[stackID] ?? [:], now: Date()), in: stackID)
        }
        .task(id: decision?.nextCheck) {
            guard let next = decision?.nextCheck else { return }
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            checkedAt = Date()
        }
        .task(id: phase == .idle) {
            // The dots fade a moment after the stack comes to rest.
            guard phase == .idle, showsDots else { return }
            try? await Task.sleep(for: Self.dotsLinger)
            guard !Task.isCancelled else { return }
            withAnimation(Theme.Motion.standard) { showsDots = false }
        }
    }

    /// What each widget that may show says about itself now.
    private func liveRelevance(at now: Date) -> [String: WidgetRelevance] {
        var live: [String: WidgetRelevance] = [:]
        for item in items where item.isAvailable {
            guard let hook = item.widget.relevance else { continue }
            let context = WidgetRelevanceContext(date: now, settings: item.member.settings ?? WidgetSettings(), services: services)
            live[item.id] = hook(context)
        }
        return live
    }

    /// Smart Rotate turns the stack, unless the person is moving it or it is held still for editing.
    private func turn(to id: String?) {
        guard let id, id != position, isInteractive, phase == .idle else { return }
        // The first page shows at once. Only a change moves.
        if position == nil {
            position = id
            return
        }
        withAnimation(reduceMotion ? nil : Theme.Motion.settle) { position = id }
    }

    private func scrolled(to new: ScrollPhase) {
        phase = new
        if new == .interacting { isFlipping = true }
        if new != .idle, !showsDots {
            withAnimation(Theme.Motion.standard) { showsDots = true }
        }
        guard new == .idle else { return }
        if isFlipping {
            // A flip by hand is the person's choice, which Smart Rotate leaves for a while.
            if let position { services.widgetStacks.choose(position, in: stackID) }
            isFlipping = false
        } else {
            // Smart Rotate changed its mind while the stack moved.
            turn(to: target)
        }
    }

    /// VoiceOver's flip, which counts as the person's choice like a swipe.
    private func flip(by step: Int) {
        guard let index = items.firstIndex(where: { $0.id == position }), items.indices.contains(index + step) else { return }
        let id = items[index + step].id
        services.widgetStacks.choose(id, in: stackID)
        withAnimation(reduceMotion ? nil : Theme.Motion.settle) { position = id }
    }

    /// The unit point whose offset puts `id`'s page on screen: 0 is the first, 1 the last.
    private func anchor(for id: String?) -> UnitPoint {
        guard items.count > 1, let index = items.firstIndex(where: { $0.id == id }) else { return .top }
        return UnitPoint(x: 0, y: CGFloat(index) / CGFloat(items.count - 1))
    }
}

/// The small dots beside a stack while it moves, and on a Smart Stack in the
/// widget gallery: one for each widget, the one on top filled, on a glass
/// capsule so they read on any backdrop.
struct StackDots: View {
    let count: Int
    let current: Int

    /// About half the Home Screen's page dots, as iPadOS draws a stack's.
    private static let dotSize: CGFloat = 6

    var body: some View {
        VStack(spacing: Self.dotSize * 0.75) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Color.primary : Color.primary.opacity(0.35))
                    .frame(width: Self.dotSize, height: Self.dotSize)
            }
        }
        .padding(.vertical, Self.dotSize)
        .padding(.horizontal, Self.dotSize * 0.75)
        .glassEffect(.regular, in: Capsule())
        .animation(Theme.Motion.standard, value: current)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
