import SwiftUI

/// A horizontal row of glass capsules where exactly one is selected, for
/// short curated choices: rooms in the Home app, intercom destinations.
/// Chips are `GlassCapsuleButton`'s large size, and the selected one is
/// filled with the app's accent.
///
///     ChoiceChips([.init(id: nil, title: "All Rooms")] + rooms.map { .init(id: $0, title: $0) },
///                 selection: $room)
public struct ChoiceChips<ID: Hashable>: View {
    /// One choice in the row.
    public struct Choice: Identifiable {
        public let id: ID
        public let title: String
        public let systemImage: String?

        /// - Parameters:
        ///   - id: The value the selection binding takes when this chip is tapped.
        ///   - title: The chip's label.
        ///   - systemImage: Optional SF Symbol before the title.
        public init(id: ID, title: String, systemImage: String? = nil) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
        }
    }

    private let choices: [Choice]
    @Binding private var selection: ID
    @Environment(\.appAccent) private var appAccent

    /// - Parameters:
    ///   - choices: The chips, in order.
    ///   - selection: The selected chip's `id`.
    public init(_ choices: [Choice], selection: Binding<ID>) {
        self.choices = choices
        self._selection = selection
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(choices) { choice in
                    let isSelected = choice.id == selection
                    Button {
                        selection = choice.id
                    } label: {
                        if let systemImage = choice.systemImage {
                            Label(choice.title, systemImage: systemImage)
                        } else {
                            Text(choice.title)
                        }
                    }
                    // The large capsule: `Theme.Size.tapTarget` tall with Title 3
                    // text, the walk-up size. The selected chip fills with the
                    // app's accent like every prominent control.
                    .buttonStyle(.glassCapsule(size: .large, tint: isSelected ? appAccent : nil))
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
        }
        .scrollClipDisabled()
        .sensoryFeedback(.selection, trigger: selection)
    }
}
