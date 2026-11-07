#if os(iOS)
import SwiftUI
import UIKit

public extension View {
    /// The one way HomePad presents Apple's system controllers (EventKitUI,
    /// PhotosUI) inside a `.sheet`: edge to edge, as a
    /// form sheet rather than a full-screen jump. The controller follows the
    /// app's appearance, which the sheet takes from the window, and is dark at
    /// night like everything else.
    ///
    ///     .sheet(isPresented: $isAdding) { EventEditorSheet(...).systemSheetStyle() }
    func systemSheetStyle() -> some View {
        ignoresSafeArea()
            .presentationSizing(.form)
    }
}

public extension UIViewController {
    /// Used to force the dark appearance on a system controller. System
    /// controllers now follow the app's appearance from the window they are
    /// presented in, so this does nothing.
    @available(*, deprecated, message: "System controllers follow the app's appearance. Remove the call.")
    func homePadDarkAppearance() -> Self {
        self
    }
}
#endif
