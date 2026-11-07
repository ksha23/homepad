import HomePadCore
import HomePadUI
import SwiftUI

/// Shows one `AssistantCard` with the view for its kind.
struct AssistantCardView: View {
    let card: AssistantCard

    var body: some View {
        switch card.kind {
        case .calendar: CalendarCardView(card: card)
        case .weather: WeatherCardView(card: card)
        case .accessory: AccessoryCardView(card: card)
        case .timer: TimerCardView(card: card)
        case .image: ImageCardView(card: card)
        case .link: SourceChipsView(cards: [card])
        case .text, .camera: TextCardView(card: card)
        }
    }
}

/// A titled glass card for plain text answers attached by other modules.
struct TextCardView: View {
    let card: AssistantCard

    var body: some View {
        GlassTile {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(card.title).font(.title3.weight(.semibold))
                if let subtitle = card.subtitle { Text(subtitle).font(.body).foregroundStyle(.secondary) }
            }
        }
    }
}
