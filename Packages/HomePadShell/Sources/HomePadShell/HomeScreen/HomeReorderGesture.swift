import HomePadCore
import HomePadUI
import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// The press that lifts a Home Screen item in edit mode, and the drag that
/// follows, for `HomeReorderSession`. UIKit's long press is the gesture the
/// iPadOS Home Screen uses: it knows where it began, keeps tracking the finger
/// once it has, reports a cancel, and while it runs the pages cannot scroll.
/// It fails as soon as a finger lands anywhere but on an item in edit mode,
/// so icons keep their context menu and widgets their long press outside
/// edit mode, and a press on empty space never holds up the pages. It also
/// fails when the finger moves before the short delay, so a quick swipe on an
/// item still turns the page.
struct HomeReorderGesture: UIGestureRecognizerRepresentable {
    let session: HomeReorderSession
    /// The pager's space, which the session's frames are in.
    let space: NamedCoordinateSpace

    func makeUIGestureRecognizer(context: Context) -> LiftRecognizer {
        let recognizer = LiftRecognizer()
        recognizer.minimumPressDuration = HomeReorderSession.liftDelay
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: LiftRecognizer, context: Context) {
        let converter = context.converter
        recognizer.canBegin = { [session, space] point in
            session.canLift(at: converter.convert(globalPoint: point, to: space))
        }
    }

    func handleUIGestureRecognizerAction(_ recognizer: LiftRecognizer, context: Context) {
        let point = context.converter.location(in: space)
        switch recognizer.state {
        case .began: session.begin(at: point)
        case .changed: session.move(to: point)
        case .ended: session.drop(at: point)
        case .cancelled, .failed: session.cancel()
        default: break
        }
    }

    /// A long press that fails as soon as it starts anywhere but on an item.
    final class LiftRecognizer: UILongPressGestureRecognizer {
        /// Whether a press at this point, in window coordinates, may lift an item.
        var canBegin: (CGPoint) -> Bool = { _ in false }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            guard state == .possible, let touch = touches.first else { return }
            if !canBegin(touch.location(in: nil)) { state = .failed }
        }
    }
}

/// The lifted item, drawn over the pages where the finger holds it: a little
/// larger, still, and without its edit controls, as on iPadOS. Its slot in the
/// grid stays open underneath (`HomeScreenPageView`).
struct HomeReorderLiftedTile: View {
    let session: HomeReorderSession
    let metrics: HomeGridMetrics
    let memberID: HouseholdMember.ID?

    var body: some View {
        if let lift = session.lift {
            HomeTileView(tile: lift.tile, metrics: metrics, memberID: memberID, isLifted: true)
                .frame(width: lift.frame.width, height: lift.frame.height)
                .scaleEffect(session.isLifted ? HomeReorderSession.liftScale : 1)
                .offset(x: lift.frame.minX + session.translation.width, y: lift.frame.minY + session.translation.height)
                .allowsHitTesting(false)
        }
    }
}
