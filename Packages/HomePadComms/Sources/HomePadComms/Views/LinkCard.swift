import CommsKit
import HomePadUI
import SwiftUI

/// A rich link as one card: preview picture, title and site. Tapping opens it.
struct LinkCard: View {
    @Environment(CommsRuntime.self) private var runtime
    @Environment(\.openURL) private var openURL
    let link: CommsLink
    @State private var image: UIImage?

    private var host: String {
        URL(string: link.url)?.host()?.replacingOccurrences(of: "www.", with: "") ?? link.url
    }

    var body: some View {
        Button {
            if let url = URL(string: link.url) { openURL(url) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // The picture's space is there from the start when the link has one, so the card
                // keeps its height when the picture arrives and the thread does not move.
                if link.imageAttachmentID != nil {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        if let image = image ?? link.imageAttachmentID.flatMap({ runtime.store.attachments?.cachedImage($0) }) {
                            Image(uiImage: image).resizable().scaledToFill()
                        }
                    }
                    .frame(width: 280, height: 160)
                    .clipped()
                }
                VStack(alignment: .leading, spacing: 2) {
                    if let title = link.title, !title.isEmpty {
                        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Text(host).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .frame(width: 280)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("link-card")
        .task(id: link.imageAttachmentID) {
            guard let id = link.imageAttachmentID else { return }
            image = await runtime.store.attachments?.image(id)
        }
    }
}
