import HomePadCore
import HomePadUI
import SwiftUI

/// A photo or generated image.
struct ImageCardView: View {
    let card: AssistantCard

    var body: some View {
        if let base64 = card.payload["base64"]?.stringValue, let data = Data(base64Encoded: base64), let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: 420)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .accessibilityLabel(card.title)
        } else if let url = card.url {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(maxWidth: .infinity, minHeight: 240, maxHeight: 420)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }
}
