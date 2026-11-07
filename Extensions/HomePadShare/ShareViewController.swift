import HomePadShareKit
import SwiftUI
import UIKit

/// "Send to HomePad" in the system share sheet. It reads the shared URL, text
/// or image, lets the person pick a HomePad, and queues the item in the App
/// Group outbox. The HomePad app delivers it over the peer link (see README).
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareComposeModel(extensionContext: extensionContext)
        let host = UIHostingController(rootView: ShareComposeView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}
