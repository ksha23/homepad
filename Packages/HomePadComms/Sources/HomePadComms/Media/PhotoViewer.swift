import CommsKit
import SwiftUI

/// Full-screen viewer for one message's photos: swipe between them, pinch or double-tap
/// to zoom, and Done, Share, Save and Send to... along the top.
struct PhotoViewer: View {
    @Environment(CommsRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    let photos: [CommsAttachment]
    @State var index: Int
    @State private var saver = MediaSaver()
    @State private var forwarding = false
    /// The block's namespace, so closing zooms back into the photo now showing.
    let zoom: Namespace.ID?

    init(photos: [CommsAttachment], start: Int, zoom: Namespace.ID? = nil) {
        self.photos = photos
        self.zoom = zoom
        _index = State(initialValue: start)
    }

    private var current: CommsAttachment { photos[min(max(index, 0), photos.count - 1)] }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                    PhotoPage(attachment: photo).tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()
        }
        .overlay(alignment: .top) { topBar }
        .preferredColorScheme(.dark)
        .mediaSaving(saver)
        .sheet(isPresented: $forwarding) { ForwardSheet(attachments: [current]) }
        .modifier(ZoomBack(id: current.id, zoom: zoom))
    }

    private var topBar: some View {
        HStack(spacing: 18) {
            Button("Done") { dismiss() }.fontWeight(.semibold).accessibilityIdentifier("viewer-done")
            Spacer()
            if photos.count > 1 { Text("\(index + 1) of \(photos.count)").font(.subheadline).monospacedDigit() }
            Spacer()
            if let loader = runtime.store.attachments {
                ShareLink(item: loader.shareItems([current])[0], preview: SharePreview(current.name)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Share")
            }
            Menu {
                MediaMenuItems(attachments: [current], saver: saver) { forwarding = true }
            } label: {
                if saver.busy { ProgressView() } else { Image(systemName: "arrow.down.circle") }
            }
            .accessibilityLabel("Save")
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.black.opacity(0.35))
    }
}

/// The viewer's side of the zoom: it grows from the tapped photo and shrinks back into the
/// one showing, and a swipe down closes it by following the finger.
private struct ZoomBack: ViewModifier {
    let id: String
    let zoom: Namespace.ID?

    func body(content: Content) -> some View {
        if let zoom { content.navigationTransition(.zoom(sourceID: id, in: zoom)) } else { content }
    }
}
