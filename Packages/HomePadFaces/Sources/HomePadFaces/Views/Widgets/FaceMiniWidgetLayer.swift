import HomePadCore
import HomePadUI
import SwiftUI
import UIKit

/// A face's mini widget, in the face's top margin at its leading side: one
/// line in a capsule that ends where the face's content starts
/// (`FaceWidgetSupport.miniWidgetFrame`), so the face never moves for it.
/// Always the smallest size on a face. It is on the glass the face's widgets
/// are on (`widgetGlass(in:)`), so it reads on bright and dark faces alike. Drawn by `HostedFace` with the face, so it drifts with the
/// face, pages with it, and shows in the editor and My Faces as on the wall.
///
/// It hugs what it shows and never grows past a gap before the Now Playing
/// pill's zone. Short of room, it shows less, as the glance does in the
/// header. On the wall a tap on one of its parts opens that part's app, as a
/// widget on the face does. At night it turns red with the face.
struct FaceMiniWidgetLayer: View {
    let placement: MiniWidgetPlacement
    /// Where it may be: its top leading corner, its height and the widest it may grow.
    let frame: CGRect
    /// True for the face on the wall. Previews take taps for themselves.
    var opensApps = false

    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry

    var body: some View {
        if let widget = registry.miniWidget(placement.widgetID) {
            widget.makeView(context(for: widget))
                .padding(.horizontal, Self.padding)
                .frame(height: frame.height)
                // The glass the face's widgets are on: dark with light text over a dark face, light
                // with dark text over a bright one, red at night.
                .widgetGlass(in: Capsule())
                // Offers the widget the room up to the pills, while the glass hugs what it shows.
                .frame(width: max(frame.width, 0), alignment: .leading)
                .nightModeAware()
                .offset(x: frame.minX, y: frame.minY)
                .accessibilityElement(children: .contain)
                .accessibilityLabel(widget.title)
                .transition(.opacity)
        }
    }

    private func context(for widget: MiniWidgetDescriptor) -> MiniWidgetContext {
        var open: (@MainActor (String) -> Void)?
        if opensApps {
            let events = services.events
            open = { events.post(.openApp(id: $0)) }
        }
        // An empty capsule would still show, so it keeps at least its first thing.
        return MiniWidgetContext(size: widget.shownSize(placement.size), surface: .glass, textSize: Self.textSize,
                                 keepsSomething: true, openApp: open)
    }

    /// Between the capsule's ends and what it shows.
    static let padding = Theme.Spacing.m

    /// The text size whose one line fits the capsule with `Theme.Spacing.s`
    /// above and below, measured from the system font's line height.
    static let textSize: CGFloat = {
        let lineHeight = UIFont.systemFont(ofSize: 100, weight: .semibold).lineHeight / 100
        return ((FaceWidgetSupport.miniWidgetHeight - Theme.Spacing.s * 2) / lineHeight).rounded(.down)
    }()
}
