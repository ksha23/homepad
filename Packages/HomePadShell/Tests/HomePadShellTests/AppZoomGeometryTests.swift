import CoreGraphics
import Testing
@testable import HomePadShell

@Suite struct AppZoomGeometryTests {
    private let zoom = AppZoomGeometry.standard
    /// A portrait iPad and an icon in its upper right.
    private let screen = CGRect(x: 0, y: 0, width: 1000, height: 1400)
    private let icon = CGRect(x: 600, y: 200, width: 100, height: 100)

    private func close(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.001) -> Bool { abs(a - b) < tolerance }

    private func look(_ pose: ZoomPose) -> AppZoomGeometry.Look {
        zoom.look(at: pose, screen: screen, iconSide: icon.width, iconCornerRadius: 26)
    }

    @Test func theIconPoseSitsTheWindowOnTheIcon() {
        let pose = zoom.iconPose(icon: icon, screen: screen)
        #expect(close(pose.scale, 0.1))
        #expect(close(screen.midX + pose.offset.width, icon.midX))
        #expect(close(screen.midY + pose.offset.height, icon.midY))
        // And there the window is the icon: its square, its corners, its picture.
        let end = look(pose)
        #expect(close(end.maskSize.width * pose.scale, icon.width))
        #expect(close(end.maskSize.height * pose.scale, icon.width))
        #expect(close(end.cornerRadius * pose.scale, 26))
        #expect(end.iconFace == 1)
    }

    /// An app opened from a widget lands on the widget: its size, its shape and its corners, wide or tall.
    @Test func aWidgetPoseSitsTheWindowOnTheWidget() {
        for widget in [CGRect(x: 100, y: 300, width: 420, height: 200), CGRect(x: 100, y: 300, width: 200, height: 640)] {
            let pose = zoom.iconPose(icon: widget, screen: screen)
            #expect(close(screen.midX + pose.offset.width, widget.midX))
            #expect(close(screen.midY + pose.offset.height, widget.midY))
            let end = zoom.look(at: pose, screen: screen, target: widget.size, cornerRadius: 28,
                                widgetTurn: zoom.widgetTurn(closeness: 1))
            #expect(close(end.maskSize.width * pose.scale, widget.width))
            #expect(close(end.maskSize.height * pose.scale, widget.height))
            #expect(close(end.cornerRadius * pose.scale, 28))
            // Its shape fits inside the screen at every step, so the picture always fills the window.
            #expect(end.maskSize.width <= screen.width + 0.001 && end.maskSize.height <= screen.height + 0.001)
            #expect(end.iconFace == 1)
            // Held by a finger, however small, the window is still the app's frozen picture in the screen's shape.
            let held = ZoomPose(scale: pose.scale * 0.9, offset: .zero)
            let swipe = zoom.look(at: held, screen: screen, target: widget.size, cornerRadius: 28,
                                  widgetTurn: zoom.widgetTurn(closeness: 0))
            #expect(swipe.iconFace == 0)
            #expect(close(swipe.maskSize.width / swipe.maskSize.height, screen.width / screen.height))
            // Flying, its shape turns over the whole way and it melts in from about a third of the way.
            let early = zoom.widgetTurn(closeness: 0.2)
            #expect(early.shape > 0 && early.fade == 0)
            let late = zoom.widgetTurn(closeness: 0.8)
            #expect(late.shape > 0.8 && late.fade > 0 && late.fade < 1)
        }
    }

    @Test func fullScreenHasSquareCornersAndNoPicture() {
        let rest = look(.full)
        #expect(rest.maskSize == screen.size)
        #expect(rest.cornerRadius == 0)
        #expect(rest.iconFace == 0)
    }

    /// The reference: the window keeps the screen's shape and opacity with rounded
    /// corners until it is about twice the icon's size.
    @Test func aBigWindowKeepsTheScreensShapeWithRoundedCorners() {
        for scale in [0.9, 0.6, 0.3, 0.2] as [CGFloat] {
            let mid = look(ZoomPose(scale: scale, offset: .zero))
            #expect(mid.maskSize == screen.size)
            #expect(close(mid.cornerRadius * scale, zoom.cornerRadius))
            #expect(mid.iconFace == 0)
        }
    }

