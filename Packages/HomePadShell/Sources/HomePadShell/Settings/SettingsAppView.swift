import HomePadCore
import HomePadUI
import SwiftUI

/// Settings pane IDs the shell registers.
enum ShellPaneID {
    static let kiosk = "kiosk"
    static let people = "people"
    static let about = "about"
    static let background = "background"
}

/// The Settings app: every module's pane in a sidebar, iOS Settings style.
/// Admin-only panes ask for Face ID or the passcode (system sheet) first,
/// unless a recognized admin is at the screen.
///
/// It reopens on the pane it was left on. A pane asked for by name (a
/// `homepad://settings/<pane>` link, onboarding, a launch argument) wins. A
/// restored admin pane waits behind its Unlock button rather than asking for
/// Face ID the moment Settings opens, unless a recognized admin is here.
///
/// The standard header row (title and close button) runs across the top like
/// every app's, clear of the Now Playing pill, and the two columns sit under
/// it on the grouped page color (`Color.groupedBackground`): black in Dark,
/// and in Light the light gray that sets off the forms' white rows, as in
/// iPadOS Settings. Each pane's title heads its column. Panes get the spacing
/// in `SettingsPaneLayout`.
struct SettingsAppView: View {
    @Environment(ModuleRegistry.self) private var registry
    @Environment(Household.self) private var household
    @Environment(ShellNavigator.self) private var navigator: ShellNavigator?
    @AppState(ShellAppState.settingsPane) private var selection
    @State private var unlockedPaneIDs: Set<String> = []
    @State private var authNote: String?
    @State private var hasNoPasscode = false
    @Environment(\.colorScheme) private var colorScheme
    /// False until the pane's UIKit navigation has been laid out. The page
    /// color fades in with the app at once, and everything on it waits and
    /// then fades in together. UIKit builds the pane a moment after the rest,
    /// so in Light its gray arrived after the header and sidebar.
    @State private var isContentReady = false

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            AppHeader("Settings")
                .padding([.horizontal, .top], Theme.Spacing.l)
            columns
        }
        .opacity(isContentReady ? 1 : 0)
        .task {
            // One frame for UIKit to lay out the pane, then one fade for all of it.
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(Theme.Motion.standard) { isContentReady = true }
        }
        .background(Color.groupedBackground.ignoresSafeArea())
        // The icon's gray would make the panes' prominent actions (Continue,
        // Unlock) look like plain glass, so Settings keeps HomePad's accent.
        .appAccent(.accentColor)
        .onAppear(perform: openPane)
        .onChange(of: selection) { _, id in
            guard let id, let pane = registry.settingsPanes.first(where: { $0.id == id }),
                  pane.adminOnly, !unlockedPaneIDs.contains(id) else { return }
            Task { await unlock(pane) }
        }
    }

    /// The sections on the left and the chosen pane on the right. Drawn as two
    /// plain columns rather than a NavigationSplitView: the system split view
    /// put a gray glass panel under the black header, starting abruptly at the
    /// first row, and its columns did not fade in with the rest of the app.
    private var columns: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                sidebar
                    .frame(width: SettingsSidebar.width(in: proxy.size.width))
                Rectangle()
                    .fill(.primary.opacity(0.08))
                    .frame(width: 1)
                    .accessibilityHidden(true)
                detail
                    // In Dark the forms sit on the page's black. In Light each form
                    // draws its own light gray, also on pages a pane pushes, which
                    // the navigation stack would otherwise draw white under white rows.
                    .scrollContentBackground(colorScheme == .light ? .automatic : .hidden)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// The rows are walk-up targets, so in landscape they do not all fit and
    /// the sidebar scrolls. It brings the chosen row into view when Settings
    /// opens and when a pane is asked for by name.
    private var sidebar: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: Theme.Spacing.sidebarRowGap) {
                    ForEach(registry.settingsPanes) { pane in
                        SettingsSidebarRow(pane: pane, isSelected: shownPane?.id == pane.id, isLocked: isLocked(pane)) {
                            selection = pane.id
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.s)
                .padding(.vertical, Theme.Spacing.s)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                if let id = shownPane?.id {
                    scroller.scrollTo(id)
                }
            }
            .onChange(of: selection) {
                guard let id = shownPane?.id else { return }
                withAnimation(Theme.Motion.standard) { scroller.scrollTo(id) }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let pane = shownPane {
            let id = pane.id
            if !pane.adminOnly || unlockedPaneIDs.contains(id) {
                NavigationStack {
                    pane.makeView()
                        .containerBackground(Color.groupedBackground, for: .navigation)
                        .settingsPaneMargins()
                        .navigationTitle(pane.title)
                        .toolbarTitleDisplayMode(.inlineLarge)
                        .safeAreaInset(edge: .top) {
                            if pane.adminOnly && hasNoPasscode {
                                StatusBanner("This iPad has no passcode, so admin settings are not protected",
                                             systemImage: "exclamationmark.shield", tint: .orange)
                                    .padding(.vertical, Theme.Spacing.s)
                            }
                        }
                }
                .settingsPaneSpacing()
                .id(id)
            } else {
                EmptyStateView(
                    "Admins Only", message: authNote ?? "\(pane.title) can only be changed by an admin.",
                    systemImage: "lock.shield", actionTitle: "Unlock"
                ) {
                    Task { await unlock(pane) }
                }
            }
        } else {
            EmptyStateView("Settings", message: "Choose a section on the left.", systemImage: "gearshape")
        }
    }

    /// The chosen pane, or the first when none was chosen or it is gone.
    private var shownPane: SettingsPaneDescriptor? {
        registry.settingsPanes.first { $0.id == selection } ?? registry.settingsPanes.first
    }

    /// A requested pane replaces the restored one and asks to unlock as a tap
    /// would. A restored admin pane unlocks only when that needs no Face ID.
    private func openPane() {
        if let requested = navigator?.pendingSettingsPane {
            navigator?.pendingSettingsPane = nil
            if requested != selection {
                // A new selection asks to unlock through `onChange`.
                selection = requested
                return
            }
        } else if !AdminAuthorizer.canSkipVerification(household) {
            return
        }
        guard let pane = shownPane, pane.adminOnly, !unlockedPaneIDs.contains(pane.id) else { return }
        Task { await unlock(pane) }
    }

    private func isLocked(_ pane: SettingsPaneDescriptor) -> Bool {
        pane.adminOnly && !unlockedPaneIDs.contains(pane.id) && !AdminAuthorizer.canSkipVerification(household)
    }

    private func unlock(_ pane: SettingsPaneDescriptor) async {
        let outcome = await AdminAuthorizer.authorize(household: household, reason: "Open \(pane.title) settings")
        if outcome.isAllowed {
            unlockedPaneIDs.insert(pane.id)
            authNote = nil
            hasNoPasscode = outcome == .allowedWithoutPasscode
        } else if case .denied(let reason) = outcome {
            authNote = reason
        }
    }
}

