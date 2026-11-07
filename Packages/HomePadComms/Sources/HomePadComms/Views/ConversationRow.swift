import CommsKit
import HomePadUI
import SwiftUI

/// A row in the conversation list: avatar, name, preview, time and unread dot.
struct ConversationRow: View {
    let conversation: CommsConversation

    var body: some View {
        HStack(spacing: 10) {
            Avatar(title: conversation.title, isGroup: conversation.isGroup, handle: conversation.isGroup ? nil : conversation.participants.first)
                .overlay(alignment: .leading) {
                    if conversation.unreadCount > 0 {
                        Circle().fill(.blue).frame(width: Self.unreadDot, height: Self.unreadDot).offset(x: Self.unreadDotOffset)
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(conversation.title).font(.headline).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(Self.label(for: conversation.lastMessageDate)).font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    Text(conversation.lastMessagePreview.isEmpty ? "Attachment" : conversation.lastMessagePreview)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    Spacer(minLength: 8)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private static let unreadDot: CGFloat = 10
    /// Centers the unread dot in the row's leading padding, inside its highlight.
    private static let unreadDotOffset: CGFloat = -(Theme.Spacing.m + unreadDot) / 2

    private static func label(for date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