    @Test func itBecomesTheIconOnlyBelowTwiceItsSize() {
        let iconScale: CGFloat = 0.1
        #expect(look(ZoomPose(scale: iconScale * zoom.morphFrom, offset: .zero)).iconFace == 0)
        #expect(look(ZoomPose(scale: iconScale * zoom.faceBy, offset: .zero)).iconFace == 1)
        let halfway = look(ZoomPose(scale: iconScale * 1.5, offset: .zero))
        // Portrait: the width is already the short side, the height comes down to it.
        #expect(halfway.maskSize.width == screen.width && halfway.maskSize.height < screen.height)
        #expect(halfway.maskSize.height > halfway.maskSize.width)
    }

    @Test func cornersComeOnQuicklyAsTheWindowLeavesFullScreen() {
        let start = look(ZoomPose(scale: 1 - zoom.cornerEase / 2, offset: .zero))
        #expect(start.cornerRadius > 0 && start.cornerRadius < zoom.cornerRadius)
        // An open that overshoots past full screen stays square.
        #expect(look(ZoomPose(scale: 1.03, offset: .zero)).cornerRadius == 0)
    }

    @Test func aSwipeKeepsTheBottomEdgeUnderTheFinger() {
        for up in [0, 100, 400, 900] as [CGFloat] {
            let pose = zoom.dragPose(translation: CGSize(width: 30, height: -up), screen: screen)
            let bottom = screen.midY + pose.offset.height + pose.scale * screen.height / 2
            #expect(close(bottom, screen.maxY - up, 0.01))
            #expect(close(pose.offset.width, 30))
        }
        #expect(zoom.dragPose(translation: CGSize(width: 0, height: -5000), screen: screen).scale == zoom.dragMinScale)
        #expect(zoom.dragPose(translation: CGSize(width: 0, height: 80), screen: screen) == .full)
    }

    @Test func withoutAnIconItLandsOnACenteredStandIn() {
        let standIn = zoom.fallbackIcon(screen: screen)
        #expect(close(standIn.midX, screen.midX) && close(standIn.midY, screen.midY))
        #expect(standIn.width == zoom.fallbackIconSide)
    }

    @Test func onlyAnIconFullyOnScreenIsATarget() {
        #expect(zoom.target(icon: icon, screen: screen) == icon)
        #expect(zoom.target(icon: nil, screen: screen) == nil)
        #expect(zoom.target(icon: CGRect(x: 1100, y: 200, width: 100, height: 100), screen: screen) == nil)
        #expect(zoom.target(icon: .zero, screen: screen) == nil)
    }

    /// Letting go hands the spring the window's own speed, which is how fast `dragPose` changes.
    @Test func lettingGoKeepsTheWindowsSpeed() {
        let pose = zoom.dragPose(translation: CGSize(width: 0, height: -300), screen: screen)
        let v = zoom.dragVelocity(CGSize(width: 50, height: -1000), at: pose, screen: screen)
        // Numerically: where the window is a moment later, from the finger a moment later.
        let dt: CGFloat = 0.001
        let later = zoom.dragPose(translation: CGSize(width: 50 * dt, height: -300 - 1000 * dt), screen: screen)
        #expect(close(v.first, (later.scale - pose.scale) / dt, 0.01))
        #expect(close(v.second.first, 50, 0.01))
        #expect(close(v.second.second, (later.offset.height - pose.offset.height) / dt, 0.5))
    }

    @Test func theHomeScreenSitsBackOnlyWhileAnAppIsOpen() {
        #expect(zoom.homeScale(receded: false) == 1)
        #expect(zoom.homeDimming(receded: false) == 0)
        #expect(close(zoom.homeScale(receded: true), 1 - zoom.homeRecession))
        #expect(close(zoom.homeDimming(receded: true), zoom.homeDim))
        #expect(zoom.homeBlur(receded: false) == 0)
        #expect(close(zoom.homeBlur(receded: true), zoom.homeBlurRadius))
    }
}
