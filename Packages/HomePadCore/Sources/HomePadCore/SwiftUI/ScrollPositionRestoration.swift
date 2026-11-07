import SwiftUI

public extension View {
    /// Scrolls back to the item that was at the top when the view last closed,
    /// and saves the top item once scrolling stops, never while it moves. Bind
    /// it to an `@AppState` value, usually with `storage: .session`. Put
    /// `.scrollTargetLayout()` on the lazy stack or grid inside the scroll view,
    /// whose items need the same IDs as `ID` (a `ForEach` over identifiable
    /// items gives them).
    ///
    ///     ScrollView { LazyVGrid(...) { ForEach(photos) { ... } }.scrollTargetLayout() }
    ///         .restoresScrollPosition($topPhotoID)
    func restoresScrollPosition<ID: Hashable>(_ saved: Binding<ID?>) -> some View {
        modifier(ScrollPositionRestoration(saved: saved))
    }
}

/// Keeps the top item in local state while scrolling and copies it to the
/// saved value when the scroll view comes to rest.
private struct ScrollPositionRestoration<ID: Hashable>: ViewModifier {
    @Binding var saved: ID?
    @State private var top: ID?
    @State private var hasRestored = false

    func body(content: Content) -> some View {
        content
            .scrollPosition(id: $top, anchor: .top)
            .onAppear {
                guard !hasRestored else { return }
                hasRestored = true
                top = saved
            }
            .onScrollPhaseChange { _, phase in
                if phase == .idle, top != saved { saved = top }
            }
    }
}
