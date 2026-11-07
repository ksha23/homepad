import HomePadCore
import HomePadUI
import SwiftUI

extension View {
    /// Press and hold a tile, then slide sideways, to set a light's brightness, a
    /// fan's speed or how far a blind is open. While the finger is down the tile
    /// turns into a slider that shows the new percentage, and the level is sent
    /// when the finger lifts. A quick tap still runs the tile's own action, and a
    /// swipe that starts right away still scrolls or turns the page.
    ///
    /// Put the tile's tap in an `onTapGesture` before this, not a `Button`: a press
    /// gesture and a button on the same tile cannot both work. The tile keeps one
    /// `LevelTapSuppression` and checks it in its tap actions, so the end of a slide
    /// never also toggles the accessory.
    func accessoryLevelDrag(_ accessory: HomeAccessory, cornerRadius: CGFloat, suppression: LevelTapSuppression) -> some View {
        modifier(AccessoryLevelDrag(accessory: accessory, cornerRadius: cornerRadius, suppression: suppression))
    }
}

/// Tells a tile's tap actions to stand down while a level is being set, and for a
/// moment after, since the finger lifting ends both the slide and the button's tap.
@MainActor
final class LevelTapSuppression {
    fileprivate var isAdjusting = false
    fileprivate var until = Date.distantPast

    /// True when a tap should be ignored because it ends a press and slide.
    var shouldIgnoreTap: Bool { isAdjusting || Date() < until }

    fileprivate func finish() {
        isAdjusting = false
        until = Date().addingTimeInterval(0.4)
    }
}

private struct AccessoryLevelDrag: ViewModifier {
    @Environment(\.accessoryCommand) private var send
    let accessory: HomeAccessory
    let cornerRadius: CGFloat
    let suppression: LevelTapSuppression
    /// The level under the finger, while adjusting.
    @State private var adjusting: Double?
    /// The level when the hold began.
    @State private var start: (level: Double, x: CGFloat) = (0, 0)
    @State private var width: CGFloat = 0
    /// True from the recognized hold until the press ends or is cancelled. Gesture
    /// state resets on its own when something else takes the touch (the Home app
    /// tile's menu, a scroll, edit mode), which `onEnded` never hears about. Without
    /// it the slider stayed up for good and the tile ignored every tap.
    @GestureState private var isHolding = false

    /// How long to hold before sliding adjusts the level instead of scrolling.
    private static let holdDuration = 0.25

    func body(content: Content) -> some View {
        if let current = AccessoryPresentation.level(of: accessory) {
            content
                .overlay {
                    if let level = adjusting ?? debugPreview {
                        LevelSliderFace(accessory: accessory, level: level, cornerRadius: cornerRadius)
                            .transition(.opacity)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                // Normal priority, beside the tile's own tap gesture (tiles that use this
                // are not buttons): a quick tap ends as a tap, a hold becomes a slide.
                // With priority over a button it swallowed every tap, and under a
                // button it never ran, because the button inside the tile wins.
                .gesture(pressAndSlide(from: current))
                .onChange(of: isHolding) { _, holding in
                    // A press that ended normally was already handled in `onEnded`.
                    guard !holding, adjusting != nil else { return }
                    adjusting = nil
                    suppression.finish()
                }
                .animation(Theme.Motion.standard, value: adjusting == nil)
                .accessibilityValue("\(AccessoryPresentation.levelName(for: accessory)) \(Int((current * 100).rounded())) percent")
                .accessibilityAdjustableAction { direction in
                    let step = direction == .increment ? 0.1 : -0.1
                    send(AccessoryPresentation.levelCommand(current + step, for: accessory), on: accessory)
                }
        } else {
            content
        }
    }

    private func pressAndSlide(from current: Double) -> some Gesture {
        LongPressGesture(minimumDuration: Self.holdDuration, maximumDistance: 10)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .updating($isHolding) { value, holding, _ in
                if case .second(true, _) = value { holding = true }
            }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                // The slider shows as soon as the hold is recognized, so it is clear
                // the press now slides. Releasing without sliding changes nothing.
                if adjusting == nil {
                    start = (current, 0)
                    suppression.isAdjusting = true
                }
                adjusting = LevelDragMath.level(from: start.level, translation: drag?.translation.width ?? 0, width: width)
            }
            .onEnded { value in
                defer {
                    adjusting = nil
                    suppression.finish()
                }
                guard case .second(true, let drag?) = value else { return }
                let level = LevelDragMath.level(from: start.level, translation: drag.translation.width, width: width)
                guard LevelDragMath.percent(level) != LevelDragMath.percent(start.level) else { return }
                send(AccessoryPresentation.levelCommand(level, for: accessory), on: accessory)
            }
    }

    /// The level `-HomePadSmartHomeAdjusting` pins for screenshots, in debug builds.
    private var debugPreview: Double? {
        guard let pinned = SmartHomeLaunchOptions.atLaunch.adjusting, pinned.accessoryID == accessory.id else { return nil }
        return pinned.level
    }
}

/// How a sideways drag turns into a level. Sliding across the whole tile goes from
/// 0 to 100 percent, so a narrow tile still has a usable range.
enum LevelDragMath {
    /// The narrowest distance that covers the whole range, for small tiles.
    static let minimumTrack: CGFloat = 160

