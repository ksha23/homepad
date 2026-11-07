import SwiftUI

/// A row of option cards, like picking a style or color in the watchOS face
/// editor. The cards sit centered when they fit and scroll with snapping
/// when they do not. Tapping a card selects it.
///
///     OptionCarousel(items: styles, selection: $styleID) { style, isSelected in
///         OptionCard(title: style.title, isSelected: isSelected) {
///             Image(systemName: style.systemImage).font(.largeTitle)
///         }
///     }
public struct OptionCarousel<Item: Identifiable, Card: View>: View where Item.ID: Hashable {
    private let items: [Item]
    @Binding private var selection: Item.ID?
    private let cardWidth: CGFloat
    private let card: (Item, Bool) -> Card

    /// - Parameters:
    ///   - items: The options, in order.
    ///   - selection: The selected option's ID.
    ///   - cardWidth: Width of each card.
    ///   - card: Draws one option, given whether it is selected. Usually an `OptionCard`.
    public init(
        items: [Item], selection: Binding<Item.ID?>, cardWidth: CGFloat = 180,
        @ViewBuilder card: @escaping (Item, Bool) -> Card
    ) {
        self.items = items
        self._selection = selection
        self.cardWidth = cardWidth
        self.card = card
    }

    public var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Spacing.l) {
                    ForEach(items) { item in
                        Button {
                            withAnimation(Theme.Motion.standard) { selection = item.id }
                        } label: {
                            card(item, item.id == selection).frame(width: cardWidth)
                        }
                        .buttonStyle(.plain)
                        .id(item.id)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .frame(minWidth: proxy.size.width)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection, anchor: .center)
            .sensoryFeedback(.selection, trigger: selection)
        }
    }
}
