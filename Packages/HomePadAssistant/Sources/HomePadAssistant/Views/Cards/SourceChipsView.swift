import HomePadCore
import HomePadUI
import SwiftUI

/// Where an answer came from, as small chips under it, like HomeView's
/// "Wikipedia" and "+3": the first source by its site, then "+N" with the rest
/// in a menu. Each opens its link, as the full-width link cards did.
struct SourceChipsView: View {
    /// Link cards. Cards without a link are skipped.
    let cards: [AssistantCard]
    @Environment(\.openURL) private var openURL

    var body: some View {
        let sources = cards.filter { $0.url != nil }
        if let first = sources.first, let url = first.url {
            HStack(spacing: Theme.Spacing.xs) {
                Link(destination: url) { SourceChip(text: SourceSite.name(of: url)) }
                    .accessibilityLabel("Source, \(first.title), \(SourceSite.name(of: url))")
                let rest = sources.dropFirst()
                if !rest.isEmpty {
                    Menu {
                        ForEach(rest) { card in
                            if let url = card.url {
                                Button(card.title) { openURL(url) }
                                    .accessibilityHint(SourceSite.name(of: url))
                            }
                        }
                    } label: {
                        SourceChip(text: "+\(rest.count)")
                    }
                    .accessibilityLabel("\(rest.count) more \(rest.count == 1 ? "source" : "sources")")
                }
            }
            .buttonStyle(.pressable)
        }
    }
}

/// One small gray capsule. The capsule is small, as on HomeView, and the tap
/// area around it is still `minTapTarget` tall.
private struct SourceChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .controlSurface(Capsule())
            .frame(minHeight: Theme.Size.minTapTarget)
            .contentShape(Rectangle())
    }
}

/// The name a source chip shows for a link.
enum SourceSite {
    /// "wikipedia.org" for en.wikipedia.org or en.m.wikipedia.org: the host
    /// without "www", a mobile "m" or a language prefix.
    static func name(of url: URL) -> String {
        guard let host = url.host()?.lowercased() else { return url.absoluteString }
        var labels = host.split(separator: ".").map(String.init)
        while labels.count > 2, isPrefix(labels[0], before: labels.dropFirst()) {
            labels.removeFirst()
        }
        return labels.joined(separator: ".")
    }

    /// "www", "m" or "mobile", or two letters for a language before a site
    /// name ("en.wikipedia.org"), but not a short name before a country's
    /// domain ("ab.co.uk").
    private static func isPrefix(_ label: String, before rest: ArraySlice<String>) -> Bool {
        if ["www", "m", "mobile"].contains(label) { return true }
        guard label.count == 2, rest.count >= 2 else { return false }
        return rest[rest.endIndex - 2].count > 3
    }
}
