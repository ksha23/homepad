import SwiftUI

extension Font {
    /// Words read from across the room beside a huge `display` number, such as
    /// the place over the Weather app's far temperature. Candidate for HomePadUI,
    /// where the recipe card's title needs it too.
    static let farTitle: Font = .system(size: 64, weight: .semibold)

    /// The lines under a far title and number, such as the condition and the
    /// high and low. Candidate for HomePadUI.
    static let farDetail: Font = .system(size: 44, weight: .medium)
}
