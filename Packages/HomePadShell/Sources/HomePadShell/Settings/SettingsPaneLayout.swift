import HomePadUI
import SwiftUI

/// Room inside Settings' detail column, so a pane breathes like every other
/// HomePad screen while keeping the system Form and List.
///
/// - Rows are at least `Theme.Size.tapTarget` tall, easy to tap from arm's length.
/// - Sections sit `Theme.Spacing.xl` apart.
/// - Cards sit about `Theme.Spacing.l` from the sidebar and about 64 points from
///   the screen's right edge, in line with the shell's close button.
///
/// The sidebar's rows are as tall as the panes' rows (`SettingsSidebar`).
enum SettingsPaneLayout {
    /// Extra safe area at the sides of a pane. The system Form already insets
    /// its sections 16 points from the safe area in a narrow column and 20 in a
    /// wide one, so this brings the inset to about `Theme.Spacing.l`.
    static let sideRoom = Theme.Spacing.xs
}

extension View {
    /// Row height and section spacing for a pane's navigation stack, so screens
    /// pushed inside the pane match it. Sheets a pane presents inherit them too.
    func settingsPaneSpacing() -> some View {
        listSectionSpacing(Theme.Spacing.xl)
            .environment(\.defaultMinListRowHeight, Theme.Size.tapTarget)
    }

    /// Side room for a pane's root screen. It is safe area, not `contentMargins`:
    /// content margins pass down to the sheets a pane presents and would squeeze
    /// their forms by the sidebar's width.
    func settingsPaneMargins() -> some View {
        safeAreaPadding(.horizontal, SettingsPaneLayout.sideRoom)
    }
}
