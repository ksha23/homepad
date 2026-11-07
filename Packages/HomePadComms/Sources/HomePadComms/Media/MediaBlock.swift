import CommsKit
import HomePadUI
import SwiftUI

/// One photo, stack or video with what goes around it: a download button beside received
/// media that is not in Photos yet, a long-press menu, the full-screen viewer on tap, and the send-to sheet.
struct MediaBlock<Content: View>: View {
    @Environment(CommsRuntime.self) private var runtime
    let attachments: [CommsAttachment]
    /// True for photos, which open the viewer on tap. A video plays through its own button.
    let opensViewer: Bool
    /// Photos I sent are already on this iPad's side of things, so they get no download button.
    let isFromMe: Bool
    @ViewBuilder let content: Content

    @State private var saver = MediaSaver()
    @State private var viewing = false
    @State private var forwarding = false
    @Namespace private var zoom

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            content
                .environment(\.mediaZoom, zoom)
                .contentShape(.rect)
                .onTapGesture { if opensViewer { viewing = true } }
                .accessibilityAddTraits(opensViewer ? .isButton : [])
                .accessibilityIdentifier(opensViewer ? "photo-block" : "media-block")
                .contextMenu {
                    MediaMenuItems(attachments: attachments, saver: saver) { forwarding = true }
                    if opensViewer, let loader = runtime.store.attachments {
                        ShareLink(items: loader.shareItems(attachments)) { SharePreview($0.attachment.name) }
                    }
                }
            if showsDownload { downloadButton }
        }
        .mediaSaving(saver)
        .sheet(isPresented: $forwarding) { ForwardSheet(attachments: attachments) }
        .fullScreenCover(isPresented: $viewing) {
            PhotoViewer(photos: attachments, start: 0, zoom: zoom).coverHomeBar(colorScheme: .dark)
        }
    }

    /// Only received media that has not been saved to Photos yet.
    private var showsDownload: Bool {
        !isFromMe && !SavedMedia.shared.containsAll(attachments.map(\.id))
    }

    /// One tap saves to Photos. Save to Files and Send to... stay in the long-press menu.
    private var downloadButton: some View {
        Button {
            Task { await saver.saveToPhotos(attachments, loader: runtime.store.attachments) }
        } label: {
            Group {
                if saver.busy { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.down").font(.system(size: 14, weight: .semibold)) }
            }
            .frame(width: 34, height: 34)
            .background(.regularMaterial, in: Circle())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(attachments.count > 1 ? "Save photos to Photos" : "Save to Photos")
        .accessibilityIdentifier("attachment-download")
    }
}
