import Foundation
import HomePadCore

/// Decides when to offer the one-tap "Play on Living Room?" prompt.
/// iOS gives apps no way to pick an AirPlay speaker themselves (see the README),
/// so HomePad asks with the system route picker instead.
enum RoutePromptPolicy {
    static func shouldPrompt(preferredSpeaker: String, enabled: Bool, ports: [AudioRoutePort]) -> Bool {
        let preferred = preferredSpeaker.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard enabled, !preferred.isEmpty else { return false }
        // Headphones mean private listening on purpose. Never pull sound out of them.
        guard !ports.contains(where: \.isHeadphones) else { return false }
        return !isPlaying(on: preferred, ports: ports)
    }

    /// True when any current output carries the preferred name.
    static func isPlaying(on preferred: String, ports: [AudioRoutePort]) -> Bool {
        let preferred = preferred.lowercased()
        return ports.contains { port in
            let name = RouteNaming.displayName(port).lowercased()
            return name == preferred || name.contains(preferred) || preferred.contains(name)
        } || (ports.isEmpty && preferred == RouteNaming.builtInName.lowercased())
    }
}
