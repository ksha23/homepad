import SwiftUI
import UIKit

/// Hosts one app in a UIKit view of its own, so it can be suspended like an iPadOS app. While it
/// is not active its view leaves the window: SwiftUI tells everything in it that it disappeared
/// (`onDisappear`, tasks cancelled), so cameras, audio and polling stop as they do when an app
/// closes, while its state stays in the host. Made active again, it comes back as it was left.
///
/// Compared with `.equatable()`, so the app's content is handed to its host again only when
/// `isActive`, `isCovered`, `inputs` or the environment change. The shell evaluates every app's host
/// on each screen change, and handing over each app's whole content then took the main thread from the zoom.
struct SuspendableHost<Content: View>: UIViewControllerRepresentable, Equatable {
    /// The app it hosts. Its host joins `hosts` under this ID.
    var appID: String
    /// Where the navigator finds the app's host, to show or hide what the app presents.
    var hosts: AppHostRegistry
    /// True while the app is in the window: on screen, or kept alive under the one on screen.
    var isActive: Bool
    /// True while the app is in the window but not the one on screen, such as Music under Now Playing
    /// or an app whose close is still landing.
    var isCovered = false
    /// What the content shows, other than which app it is. The content holds closures, which never compare equal.
    var inputs: AnyHashable
    @ViewBuilder var content: Content
    /// Whether VoiceOver or another assistive technology is on, which a UI test also turns on. The content
    /// keeps the copy of the environment made at the last update (`hosted`), and nothing else here reads
    /// these, so turning one on did not run an update. With the copy saying it was off, the app's views
    /// made no accessibility elements, and VoiceOver and UI tests found the app empty. Read here, a change
    /// runs an update, and the content gets a fresh copy.
    @Environment(\.accessibilityEnabled) private var accessibilityEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isActive == rhs.isActive && lhs.isCovered == rhs.isCovered && lhs.inputs == rhs.inputs
    }

    func makeUIViewController(context: Context) -> SuspendableHostController {
        let controller = SuspendableHostController(rootView: hosted(context))
        hosts.register(controller, for: appID)
        return controller
    }

    func updateUIViewController(_ controller: SuspendableHostController, context: Context) {
        controller.host.rootView = hosted(context)
        controller.isActive = isActive
    }

    /// The content with the shell's environment, which does not cross into a hosting controller by itself.
    /// Neither does `accessibilityHidden`, so a covered app hides itself from VoiceOver and UI tests here.
    /// Its controls showed up beside those of the app on screen.
    private func hosted(_ context: Context) -> AnyView {
        AnyView(content.environment(\.self, context.environment).accessibilityHidden(isCovered))
    }
}

/// Holds an app's hosting controller and puts its view in the window only while the app is active.
/// What the app presents goes with it: hidden while the app is not what the screen shows, and
/// dismissed when the app is suspended (`AppHostingController`).
final class SuspendableHostController: UIViewController {
    let host: AppHostingController

    var isActive = false {
        didSet { if isActive != oldValue { attach() } }
    }

    /// False while what the app presents must not show: the app is not the one on screen, or the zoom's
    /// picture stands in for it. Set by the navigator through `AppHostRegistry`.
    var showsPresentations: Bool {
        get { host.showsPresentations }
        set { host.showsPresentations = newValue }
    }

    /// Told when the app is suspended with something presented, once that is dismissed.
    var onDismissPresentations: () -> Void = {}

    init(rootView: AnyView) {
        host = AppHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        addChild(host)
        host.view.backgroundColor = .clear
        host.didMove(toParent: self)
        attach()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        host.view.frame = view.bounds
    }

    /// Puts the app's view in the window, or takes it out, to match `isActive`. A suspended app's
    /// presentations are dismissed first: UIKit draws them above the whole shell, so they would stay over
    /// the Home Screen, keep a camera or a video going, and keep anything else from being presented.
    private func attach() {
        guard isViewLoaded else { return }
        view.isUserInteractionEnabled = isActive
        if isActive, host.view.superview == nil {
            host.view.frame = view.bounds
            view.addSubview(host.view)
        } else if !isActive, host.view.superview != nil {
            if host.dismissPresentations() { onDismissPresentations() }
            host.view.removeFromSuperview()
        }
    }
}

/// An app's hosting controller. SwiftUI presents the app's sheets, full-screen covers and alerts through
/// it, and UIKit puts them above the whole shell, from the window's root. It keeps them so the shell can
/// hide them while the app is not what the screen shows, and dismiss them when the app is suspended.
final class AppHostingController: UIHostingController<AnyView> {
    /// What the app presented, the first of each stack. What those present in turn sits above them.
    private let presented = NSHashTable<UIViewController>.weakObjects()

    /// False hides what the app presents, without dismissing it, so it shows again as it was.
    var showsPresentations = true {
        didSet { if showsPresentations != oldValue { applyVisibility() } }
    }

    /// A presentation made while the app is hidden under the zoom shows at once, like the player that
    /// Now Playing opens over Music while Music zooms open.
    override func present(_ controller: UIViewController, animated: Bool, completion: (() -> Void)? = nil) {
        presented.add(controller)
        super.present(controller, animated: animated, completion: completion)
    }

    /// Dismisses everything the app presents, at once. True when there was something.
    @discardableResult
    func dismissPresentations() -> Bool {
        let stacks = presentedStacks
        presented.removeAllObjects()
        for controller in stacks { controller.dismiss(animated: false) }
        return !stacks.isEmpty
    }

    /// The first controller of each stack the app presented that is still up.
    private var presentedStacks: [UIViewController] {
        presented.allObjects.filter { $0.presentingViewController != nil && !$0.isBeingDismissed }
    }

    /// Hides or shows each presentation's container, the view UIKit puts in the window for it, with
    /// everything presented above it. Hidden, it is still laid out and keeps its finger, so the bar a
    /// cover draws keeps following a swipe that hid it.
    private func applyVisibility() {
        for stack in presentedStacks {
            var next: UIViewController? = stack
            while let controller = next {
                controller.presentationController?.containerView?.alpha = showsPresentations ? 1 : 0
                next = controller.presentedViewController
            }
        }
    }
}
