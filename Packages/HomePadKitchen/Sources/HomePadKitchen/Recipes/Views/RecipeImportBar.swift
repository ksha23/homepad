import HomePadUI
import SwiftUI

/// The library's one field, like Safari's: words search the online catalog as
/// they are typed, and a link imports that page. The system Paste button (no
/// clipboard permission prompt) imports a pasted link or recipe text. Import
/// progress and errors show under the field.
struct RecipeImportBar: View {
    let context: KitchenContext
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Image(systemName: isLink ? "link" : "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search recipes or paste a link", text: $text)
                    .font(.title3)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(isLink ? .go : .search)
                    .onSubmit(submit)
                    .onChange(of: text) { _, value in typed(value) }
                if !text.isEmpty {
                    Button(action: clear) {
                        Image(systemName: "xmark.circle.fill").font(.title3)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Clear Search")
                }
                PasteButton(payloadType: String.self) { strings in
                    guard let pasted = strings.first else { return }
                    Task { @MainActor in importPasted(pasted) }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
                // Large, so the system button fills the bar's height instead of a 34 point circle.
                .controlSize(.large)
                .tint(.orange)
                if isLink {
                    GlassCapsuleButton("Import", systemImage: "square.and.arrow.down", size: .regular, isProminent: true, tint: .orange, action: submit)
                        .disabled(isWorking)
                }
            }
            .padding(.leading, Theme.Spacing.m)
            .padding(Theme.Spacing.xs)
            .frame(minHeight: Theme.Size.minTapTarget + Theme.Spacing.xs * 2)
            .glassEffect(.regular, in: .capsule)

            if let status = context.importStatus {
                statusLine(status)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Theme.Motion.standard, value: context.importStatus)
        .onChange(of: context.search.query, initial: true) { _, query in
            // The assistant searches too, and a search outlives a visit to a
            // recipe card. Its words show in the field.
            if !query.isEmpty, query != text.trimmingCharacters(in: .whitespacesAndNewlines) { text = query }
        }
    }

    private var isWorking: Bool {
        if case .working = context.importStatus { return true }
        return false
    }

    private var isLink: Bool { Self.isLink(text) }

    /// A single web address, as opposed to words to search for.
    static func isLink(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !trimmed.contains(" ") && RecipeImporter.url(from: trimmed) != nil
    }

    @ViewBuilder
    private func statusLine(_ status: RecipeImportStatus) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            switch status {
            case .working(let message):
                ProgressView()
                Text(message)
            case .imported(let title):
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Added \(title)")
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(message)
            }
        }
        .font(.headline)
        .padding(.horizontal, Theme.Spacing.m)
    }

    private func typed(_ value: String) {
        if Self.isLink(value) {
            context.search.clear()
        } else {
            context.search.update(query: value)
        }
    }

    private func submit() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if Self.isLink(value) {
            text = ""
            Task { await context.importRecipe(link: value) }
        } else {
            Task { await context.search.run(value) }
        }
    }

    private func clear() {
        text = ""
        context.search.clear()
    }

    /// A pasted link imports the page. Anything longer is treated as recipe text.
    private func importPasted(_ pasted: String) {
        if RecipeImporter.url(from: pasted) != nil, !pasted.contains("\n"), pasted.count < 500 {
            clear()
            Task { await context.importRecipe(link: pasted) }
        } else {
            Task { await context.importRecipe(text: pasted) }
        }
    }
}
