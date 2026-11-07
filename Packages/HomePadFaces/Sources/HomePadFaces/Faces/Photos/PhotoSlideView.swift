import HomePadCore
import HomePadUI
import SwiftUI

/// One photo on the Photos face: the picture with a slow Ken Burns move, the
/// time, and (for the depth style) the subject cut out and drawn again on top
/// of the time, so the numerals sit behind the people in the photo. Behind
/// the Home Screen it is the picture alone (`faceForeground()`).
///
/// The move redraws the whole screen on every frame, so it holds still where
/// it is while motion is off (`faceAllowsMotion`: behind the Home Screen's
/// frost, beside the face on the wall, dimmed, at night, asleep) and carries
/// on from there afterwards.
struct PhotoSlideView: View {
    let frame: PhotoFrame
    let motion: KenBurnsMotion
    /// Seconds the Ken Burns move takes. A bit longer than the slide interval.
    let duration: TimeInterval
    let wantsDepth: Bool
    /// The time's color, or nil for a tint taken from the photo.
    let timeColor: FaceTextColor?
    let viewSize: CGSize
    /// Where One Photo puts the photo. Slideshows fill the screen, centered.
    var framing = PhotoFraming()
    /// Where the time is drawn from across the room and up close. The depth
    /// effect measures the numerals where they are at the distance shown.
    let clock: PhotoClockLayout

    @Environment(\.displayCondition) private var condition
    @Environment(\.proximity) private var proximity
    @Environment(\.faceAllowsMotion) private var allowsMotion
    @Environment(\.isThumbnail) private var isThumbnail
    /// How far through the Ken Burns move the photo is, from 0 to 1.
    @State private var progress: CGFloat = 0
    /// When the current stretch of the move started, and from what progress.
    @State private var stretch: (start: Date, progress: CGFloat)?

    var body: some View {
        let isNight = condition == .night
        let isNear = proximity >= .mid
        let depth = wantsDepth && frame.mask != nil && usesDepth(isNear: isNear)
        ZStack {
            photo
                .modifier(KenBurnsEffect(motion: motion, progress: progress))
                .modifier(NightPhoto(isNight: isNight))
            // Behind the Home Screen the photo is all there is.
            ZStack {
                PhotoClock(isDepthStyle: wantsDepth, tint: clockTint(isNight: isNight), layout: clock, isNear: isNear,
                           isNight: isNight, showsDate: !depth)
                // The subject drawn again over the time. When walking up or away
                // changes whether the subject leaves enough of the time showing, it
                // fades with the time's move.
                if depth, let mask = frame.mask {
                    photo
                        .mask { placed(Image(decorative: mask, scale: 1)) }
                        .modifier(KenBurnsEffect(motion: motion, progress: progress))
                        .modifier(NightPhoto(isNight: isNight))
                        .transition(.opacity)
                    // The date never goes behind the subject: it is small, and
                    // half of it hidden reads as nothing.
                    PhotoClock(isDepthStyle: wantsDepth, tint: clockTint(isNight: isNight), layout: clock, isNear: isNear,
                               isNight: isNight, showsTime: false)
                }
            }
            .faceForeground()
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .clipped()
        .onAppear {
            if duration <= 0 {
                progress = 1
            } else if allowsMotion {
                move()
            }
        }
        .onChange(of: allowsMotion) { _, allowed in
            allowed ? move() : hold()
        }
        .task(id: "\(Int(viewSize.width))x\(Int(viewSize.height))|\(frame.id)|\(wantsDepth)|\(isNear)|\(clock.nearLine.maxY)") {
            let coverage = coverages(isNear: isNear)
            PhotoTrace.depth(frame, viewSize: viewSize, timeCoverage: coverage?.time, subjectCoverage: coverage?.subject,
                             wantsDepth: wantsDepth, uses: depth, isNear: isNear, isThumbnail: isThumbnail)
        }
    }

    /// Moves on from the current progress to the end, at the slide's speed.
    private func move() {
        guard duration > 0, stretch == nil, progress < 1 else { return }
        stretch = (Date(), progress)
        withAnimation(.linear(duration: Double(1 - progress) * duration)) { progress = 1 }
    }

    /// Stops the move where it is. The move is linear, so where it is follows from the time.
    private func hold() {
        guard let stretch else { return }
        self.stretch = nil
        let reached = stretch.progress + CGFloat(Date().timeIntervalSince(stretch.start) / duration)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { progress = min(reached, 1) }
    }

    private var photo: some View {
        placed(Image(decorative: frame.image, scale: 1))
    }

    /// The photo, or its subject mask, at the framing's size and offset on the
    /// screen. The plain framing fills the screen, centered.
    private func placed(_ image: Image) -> some View {
        let placement = framing.placement(imageSize: frame.imageSize, viewSize: viewSize)
        return image
            .resizable()
            .frame(width: placement.size.width, height: placement.size.height)
            .offset(placement.offset)
            .frame(width: viewSize.width, height: viewSize.height)
            .clipped()
    }

    /// True when the subject leaves enough of the numerals visible at a distance.
    private func usesDepth(isNear: Bool) -> Bool {
        guard let coverage = coverages(isNear: isNear) else { return false }
        return DepthLayout.usesDepth(timeCoverage: coverage.time, subjectCoverage: coverage.subject)
    }

    /// How much of the numerals' area, where they are drawn at a distance, and
    /// of the whole photo the subject covers.
    private func coverages(isNear: Bool) -> (time: Double, subject: Double)? {
        guard let sample = frame.sample else { return nil }
        let timeRect = framing.imageRect(forViewRect: clock.digits(isNear: isNear), viewSize: viewSize, imageSize: frame.imageSize)
        return (sample.coverage(in: timeRect), sample.coverage(in: CGRect(x: 0, y: 0, width: 1, height: 1)))
    }

    private func clockTint(isNight: Bool) -> Color {
        if isNight { return Theme.nightRed }
        if let timeColor { return timeColor.rgb.color }
        let tint = frame.tint.numeralTint()
        return Color(red: tint.red, green: tint.green, blue: tint.blue)
    }
}

/// Scales the photo toward an anchor over the slide's lifetime.
private struct KenBurnsEffect: ViewModifier {
    let motion: KenBurnsMotion
    /// 0 at the start scale, 1 at the end scale.
    let progress: CGFloat

    func body(content: Content) -> some View {
        content.scaleEffect(motion.startScale + (motion.endScale - motion.startScale) * progress,
                            anchor: UnitPoint(x: motion.anchor.x, y: motion.anchor.y))
    }
}

/// Night mode for photos: a dim red monochrome, so a bedroom stays dark.
private struct NightPhoto: ViewModifier {
    let isNight: Bool

    func body(content: Content) -> some View {
        if isNight {
            content
                .grayscale(1)
                .colorMultiply(Theme.nightRed)
                .brightness(-0.2)
                .opacity(0.55)
        } else {
            content
        }
    }
}
