import SwiftUI

/// Wrapping glass buttons for suggestions or quick replies, such as example
/// questions under "Ask About This".
///
///     SuggestionChips(["What is this?", "Is it ripe?"]) { ask($0) }
public struct SuggestionChips: View {
    private let items: [String]
    private let onTap: (String) -> Void

    /// - Parameters:
    ///   - items: The suggestions, in order. Each must be unique.
    ///   - onTap: Called with the tapped suggestion.
    public init(_ items: [String], onTap: @escaping (String) -> Void) {
        self.items = items
        self.onTap = onTap
    }

    public var body: some View {
        FlowLayout(spacing: Theme.Spacing.s) {
            ForEach(items, id: \.self) { item in
                // The large capsule, `Theme.Size.tapTarget` tall, like `ChoiceChips`.
                Button(item) { onTap(item) }
                    .buttonStyle(.glassCapsule(size: .large))
            }
        }
    }
}
