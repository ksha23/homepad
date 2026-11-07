import AVKit
import CommsKit
import HomePadUI
import SwiftUI

/// One attachment in a bubble: a photo, a video with a play button, or a file chip.
struct AttachmentView: View {
    @Environment(CommsRuntime.self) private var runtime
    let attachment: CommsAttachment
    @State private var image: UIImage?
    @State private var failed = false
    @State private var playing = false
    @State private var openingPDF = false

    /// The picture: loaded by this view, or already in memory from before, so it is there on the first frame.
    private var loaded: UIImage? {
        image ?? runtime.store.attachments?.cachedImage(attachment.id)
    }

    var body: some View {
        Group {
            if attachment.mimeType.hasPrefix("image/") { photo }
            else if attachment.mimeType.hasPrefix("video/") { video }
            else if attachment.mimeType == "application/pdf" { pdf }
            else { file }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// Laid out at its final size from the start (`MediaFit`), so loading it never moves the thread.
    private var photo: some View {
        let size = MediaFit.size(of: attachment, in: MediaFit.photoBox, fallback: MediaFit.photoFallback)
        return ZStack {
            Rectangle().fill(.quaternary)
            if let image = loaded {
                Image(uiImage: image).resizable()
                    .aspectRatio(contentMode: attachment.width == nil ? .fit : .fill)
                    .accessibilityIdentifier("attachment-photo")
            } else if failed {
                Label("Not on your Mac yet", systemImage: "photo.badge.exclamationmark").font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView()
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .mediaZoomSource(id: attachment.id, cornerRadius: Theme.Radius.card)
        .task(id: attachment.id) {
            image = await runtime.store.attachments?.image(attachment.id)
            failed = image == nil
        }
    }

    private var video: some View {
        Button { playing = true } label: {
            placeholder(systemImage: "play.circle.fill", text: attachment.name).frame(width: 260, height: 160)
        }
        .buttonStyle(.plain)
        .fullScreenCover(isPresented: $playing) { VideoPlayerCover(attachmentID: attachment.id).coverHomeBar(colorScheme: .dark) }
    }

    /// First page as a preview with the file name under it. Tapping opens the whole PDF.
    private var pdf: some View {
        Button { openingPDF = true } label: {
            VStack(spacing: 0) {
                let page = MediaFit.size(of: attachment, in: MediaFit.pageBox, fallback: MediaFit.pageBox)
                ZStack {
                    Rectangle().fill(.quaternary)
                    if let image = loaded { Image(uiImage: image).resizable().scaledToFit() }
                    else if failed { Image(systemName: "doc.richtext").font(.largeTitle).foregroundStyle(.secondary) }
                    else { ProgressView() }
                }
                .frame(width: page.width, height: page.height)
                HStack(spacing: 6) {
                    Image(systemName: "doc.richtext.fill").foregroundStyle(.red)
                    Text(attachment.name).font(.footnote).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(width: page.width)
                .background(.regularMaterial)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pdf-preview")
        .task(id: attachment.id) {
            image = await runtime.store.attachments?.image(attachment.id)
            failed = image == nil
        }
        .fullScreenCover(isPresented: $openingPDF) {
            PDFViewerCover(attachmentID: attachment.id, name: attachment.name).coverHomeBar()
        }
    }

    private var file: some View {
        placeholder(systemImage: "doc.fill", text: attachment.name).frame(width: 220, height: 64)
    }

    private func placeholder(systemImage: String, text: String?) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage).font(.largeTitle)
            if let text { Text(text).font(.caption).lineLimit(1) }
        }
        .foregroundStyle(.secondary)
        .frame(minWidth: 120, minHeight: 90)
        .padding()
        .background(.quaternary)
    }
}

private struct VideoPlayerCover: View {
    @Environment(CommsRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    let attachmentID: String
    @State private var player: AVPlayer?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            if let player { VideoPlayer(player: player).ignoresSafeArea() }
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.largeTitle).padding() }
                .foregroundStyle(.white)
        }
        .task {
            guard let stream = runtime.store.attachments?.stream(attachmentID) else { return }
            let asset = AVURLAsset(url: stream.url, options: ["AVURLAssetHTTPHeaderFieldsKey": stream.headers])
            let player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}
