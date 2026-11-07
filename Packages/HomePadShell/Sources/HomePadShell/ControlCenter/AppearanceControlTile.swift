import HomePadCore
import HomePadUI
import SwiftUI

/// Control Center button that switches between dark mode, light mode, and matching the iPad system appearance.
/// Tapping cycles between Dark -> Light -> System -> Dark, with a context menu to choose directly.
struct AppearanceControlTile: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var choice: AppearanceChoice {
        settings[ShellSettings.appearance]
    }

    var body: some View {
        Button {
            settings[ShellSettings.appearance] = choice.next
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: choice.systemImage)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: Theme.Size.roundControl, height: Theme.Size.roundControl)
                    .background {
                        circleBackground
                    }
                    .glassEffect(isLit ? .identity : .regular.interactive(), in: Circle())
                    .editPulseBorder(in: Circle())
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce.down, options: .nonRepeating, value: reduceMotion ? "" : choice.rawValue)
                Text(choice.shortTitle)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Appearance")
        .accessibilityValue(choice.title)
        .accessibilityHint("Switches between dark mode, light mode, and match iPad")
        .sensoryFeedback(.selection, trigger: choice)
        .contextMenu {
            Button {
                settings[ShellSettings.appearance] = .dark
            } label: {
                Label("Dark", systemImage: "circle.lefthalf.filled")
            }
            Button {
                settings[ShellSettings.appearance] = .light
            } label: {
                Label("Light", systemImage: "sun.max.fill")
            }
            Button {
                settings[ShellSettings.appearance] = .automatic
            } label: {
                Label("Match iPad (Follow System)", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }

    private var isLit: Bool {
        choice != .dark
    }

    @ViewBuilder
    private var circleBackground: some View {
        switch choice {
        case .dark:
            EmptyView()
        case .light:
            Circle().fill(Color.white)
        case .automatic:
            Circle().fill(Color.blue)
        }
    }

    private var iconColor: Color {
        switch choice {
        case .dark:
            .primary
        case .light:
            .black
        case .automatic:
            .white
        }
    }
}
