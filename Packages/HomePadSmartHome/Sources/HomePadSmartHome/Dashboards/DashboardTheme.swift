import HomePadUI
import SwiftUI
import UIKit

/// CSS and scripts that make Home Assistant's frontend look like part of HomePad:
/// HomePad's page color, glass-like cards with HomePad's corner radius, the system
/// font, HomePad's accent, and no Home Assistant header or sidebar.
///
/// The page follows HomePad's appearance. The web view reports it as
/// `prefers-color-scheme`, so the colors sit in a dark and a light block, and Home
/// Assistant's own theme follows it too: black with white text in Dark (and at
/// night), white with black text in Light.
enum DashboardTheme {
    /// Runs before the frontend loads: the default theme in automatic mode, which
    /// follows `prefers-color-scheme`, and a hidden sidebar, both stored where
    /// Home Assistant keeps the person's own choices.
    static let earlySetupScript = """
    try {
      localStorage.setItem('dockedSidebar', JSON.stringify('always_hidden'));
      localStorage.setItem('selectedTheme', JSON.stringify({ theme: 'default' }));
    } catch (e) {}
    """

    /// Home Assistant theme variables, set with priority so they win over the active theme.
    static func homeAssistantCSS(accent: Color) -> String {
        let accentHex = hex(accent)
        let radius = Int(Theme.Radius.tile)
        return """
        :root, html {
          color-scheme: light dark;
          --ha-card-border-radius: \(radius)px !important;
          --ha-card-border-width: 1px !important;
          --ha-card-box-shadow: none !important;
          --primary-color: \(accentHex) !important;
          --accent-color: \(accentHex) !important;
          --app-header-background-color: transparent !important;
          --header-height: 0px !important;
          --primary-font-family: -apple-system, system-ui, "SF Pro Text", sans-serif !important;
          --paper-font-common-base_-_font-family: -apple-system, system-ui, sans-serif !important;
          --mdc-typography-font-family: -apple-system, system-ui, sans-serif !important;
          --ha-font-family-body: -apple-system, system-ui, sans-serif !important;
          --ha-font-family-heading: -apple-system, system-ui, sans-serif !important;
        }
        @media (prefers-color-scheme: dark) {
          :root, html {
            --primary-background-color: #000000 !important;
            --secondary-background-color: #000000 !important;
            --lovelace-background: #000000 !important;
            --card-background-color: rgba(255, 255, 255, 0.08) !important;
            --ha-card-background: rgba(255, 255, 255, 0.08) !important;
            --ha-card-border-color: rgba(255, 255, 255, 0.15) !important;
            --primary-text-color: #ffffff !important;
            --secondary-text-color: rgba(235, 235, 245, 0.6) !important;
            --disabled-text-color: rgba(235, 235, 245, 0.3) !important;
            --divider-color: rgba(255, 255, 255, 0.12) !important;
            --state-icon-color: rgba(255, 255, 255, 0.85) !important;
            --paper-item-icon-color: rgba(255, 255, 255, 0.85) !important;
            --sidebar-background-color: #000000 !important;
          }
          html, body { background: #000000 !important; }
        }
        @media (prefers-color-scheme: light) {
          :root, html {
            --primary-background-color: #ffffff !important;
            --secondary-background-color: #ffffff !important;
            --lovelace-background: #ffffff !important;
            --card-background-color: rgba(120, 120, 128, 0.08) !important;
            --ha-card-background: rgba(120, 120, 128, 0.08) !important;
            --ha-card-border-color: rgba(0, 0, 0, 0.08) !important;
            --primary-text-color: #000000 !important;
            --secondary-text-color: rgba(60, 60, 67, 0.6) !important;
            --disabled-text-color: rgba(60, 60, 67, 0.3) !important;
            --divider-color: rgba(60, 60, 67, 0.18) !important;
            --state-icon-color: rgba(0, 0, 0, 0.7) !important;
            --paper-item-icon-color: rgba(0, 0, 0, 0.7) !important;
            --sidebar-background-color: #ffffff !important;
          }
          html, body { background: #ffffff !important; }
        }
        html, body { font-family: -apple-system, system-ui, sans-serif !important; }
        """
    }

    /// Hides the dashboard header and the sidebar inside the frontend's shadow DOM.
    /// The frontend re-renders as people navigate, so it checks again periodically.
    static let kioskScript = """
    (function () {
      const headerCSS = '.header, app-header, app-toolbar, .toolbar { display: none !important; } ' +
        '#view, hui-view, .view { padding-top: 0 !important; margin-top: 0 !important; } ' +
        ':host { --header-height: 0px !important; }';
      const sidebarCSS = 'ha-sidebar { display: none !important; } :host { --mdc-drawer-width: 0px !important; }';
      function inject(root, id, text) {
        if (!root || root.querySelector('#' + id)) return;
        const style = document.createElement('style');
        style.id = id;
        style.textContent = text;
        root.appendChild(style);
      }
      function walk(root, visit) {
        root.querySelectorAll('*').forEach(function (element) {
          visit(element);
          if (element.shadowRoot) walk(element.shadowRoot, visit);
        });
      }
      function apply() {
        walk(document, function (element) {
          const tag = element.tagName.toLowerCase();
          if (tag === 'hui-root' && element.shadowRoot) inject(element.shadowRoot, 'homepad-kiosk', headerCSS);
          if (tag === 'home-assistant-main' && element.shadowRoot) inject(element.shadowRoot, 'homepad-sidebar', sidebarCSS);
        });
      }
      apply();
      setInterval(apply, 800);
    })();
    """

    /// For other web panels: only the page color, so their own themes stay intact.
    static let panelCSS = """
    :root { color-scheme: light dark; }
    @media (prefers-color-scheme: dark) { html, body { background: #000000 !important; } }
    @media (prefers-color-scheme: light) { html, body { background: #ffffff !important; } }
    """

    /// A script that adds a stylesheet to the page.
    static func styleScript(_ css: String) -> String {
        let escaped = css.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
        return """
        (function () {
          const style = document.createElement('style');
          style.id = 'homepad-theme';
          style.textContent = `\(escaped)`;
          (document.head || document.documentElement).appendChild(style);
        })();
        """
    }

    /// `#RRGGBB` for a SwiftUI color.
    static func hex(_ color: Color) -> String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let clamp = { (value: CGFloat) in Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", clamp(red), clamp(green), clamp(blue))
    }
}
