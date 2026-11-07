import Foundation

/// The pages the face on the wall lays out: the face at rest in the middle,
/// with the `reach` faces before and after it in the saved order on either
/// side, wrapping around at the ends. With one saved face there is only its page.
///
/// Every page has an identity of its own, so with two saved faces the other
/// face can sit on both sides. When the pages come to rest on a page beside
/// the middle one, the window moves along: the pages it keeps keep their
/// identity, so the faces drawn on them keep running, and only the page
/// beyond is new.
struct FacePageWindow: Equatable {
    /// One page and the saved face drawn on it.
    struct Page: Identifiable, Equatable {
        let id: UUID
        /// The saved face (`FaceConfiguration.id`).
        let faceID: UUID
    }

    /// How many faces lie ready on each side of the one at rest. The window
    /// moves along only once the pages rest, so a quick second flick, made
    /// while the first still glides, lands one page further out. With one face
    /// on each side there was nothing there, and the flick bounced back.
    static let reach = 2

    private(set) var pages: [Page]

    /// A window around a saved face, with new pages.
    init(around faceID: UUID, order: [UUID]) {
        pages = Self.pages(resting: Page(id: UUID(), faceID: faceID), old: [], order: order)
    }

    private init(pages: [Page]) {
        self.pages = pages
    }

    /// The page in the middle: the face at rest.
    var resting: Page {
        pages[pages.count / 2]
    }

    /// The window around a page of this one, after the pages came to rest on
    /// it or the saved faces changed. A page of this window that shows the
    /// face now at its distance on its side stays.
    func centered(on page: Page, order: [UUID]) -> FacePageWindow {
        FacePageWindow(pages: Self.pages(resting: page, old: pages, order: order))
    }

    private static func pages(resting: Page, old: [Page], order: [UUID]) -> [Page] {
        guard order.count > 1, let index = order.firstIndex(of: resting.faceID) else { return [resting] }
        let count = order.count
        let position = old.firstIndex(of: resting)
        let before = position.map { Array(old[..<$0].reversed()) } ?? []
        let after = position.map { Array(old[($0 + 1)...]) } ?? []
        /// The page `distance` away on one side: the old one there when it shows that face, else a new one.
        func page(_ distance: Int, from side: [Page], faceID: UUID) -> Page {
            let kept = side.indices.contains(distance - 1) ? side[distance - 1] : nil
            return kept?.faceID == faceID ? kept! : Page(id: UUID(), faceID: faceID)
        }
        let left = (1...reach).reversed().map { distance in
            page(distance, from: before, faceID: order[((index - distance) % count + count) % count])
        }
        let right = (1...reach).map { distance in
            page(distance, from: after, faceID: order[(index + distance) % count])
        }
        return left + [resting] + right
    }
}
