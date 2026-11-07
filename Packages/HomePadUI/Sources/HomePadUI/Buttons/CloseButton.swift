import SwiftUI

/// The standard round glass close button used by `AppScreen`, the shell,
/// sheets and full-screen overlays. It is a `GlassIconButton` with an xmark
/// at `Theme.Size.toolbarItem` everywhere, the size of every header item, so
/// it lines up with a header's toolbar and looks the same on every screen.
///
///     CloseButton { dismiss() }
public struct CloseButton: View {
    private let label: String
    private let action: () -> Void

    /// - Parameters:
    ///   - label: What VoiceOver reads. "Close" by default.
    ///   - action: Called on tap.
    public init(_ label: String = "Close", action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    public var body: some View {
        GlassIconButton("xmark", label: label, size: Theme.Size.toolbarItem, action: action)
    }
}
