import HomePadUI
import SwiftUI

/// Places Find My's glass panel over the map: a column on the leading side when
/// the screen is wide, the lower part when it is tall. It measures where the
/// panel and the header leave the map free, so the map can frame its pins there
/// (`FindMyLayoutFrames.mapInsets`) instead of under the panel.
struct FindMyPanelLayout<Panel: View>: View {
    @Binding var measured: FindMyLayoutFrames
    @ViewBuilder let panel: Panel

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width > geometry.size.height
            panel
                .frame(width: isWide ? Self.panelWidth(for: geometry.size.width) : nil,
                       height: isWide ? nil : geometry.size.height * 0.46)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FindMyLayoutFrames.space)) } action: { measured.panel = $0 }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isWide ? .topLeading : .bottom)
                .onChange(of: isWide, initial: true) { measured.isWide = isWide }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(FindMyLayoutFrames.space)) } action: { measured.content = $0 }
    }

    /// A little over a third of the screen, like the sidebar in Apple's Find
    /// My, wide enough that a device's name and where it is fit at the walk-up
    /// sizes on the 11-inch.
    static func panelWidth(for width: CGFloat) -> CGFloat {
        min(480, max(360, width * 0.38))
    }
}

/// Where Find My's map, content area and panel are, measured after layout
/// (see `FindMyPanelLayout`) in the screen's own coordinate space. Global
/// coordinates would not do: forced landscape rotates the whole app.
struct FindMyLayoutFrames: Equatable {
    /// The coordinate space the app view names for these frames.
    static let space = "findmy.screen"

    /// The whole map, which reaches the screen's edges.
    var map: CGRect = .zero
    /// The screen's content area under the header.
    var content: CGRect = .zero
    /// The panel itself.
    var panel: CGRect = .zero
    var isWide = true

    /// The parts of the map the header, the margins and the panel cover.
    var mapInsets: EdgeInsets {
        guard map.width > 0, content.width > 0 else { return EdgeInsets() }
        var insets = EdgeInsets(
            top: content.minY - map.minY,
            leading: content.minX - map.minX,
            bottom: map.maxY - content.maxY,
            trailing: map.maxX - content.maxX
        )
        if isWide {
            insets.leading = panel.maxX - map.minX + Theme.Spacing.l
        } else {
            insets.bottom = map.maxY - panel.minY + Theme.Spacing.l
        }
        return insets
    }
}
