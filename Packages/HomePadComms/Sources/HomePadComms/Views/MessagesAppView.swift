import CommsKit
import HomePadCore
import HomePadUI
import SwiftUI

/// The Messages app: conversation list on the left, the open thread on the right.
struct MessagesAppView: View {
    @Environment(CommsRuntime.self) private var runtime
    @AppState("messages.selected", default: String?.none, scope: .member, storage: .session) private var selected: String?

    var body: some View {
        let store = runtime.store
        NavigationSplitView {
            Group {
                if !store.conversations.isEmpty {
                    ConversationList(selection: $selected)
                        .safeAreaInset(edge: .top, spacing: 0) { if store.isReconnecting { ReconnectingStrip(failed: store.phase != .connecting) } }
                } else {
                    switch store.phase {
                    case .connected: ContentUnavailableView("No conversations", systemImage: "message")
                    case .connecting: ProgressView("Connecting to your Mac")
                    case .notConfigured: ContentUnavailableView("Set up Messages", systemImage: "macbook.and.iphone", description: Text("Add your Mac hub in Settings > Messages."))
                    case .failed(let reason): ContentUnavailableView("Cannot reach your Mac", systemImage: "wifi.exclamationmark", description: Text(reason))
                    case .locked: ContentUnavailableView("Locked", systemImage: "lock.fill", description: Text("Pick yourself in People, or turn off face recognition in Settings > Messages."))
                    }
                }
            }
            .navigationTitle("Messages")
        } detail: {
            if let selected, let conversation = store.conversations.first(where: { $0.id == selected }) {
                ThreadView(conversation: conversation).id(conversation.id)
            } else {
                ContentUnavailableView("No conversation", systemImage: "message")
            }
        }
        // The app's own color is green, but Messages on iPadOS highlights in blue.
        .tint(.blue)
        // Opening Messages answers the notification, and the open thread is already in view.
        .onAppear {
            #if DEBUG
            if let id = CommsDemo.openConversationID { selected = id }
            #endif
            store.dismissBanner()
            store.openConversationID = selected
        }
        .onChange(of: selected) { _, id in store.openConversationID = id }
        .onDisappear { store.openConversationID = nil }
    }
}

private struct ConversationList: View {
    @Environment(CommsRuntime.self) private var runtime
    @Binding var selection: String?
    @State private var query = ""

    private var shown: [CommsConversation] {
        let all = runtime.store.conversations
        guard !query.isEmpty else { return all }
        return all.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.lastMessagePreview.localizedCaseInsensitiveContains(query) }
    }

    // The rows draw their own highlight with the sidebar row style, as Settings and Music do. A
    // `List` selection drew the system's platter and focus ring, whose corners are not on HomePad's scale.
    var body: some View {
        List(shown) { conversation in
            let isSelected = conversation.id == selection
            Button {
                selection = conversation.id
            } label: {
                ConversationRow(conversation: conversation)
            }
            .buttonStyle(.sidebarRow(isSelected: isSelected, tint: .blue))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            // `sidebarRowGap` between rows. The sidebar list already keeps rows `Spacing.m` from its
            // sides, so the highlight lines up with the search field above it.
            .listRowInsets(EdgeInsets(top: Theme.Spacing.sidebarRowGap / 2, leading: 0,
                                      bottom: Theme.Spacing.sidebarRowGap / 2, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.sidebar)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
    }
}

/// A thin strip over the list while the Mac is not answering. The messages stay readable.
private struct ReconnectingStrip: View {
    let failed: Bool

    var body: some View {
        HStack(spacing: 8) {
            if failed { Image(systemName: "wifi.exclamationmark") } else { ProgressView().controlSize(.small) }
            Text(failed ? "Offline. Showing saved messages." : "Reconnecting to your Mac")
                .font(.footnote.weight(.medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .accessibilityIdentifier("reconnecting-strip")
    }
}
