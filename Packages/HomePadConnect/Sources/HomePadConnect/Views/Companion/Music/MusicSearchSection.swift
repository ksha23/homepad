import HomePadCore
import HomePadUI
import SwiftUI

/// Starts music on a HomePad from the phone. The HomePad searches its own music
/// (`MediaService.playSearch`) and plays the best match. When that finds
/// nothing, or the HomePad is too old for music control, the request goes to
/// the HomePad's assistant instead ("Play jazz"), which every HomePad understands.
struct MusicSearchSection: View {
    @Environment(ConnectRuntime.self) private var connect
    let peer: PeerDevice
    /// True for a HomePad too old for music commands: every search goes to its assistant.
    let viaAssistant: Bool
    @State private var query = ""
    @State private var outcome: Outcome?
    @State private var isSending = false

    /// What happened to the last search.
    private struct Outcome {
        var text: String
        var isError: Bool
        /// The search that failed, offered to the assistant.
        var failedQuery: String?
    }

    /// Ideas for a phone that has not searched yet.
    private static let starters = ["Jazz", "Morning Coffee", "Classical Focus", "Today's Hits"]
    private static let recentLimit = 6

    private var recents: [String] { connect.services.settings[ConnectSettings.musicRecentSearches] }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Play Music", systemImage: "magnifyingglass")
            HStack(spacing: Theme.Spacing.s) {
                TextField("Song, artist, station or mood", text: $query)
                    .padding(.horizontal, Theme.Spacing.m)
                    .frame(height: Theme.Size.toolbarItem)
                    .glassEffect(.regular, in: Capsule())
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { play(query) }
                GlassIconButton("play.fill", label: "Play", size: Theme.Size.toolbarItem, isProminent: true) { play(query) }
                    .disabled(trimmed(query).isEmpty || isSending)
            }
            if isSending {
                ProgressView().frame(maxWidth: .infinity, alignment: .leading)
            } else if let outcome {
                outcomeView(outcome)
            }
            SuggestionChips(recents.isEmpty ? Self.starters : recents) { play($0) }
                .disabled(isSending)
        }
    }

    @ViewBuilder
    private func outcomeView(_ outcome: Outcome) -> some View {
        Label(outcome.text, systemImage: outcome.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
            .font(.subheadline)
            .foregroundStyle(outcome.isError ? .orange : .secondary)
        if let failed = outcome.failedQuery {
            GlassCapsuleButton("Ask \(peer.name) Instead", systemImage: "sparkles", size: .regular) { ask(failed) }
        }
    }

    private func play(_ text: String) {
        let text = trimmed(text)
        guard !text.isEmpty, !isSending else { return }
        remember(text)
        query = ""
        if viaAssistant {
            ask(text)
            return
        }
        isSending = true
        outcome = nil
        Task {
            do {
                let started = try await connect.music.send(.playSearch(query: text), to: peer.id)
                outcome = Outcome(text: started ?? "Playing on \(peer.name).", isError: false)
            } catch RemoteError.updateRequired(let homePad) {
                outcome = Outcome(text: RemoteControlServer.updateMessage(for: homePad), isError: true, failedQuery: text)
            } catch RemoteError.failed(let message) {
                outcome = Outcome(text: message, isError: true, failedQuery: text)
            } catch {
                outcome = Outcome(text: error.localizedDescription, isError: true)
            }
            isSending = false
        }
    }

    /// The assistant path: "Play <query>" on the HomePad, as if asked out loud.
    private func ask(_ text: String) {
        isSending = true
        outcome = nil
        Task {
            do {
                try await connect.remote.send(.ask(prompt: "Play \(text)"), to: peer.id)
                outcome = Outcome(text: "Asked \(peer.name) to play \(text).", isError: false)
            } catch {
                outcome = Outcome(text: error.localizedDescription, isError: true)
            }
            isSending = false
        }
    }

    private func remember(_ text: String) {
        var list = recents.filter { $0.caseInsensitiveCompare(text) != .orderedSame }
        list.insert(text, at: 0)
        connect.services.settings[ConnectSettings.musicRecentSearches] = Array(list.prefix(Self.recentLimit))
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
