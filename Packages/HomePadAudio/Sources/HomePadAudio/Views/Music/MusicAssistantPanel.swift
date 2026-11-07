import HomePadCore
import HomePadUI
import SwiftUI
import WebKit

/// Music Assistant's own web UI as an optional, secondary panel, inside HomePad
/// chrome. The native Music and Now Playing screens stay primary. CSS injected
/// at document end gives it HomePad's page color (black in Dark, white in
/// Light), system font, accent and corner radius so it does not look bolted on.
struct MusicAssistantPanel: View {
    @Environment(AppServices.self) private var services
    let onClose: () -> Void

    var body: some View {
        AppScreen("Music Assistant", onClose: onClose) {
            if let url = MusicAssistantPanel.url(from: services.settings[AudioSettings.musicAssistantURL]) {
                ThemedWebView(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            } else {
                EmptyStateView("Music Assistant Not Set Up",
                               message: "Add your Music Assistant address in Settings, under Audio and AirPlay.",
                               systemImage: "hifispeaker.2")
            }
        }
        .background(Color.screenBackground.ignoresSafeArea())
    }

    /// Accepts "homeassistant.local:8095" or a full URL.
    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let url = URL(string: withScheme), url.host() != nil else { return nil }
        return url
    }
}

private struct ThemedWebView: UIViewRepresentable {
    let url: URL

    /// HomePad tokens for Music Assistant's Vuetify interface. The web view
    /// reports HomePad's appearance as `prefers-color-scheme`, so the page
    /// follows Light and Dark like the rest of the app.
    static let css = """
    :root { color-scheme: light dark; --v-theme-primary: 255,55,95; }
    @media (prefers-color-scheme: dark) {
      :root { --v-theme-background: 0,0,0; --v-theme-surface: 28,28,30; }
      html, body, #app, .v-application, .v-main, .v-navigation-drawer, .v-app-bar, .v-toolbar, .v-bottom-navigation {
        background: #000 !important;
      }
    }
    @media (prefers-color-scheme: light) {
      :root { --v-theme-background: 255,255,255; --v-theme-surface: 242,242,247; }
      html, body, #app, .v-application, .v-main, .v-navigation-drawer, .v-app-bar, .v-toolbar, .v-bottom-navigation {
        background: #fff !important;
      }
    }
    * { font-family: -apple-system, system-ui, sans-serif !important; }
    .v-card, .v-sheet, .v-list, .v-dialog > .v-overlay__content > * { border-radius: \(Int(Theme.Radius.card))px !important; }
    .v-btn { border-radius: \(Int(Theme.Radius.pill))px !important; }
    """

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let source = "var s=document.createElement('style');s.textContent=\(Self.javaScriptString(Self.css));document.head.appendChild(s);"
        configuration.userContentController.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .systemBackground
        view.scrollView.backgroundColor = .systemBackground
        view.allowsBackForwardNavigationGestures = true
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    private static func javaScriptString(_ text: String) -> String {
        let data = (try? JSONEncoder().encode(text)) ?? Data("\"\"".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}
