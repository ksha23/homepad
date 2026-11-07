import SwiftUI
import UIKit

/// Hosts the Home Screen's icons and widgets in a UIKit view of their own, so they can sit back
/// behind an open app the way iPadOS does it: Core Animation scales the finished layer, and the
/// layout never sees the scale. A SwiftUI scale effect reaches layout. Under one, the paging
/// scroll view worked its pages out again on every frame, and the icons shifted sideways and back
/// as an app closed.
struct HomeScreenHost<Content: View>: UIViewControllerRepresentable {
    /// True while an app is open over the Home Screen.
    var receded: Bool
    @ViewBuilder var content: Content
    /// Read so that VoiceOver or another assistive technology coming on runs an update, which hands the
    /// content a fresh copy of the environment. As in `SuspendableHost`, a copy made while it was off
    /// leaves the content with no accessibility elements.
    @Environment(\.accessibilityEnabled) private var accessibilityEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    func makeUIViewController(context: Context) -> HomeScreenHostController {
        HomeScreenHostController(rootView: hosted(context))
    }

    func updateUIViewController(_ controller: HomeScreenHostController, context: Context) {
        controller.host.rootView = hosted(context)
        let scale = AppZoomGeometry.standard.homeScale(receded: receded)
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        guard controller.host.view.transform != transform else { return }
        // With the animation of the screen change that set it, as a SwiftUI scale had.
        context.animate { controller.host.view.transform = transform }
    }

    /// The content with the shell's environment, which does not cross into a hosting controller by itself.
    /// Neither does `accessibilityHidden`, so behind an open app the Home Screen hides itself from VoiceOver
    /// and UI tests here. Its controls showed up beside the app's.
    private func hosted(_ context: Context) -> AnyView {
        AnyView(content.environment(\.self, context.environment).accessibilityHidden(receded))
    }
}

/// Holds the Home Screen's hosting controller and keeps its view on the container's bounds, so the
/// scale is set on that view while SwiftUI sizes the container.
final class HomeScreenHostController: UIViewController {
    let host: UIHostingController<AnyView>

    init(rootView: AnyView) {
        host = UIHostingController(rootView: rootView)
        // The Home Screen lays itself out from the screen's edges. Taking no safe area also keeps the
        // scale, which moves the view on screen, from reaching its layout.
        host.safeAreaRegions = []
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(host)
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Bounds and center rather than frame, which a scale makes meaningless.
        host.view.bounds = CGRect(origin: .zero, size: view.bounds.size)
        host.view.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    }
}
