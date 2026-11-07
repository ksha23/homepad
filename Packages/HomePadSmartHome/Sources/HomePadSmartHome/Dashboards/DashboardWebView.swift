import SwiftUI
import WebKit

/// What the dashboard web view shows.
struct DashboardPage: Hashable {
    var url: URL
    /// Set for Home Assistant pages: the frontend gets this token through its external
    /// auth bridge and the full HomePad theme. Other web panels only get a dark background.
    var homeAssistantToken: String?
}

/// A `WKWebView` themed to match HomePad. For Home Assistant it answers the frontend's
/// documented external auth calls (`getExternalAuth`, `revokeExternalAuth`) with the
/// stored long-lived token, so there is no second login. Give it a new `.id` per page.
struct DashboardWebView: UIViewRepresentable {
    let page: DashboardPage
    var accent: Color

    func makeCoordinator() -> Coordinator {
        Coordinator(token: page.homeAssistantToken)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        if page.homeAssistantToken != nil {
            controller.addUserScript(WKUserScript(source: DashboardTheme.earlySetupScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
            controller.addUserScript(WKUserScript(source: DashboardTheme.styleScript(DashboardTheme.homeAssistantCSS(accent: accent)),
                                                  injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            controller.addUserScript(WKUserScript(source: DashboardTheme.kioskScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
            for name in Coordinator.messageNames { controller.add(context.coordinator, name: name) }
        } else {
            controller.addUserScript(WKUserScript(source: DashboardTheme.styleScript(DashboardTheme.panelCSS),
                                                  injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.webView = webView
        webView.load(URLRequest(url: page.url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        for name in Coordinator.messageNames {
            webView.configuration.userContentController.removeScriptMessageHandler(forName: name)
        }
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        static let messageNames = ["getExternalAuth", "revokeExternalAuth"]
        weak var webView: WKWebView?
        private let token: String?

        init(token: String?) {
            self.token = token
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let callback = body["callback"] as? String,
                  callback.range(of: "^[A-Za-z0-9_$]+$", options: .regularExpression) != nil else { return }
            let script: String
            switch message.name {
            case "getExternalAuth":
                guard let token, let data = try? JSONSerialization.data(withJSONObject: ["access_token": token, "expires_in": 86_400]),
                      let json = String(data: data, encoding: .utf8) else {
                    script = "window.\(callback)(false);"
                    break
                }
                script = "window.\(callback)(true, \(json));"
            default:
                script = "window.\(callback)(true);"
            }
            webView?.evaluateJavaScript(script)
        }
    }
}
