import SwiftUI

/// A search field on a glass capsule: a magnifying glass, the field and a
/// clear button once something is typed. Sheets draw their own header
/// (`SheetScreen`) instead of a navigation bar, so `.searchable` has nowhere
/// to go there. Put this first in the sheet's content instead.
///
///     SheetScreen("Add City") {
///         VStack(spacing: Theme.Spacing.s) {
///             GlassSearchField("City", text: $query).padding(.horizontal, Theme.Spacing.l)
///             List { ... }
///         }
///     }
///
/// It is as tall as a header item (`Theme.Size.toolbarItem`), so it lines up
/// with the header above it.
public struct GlassSearchField: View {
    private let prompt: String
    @Binding private var text: String

    /// - Parameters:
    ///   - prompt: The placeholder, which says what to search for.
    ///   - text: The search text.
    public init(_ prompt: String, text: Binding<String>) {
        self.prompt = prompt
        self._text = text
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: Theme.Size.minTapTarget, height: Theme.Size.minTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear Search")
            }
        }
        .font(.title3)
        .padding(.leading, Theme.Spacing.m)
        .padding(.trailing, text.isEmpty ? Theme.Spacing.m : 0)
        .frame(minHeight: Theme.Size.toolbarItem)
        .glassEffect(.regular, in: .capsule)
    }
}
