import HomePadCore
import SwiftUI

/// Same on All HomePads, on Edit Widget under the preview. On, the widget's
/// settings are the same on every HomePad in the household. Off, each HomePad
/// keeps its own, such as each room's lights in Home Favorites, and the widget
/// still sits in the same place on all of them
/// (`WidgetSettings.isSameOnAllHomePads`). The switch itself is shared.
struct SameOnAllHomePadsSwitch: View {
    @Binding var settings: WidgetSettings

    /// Shown while this HomePad shares its setup with another one, so a
    /// HomePad on its own has no extra control, and while the switch is off,
    /// so a widget is never left off with no way back.
    static func isShown(for settings: WidgetSettings, homePadsSharingSetup: Int) -> Bool {
        homePadsSharingSetup > 0 || !settings.isSameOnAllHomePads
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Toggle("Same on All HomePads", isOn: isOn)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(minHeight: Theme.Size.tapTarget)
                .background(.groupedRow, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            Text("When off, each HomePad keeps its own settings for this widget, and changes made here stay on this HomePad. The widget still sits in the same place on every HomePad.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.m)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var isOn: Binding<Bool> {
        Binding(
            get: { settings.isSameOnAllHomePads },
            set: { settings.setSameOnAllHomePads($0) }
        )
    }
}
