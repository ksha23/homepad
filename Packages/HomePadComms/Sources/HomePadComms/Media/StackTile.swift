import CommsKit
import HomePadUI
import SwiftUI

/// One square, cropped thumbnail.
struct StackTile: View {
    @Environment(CommsRuntime.self) private var runtime
    let attachment: CommsAttachment
    let side: CGFloat
    var cornerRadius: CGFloat = Theme.Radius.card
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.systemGray5)
            if let image = image ?? runtime.store.attachments?.cachedImage(attachment.id) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ProgressView()
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .mediaZoomSource(id: attachment.id, cornerRadius: cornerRadius)
        .task(id: attachment.id) { image = await runtime.store.attachments?.image(attachment.id) }
    }
}