    static func level(from start: Double, translation: CGFloat, width: CGFloat) -> Double {
        min(1, max(0, start + Double(translation / max(width, minimumTrack))))
    }

    /// The whole percentage a level shows as.
    static func percent(_ level: Double) -> Int {
        Int((min(max(level, 0), 1) * 100).rounded())
    }
}

/// What a tile shows while its level is being dragged: a track of the page's
/// color (dark in Dark, light in Light) filled to the level in the accessory's
/// color, its symbol, name and the percentage. Text is the page's text color
/// over the track and black over the fill, like Control Center.
private struct LevelSliderFace: View {
    let accessory: HomeAccessory
    let level: Double
    let cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        GeometryReader { proxy in
            let filled = proxy.size.width * level
            ZStack(alignment: .leading) {
                Color.screenBackground.opacity(0.45)
                // The same color as the resting fill, so lifting the finger leaves
                // the fill where the slider showed it.
                Rectangle().fill(Theme.tint(for: accessory.kind).opacity(0.9)).frame(width: filled)
                labels(isTall: proxy.size.height > 100).foregroundStyle(Color.primary)
                labels(isTall: proxy.size.height > 100).foregroundStyle(.black)
                    .mask(alignment: .leading) { Rectangle().frame(width: filled) }
            }
        }
        .background(.ultraThinMaterial)
        .clipShape(shape)
        .overlay { shape.strokeBorder(.primary.opacity(0.15), lineWidth: 1) }
        .accessibilityHidden(true)
    }

    private var percentText: some View {
        Text("\(LevelDragMath.percent(level))%")
            .monospacedDigit()
            .contentTransition(.numericText(value: level))
    }

    private var symbol: String {
        var lit = accessory
        lit.state.isOn = level > 0
        lit.state.position = level
        return AccessoryPresentation.symbol(for: lit)
    }

    /// A row: symbol, name and the percentage at the end. A tall tile: the symbol
    /// at the top, then a big percentage over the name.
    @ViewBuilder
    private func labels(isTall: Bool) -> some View {
        if isTall {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Image(systemName: symbol).font(.title.weight(.semibold))
                Spacer(minLength: 0)
                percentText.font(.largeTitle.weight(.bold))
                Text(accessory.name).font(.headline).lineLimit(1)
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: symbol).font(.title3.weight(.semibold)).frame(width: 40)
                Text(accessory.name).font(.headline).lineLimit(1)
                Spacer(minLength: 0)
                percentText.font(.title2.weight(.bold))
            }
            .padding(.horizontal, Theme.Spacing.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
