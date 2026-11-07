import CommsKit
import HomePadUI
import SwiftUI

/// Several photos from one message as a pile (2 or 3) or a grid with a "+N" tile (4 or more).
/// The caller makes the whole stack one tap target.
struct AttachmentStack: View {
    let photos: [CommsAttachment]

    var body: some View {
        switch StackLayout.choose(count: photos.count) {
        case .single:
            StackTile(attachment: photos[0], side: 220)
        case .pile(let count):
            pile(count: count)
        case .grid(let shown, let extra):
            grid(shown: shown, extra: extra)
        }
    }

    /// The first photo on top, the next ones fanned out behind it.
    private func pile(count: Int) -> some View {
        ZStack {
            ForEach(Array(photos.prefix(count).enumerated()).reversed(), id: \.element.id) { index, photo in
                StackTile(attachment: photo, side: 200)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).stroke(.background, lineWidth: 2))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .rotationEffect(.degrees(Double(index) * (index.isMultiple(of: 2) ? 4 : -4)))
                    .offset(x: CGFloat(index) * 10, y: CGFloat(index) * -8)
            }
        }
        .frame(width: 240, height: 232)
    }

    private func grid(shown: Int, extra: Int) -> some View {
        let side: CGFloat = 130
        return LazyVGrid(columns: [GridItem(.fixed(side), spacing: 3), GridItem(.fixed(side), spacing: 3)], spacing: 3) {
            ForEach(Array(photos.prefix(shown).enumerated()), id: \.element.id) { index, photo in
                StackTile(attachment: photo, side: side, cornerRadius: Theme.Radius.thumbnail)
                    .overlay {
                        if extra > 0, index == shown - 1 {
                            ZStack {
                                Color.black.opacity(0.5)
                                Text("+\(extra)").font(.title.bold()).foregroundStyle(.white)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
            }
        }
        .frame(width: side * 2 + 3)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}
