import CommsKit
import PhotosUI
import SwiftUI

/// One conversation: messages (newest at the bottom) and the composer.
struct ThreadView: View {
    @Environment(CommsRuntime.self) private var runtime
    let conversation: CommsConversation
    @State private var draft = ""
    @State private var uploads = PhotoUploads()
    /// True while the thread follows its newest message: from the moment it opens until the person
    /// scrolls up, and again once they scroll back to the bottom. While it follows, anything that
    /// changes the thread's height (a message arriving, the composer growing) keeps it at the bottom.
    @State private var followsNewest = true
    /// False until the thread is laid out with its header and composer around it. Its very first layout
    /// comes before they are attached, with the messages in the wrong place, and showed as a one-frame jolt.
    @State private var isLaidOut = false

    private static let gap: TimeInterval = 30 * 60

    var body: some View {
        let messages = runtime.store.threads[conversation.id] ?? []
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        if index == 0 || message.date.timeIntervalSince(messages[index - 1].date) > Self.gap {
                            TimeDivider(date: message.date)
                        }
                        Bubble(message: message, showSender: conversation.isGroup)
                            .id(message.id)
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier(index == messages.count - 1 ? "newest-message" : "message")
                    }
                    // The very end of the thread, below the last message and its reactions.
                    Color.clear.frame(height: 1).id(Self.end)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .opacity(isLaidOut ? 1 : 0)
            // Opens at the newest message, and a short conversation sits at the bottom like Messages.
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            // Tapping the conversation puts the keyboard away. It does not block taps on photos or links.
            .simultaneousGesture(TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            })
            // A drag by the person decides whether the thread keeps following: it stops when they
            // take hold, and starts again if they let go at the bottom.
            .onScrollPhaseChange { _, phase, context in
                switch phase {
                case .tracking, .interacting: followsNewest = false
                case .idle: followsNewest = Self.isAtEnd(context.geometry)
                default: break
                }
            }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentSize.height + $0.contentInsets.bottom }) { _, _ in
                if followsNewest { proxy.scrollTo(Self.end, anchor: .bottom) }
            }
            // The composer's inset arriving is the sign the thread has its final frame.
            .onScrollGeometryChange(for: Bool.self, of: { $0.contentInsets.bottom > 0 }) { _, hasComposer in
                guard hasComposer, !isLaidOut else { return }
                proxy.scrollTo(Self.end, anchor: .bottom)
                isLaidOut = true
            }
            .onChange(of: messages.last?.id) { _, _ in
                guard followsNewest else { return }
                withAnimation(.snappy) { proxy.scrollTo(Self.end, anchor: .bottom) }
            }
            // A safety net: if the thread was laid out with its composer from the very first pass, the change
            // above never comes, and the thread shows after a moment.
            .task(id: conversation.id) {
                try? await Task.sleep(for: .milliseconds(250))
                if !isLaidOut { isLaidOut = true }
            }
            // The unread dot clears the moment the thread opens. Once the thread has loaded, the person has
            // seen through its newest message, and the Mac is asked to mark the chat read too.
            .task(id: conversation.id) {
                runtime.store.markSeen(conversation.id)
                await runtime.store.loadThread(conversation.id)
                await runtime.store.markRead(conversation.id)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                if uploads.sending > 0 {
                    HStack(spacing: 8) { ProgressView(); Text("Sending \(uploads.sending) photo\(uploads.sending == 1 ? "" : "s")...") }
                        .font(.footnote).foregroundStyle(.secondary).padding(.vertical, 6)
                }
                Composer(text: $draft, onSend: send, onPick: sendPicked)
            }
        }
        .alert("Could not send", isPresented: Binding(get: { uploads.failure != nil }, set: { if !$0 { uploads.failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(uploads.failure ?? "")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Avatar(title: conversation.title, isGroup: conversation.isGroup, size: 36, handle: conversation.isGroup ? nil : conversation.participants.first)
                    Text(conversation.title).font(.caption2.weight(.medium)).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(conversation.title)
            }
        }
    }

    /// The id of the empty row at the end of the thread.
    private static let end = "thread-end"

    /// Whether the person is looking at the end of the thread, within a few points.
    private static func isAtEnd(_ geometry: ScrollGeometry) -> Bool {
        geometry.visibleRect.maxY >= geometry.contentSize.height - 8
    }

    private func sendPicked(_ items: [PhotosPickerItem]) {
        Task { await uploads.send(items, to: conversation.id, store: runtime.store) }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { if !(await runtime.store.send(text, to: conversation.id)) { draft = text } }
    }
}