/// Sizes for the Settings sidebar. Its rows take HomePadUI's sidebar row
/// style: `Theme.Size.tapTarget` tall and `Theme.Spacing.sidebarRowGap` apart.
enum SettingsSidebar {
    /// The narrowest the sidebar gets, in portrait, where the panes need the room.
    static let minWidth: CGFloat = 300
    /// The widest it gets, on a 13-inch iPad in landscape.
    static let maxWidth: CGFloat = 400
    /// The share of the Settings columns' width the sidebar takes between those.
    static let widthShare: CGFloat = 0.32
    /// A section's icon, sized for a walk-up row and its Title 3 name.
    static let iconSize: CGFloat = 36

    /// The sidebar's width for columns this wide: about 360 points on an
    /// 11-inch iPad in landscape, 400 on a 13-inch, and 300 in portrait.
    static func width(in columnsWidth: CGFloat) -> CGFloat {
        let share = (columnsWidth * widthShare).rounded()
        return min(max(share, minWidth), maxWidth)
    }
}

/// One section in the Settings sidebar: its icon and title, a lock while it
/// needs an admin, and a quiet highlight when it is the one showing.
struct SettingsSidebarRow: View {
    let pane: SettingsPaneDescriptor
    let isSelected: Bool
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                SettingsIcon(systemImage: pane.systemImage, tint: pane.tint, size: SettingsSidebar.iconSize)
                Text(pane.title)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if isLocked {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                }
            }
            .font(.title3)
        }
        .buttonStyle(.sidebarRow(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isLocked ? "Locked" : "")
    }
}
