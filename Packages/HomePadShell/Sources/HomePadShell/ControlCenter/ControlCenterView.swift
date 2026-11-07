import HomePadCore
import HomePadUI
import SwiftUI

/// Control Center, pulled down from the top-right corner: date and time, the
/// profile button, and the household's tiles (built-in and from modules).
/// Edit mode adds, removes and reorders tiles, like iOS 18.
struct ControlCenterView: View {
    @Environment(ModuleRegistry.self) private var registry
    @Environment(SettingsStore.self) private var settings
    @Environment(Household.self) private var household
    @Environment(ShellNavigator.self) private var navigator
    @State private var showsGallery = false
    /// The scroll view's height, so its content reaches the bottom and a tap
    /// below the last tile lands on it.
    @State private var scrollHeight: CGFloat = 0
    @State private var isReordering = false

    /// Room the header (about 88 points at the default text size), the panel's
    /// padding and the grid's inset take from the grid.
    private static let chromeHeight: CGFloat = 88 + Theme.Spacing.l * 2 + Theme.Spacing.m + Theme.Spacing.s * 2

    var body: some View {
        let store = ControlCenterStore(settings: settings, registry: registry)
        let isEditing = navigator.isEditingControlCenter
        GeometryReader { proxy in
            let room = CGSize(
                width: proxy.size.width - Theme.Spacing.l * 2,
                height: proxy.size.height - Self.chromeHeight - (isEditing ? Theme.Size.minTapTarget + Theme.Spacing.l : 0)
            )
            let columns = ControlCenterGrid.columns(for: store.visibleIDs.map(store.span(for:)), fitting: room)
            panel(store: store, isEditing: isEditing, columns: columns)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                // Dark in either appearance, as on iPadOS. Only the panel: the
                // Add a Control sheet below follows the app's appearance.
                .environment(\.colorScheme, .dark)
        }
        .sheet(isPresented: $showsGallery) {
            ControlGallerySheet(store: store)
        }
        // However it closes (a tap outside, a swipe, another panel), edit mode
        // ends with it rather than waiting for Done.
        .onDisappear { navigator.isEditingControlCenter = false }
    }

    private func panel(store: ControlCenterStore, isEditing: Bool, columns: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            header(isEditing: isEditing)
            ScrollView {
                ControlCenterGrid(store: store, isEditing: isEditing, columns: columns, isReordering: $isReordering)
                    .padding(Theme.Spacing.s)
                    .frame(maxWidth: .infinity, minHeight: scrollHeight, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: tapOutsideTiles)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDisabled(isReordering)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scrollHeight = $0 }
            if isEditing {
                Button {
                    showsGallery = true
                } label: {
                    Label("Add a Control", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.Size.minTapTarget)
                }
                .buttonStyle(.glass)
            }
        }
        .frame(width: ControlCenterGrid.width(columns: columns) + Theme.Spacing.s * 2)
        // The header's empty space too. The scroll view swallowed the backdrop's
        // tap, so only the strip left of the panel used to close it.
        .background(Color.clear.contentShape(Rectangle()).onTapGesture(perform: tapOutsideTiles))
        // Inside the shell's screen margin, so the header lines up with the Home Screen's.
        .padding(.top, Theme.Spacing.l)
        .padding(.trailing, Theme.Spacing.l)
        .padding(.bottom, Theme.Spacing.m)
        .nightModeAware()
        .animation(Theme.Motion.settle, value: columns)
    }

    /// A tap where no tile is: ends edit mode first, as on iPadOS, otherwise
    /// closes Control Center.
    private func tapOutsideTiles() {
        if navigator.isEditingControlCenter {
            navigator.isEditingControlCenter = false
        } else {
            navigator.panel = nil
        }
    }

    private func header(isEditing: Bool) -> some View {
        HStack(alignment: .top) {
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.headline)
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(context.date, format: .dateTime.hour().minute())
                        .font(.display(52))
                        .contentTransition(.numericText())
                }
                // The minute rolls over, once a minute.
                .animation(Theme.Motion.standard, value: context.date)
            }
            Spacer()
            Button {
                navigator.isEditingControlCenter.toggle()
            } label: {
                if isEditing {
                    Text("Done").font(.headline).padding(.horizontal, Theme.Spacing.s)
                } else {
                    Image(systemName: "pencil").font(.headline)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .accessibilityLabel(isEditing ? "Done" : "Edit Control Center")
            Button {
                navigator.toggle(.people)
            } label: {
                AvatarView(member: household.isPersonalContentUnlocked ? household.activeMember : nil, size: 52)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("People, \(household.activeMember?.name ?? "Guest")")
        }
        .padding(.horizontal, Theme.Spacing.s)
    }
}
