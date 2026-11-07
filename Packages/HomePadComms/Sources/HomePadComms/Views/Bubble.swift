import CommsKit
import HomePadUI
import SwiftUI

/// One message: attachments above, then the text in a bubble.
struct Bubble: View {
    let message: CommsMessage
    let showSender: Bool

    var body: some View {
        VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 3) {
            if showSender, !message.isFromMe, let sender = message.senderName ?? message.sender {
                Text(sender).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 12)
            }
            ForEach(AttachmentGroup.make(message.attachments)) { group in
                switch group {
                case .photos(let photos):
                    MediaBlock(attachments: photos, opensViewer: true, isFromMe: message.isFromMe) {
                        if photos.count > 1 { AttachmentStack(photos: photos) } else { AttachmentView(attachment: photos[0]) }
                    }
                case .video(let video):
                    MediaBlock(attachments: [video], opensViewer: false, isFromMe: message.isFromMe) { AttachmentView(attachment: video) }
                case .file(let file):
                    AttachmentView(attachment: file)
                }
            }
            if let link = message.link { LinkCard(link: link).reactionOverlay(message, when: !hasTextBubble) }
            if !message.text.isEmpty, !isJustTheLink {
                Text(message.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .foregroundStyle(message.isFromMe ? Color.white : Color.primary)
                    .background(message.isFromMe ? Color.blue : Color(.systemGray5), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .reactionOverlay(message)
            }
        }
        .reactionOverlay(message, when: !hasTextBubble && message.link == nil)
        .padding(.top, message.reactions.isEmpty ? 0 : 10)
        .frame(maxWidth: .infinity, alignment: message.isFromMe ? .trailing : .leading)
    }
}

extension Bubble {
    fileprivate var hasTextBubble: Bool { !message.text.isEmpty && !isJustTheLink }

    /// A link message's text is usually only the URL, which the card already shows.
    fileprivate var isJustTheLink: Bool {
        guard message.link != nil else { return false }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.contains(" ") && !text.contains("\n") && (text.hasPrefix("http://") || text.hasPrefix("https://"))
    }
}

/// A centered time label between messages that are far apart in time.
struct TimeDivider: View {
    let date: Date

    var body: some View {
        Text(date.formatted(date: .abbreviated, time: .shortened))
            .font(.caption).foregroundStyle(.secondary).padding(.top, 10)
    }
}
