import CommsKit
import SwiftUI

/// Pick a conversation and send the given attachments into it.
struct ForwardSheet: View {
    @Environment(CommsRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    let attachments: [CommsAttachment]
    @State private var query = ""
    @State private var sendingTo: String?
    @State private var failure: String?

    private var matches: [CommsConversation] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return runtime.store.conversations }
        return runtime.store.conversations.filter {
            $0.title.lowercased().contains(needle) || $0.participants.contains { $0.lowercased().contains(needle) }
        }
    }

    var body: some View {
        NavigationStack {
            List(matches) { conversation in
                Button { send(to: conversation) } label: {
                    ConversationRow(conversation: conversation)
                        .overlay(alignment: .trailing) { if sendingTo == conversation.id { ProgressView() } }
                }
                .buttonStyle(.plain)
                .disabled(sendingTo != nil)
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search conversations")
            .navigationTitle("Send to")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("Could not send", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private func send(to conversation: CommsConversation) {
        sendingTo = conversation.id
        Task {
            do {
                for attachment in attachments { try await runtime.store.forward(attachment, to: conversation.id) }
                dismiss()
            } catch {
                failure = error.localizedDescription
                sendingTo = nil
            }
        }
    }
}
