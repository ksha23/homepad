import Foundation
import HomePadCore

/// Turns the ports of the current system route into `AudioOutput`s and a short
/// name for the whole route, such as "Living Room and Kitchen".
enum RouteNaming {
    static let builtInID = "builtin"
    static let builtInName = "iPad"

    static func outputs(for ports: [AudioRoutePort]) -> [AudioOutput] {
        guard !ports.isEmpty else {
            return [AudioOutput(id: builtInID, name: builtInName, kind: .builtInSpeaker, isActive: true)]
        }
        return ports.map { port in
            AudioOutput(
                id: port.kind == .builtInSpeaker ? builtInID : "route:\(port.uid)",
                name: displayName(port), kind: port.kind, isActive: true
            )
        }
    }

    static func displayName(_ port: AudioRoutePort) -> String {
        port.kind == .builtInSpeaker ? builtInName : port.name
    }

    /// One name for the route. AirPlay groups list up to two speakers, then a count.
    static func routeName(for ports: [AudioRoutePort]) -> String {
        routeName(names: ports.map(displayName))
    }

    /// One name for several speaker names, repeats dropped.
    static func routeName(names all: [String]) -> String {
        var names: [String] = []
        for name in all where !names.contains(name) {
            names.append(name)
        }
        switch names.count {
        case 0: return builtInName
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]) and \(names.count - 1) more"
        }
    }
}
