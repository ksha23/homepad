import CommsKit
import Foundation

/// One thing read from the hub's live stream.
public enum StreamPacket: Sendable, Equatable {
    /// The hub's run identifier, sent first. A new one means event numbers restarted.
    case hello(epoch: Int)
    case event(id: Int?, CommsEvent)
    /// The hub no longer remembers back to the client's last event, so the client must reload.
    case gap
}

/// Turns the stream's lines into packets. Blank lines never arrive (`URLSession` drops them),
/// so a packet is complete at its `data:` line, with `id:` and `event:` lines before it.
struct StreamParser {
    private var id: Int?
    private var eventName: String?

    mutating func feed(_ line: String) -> StreamPacket? {
        if line.hasPrefix("id:") {
            id = Int(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
            return nil
        }
        if line.hasPrefix("event:") {
            eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
            return nil
        }
        guard line.hasPrefix("data:") else { return nil }
        defer { id = nil; eventName = nil }
        let body = Data(line.dropFirst(5).utf8)
        switch eventName {
        case "gap":
            return .gap
        case "hello":
            let epoch = (try? JSONSerialization.jsonObject(with: body) as? [String: Any])?["epoch"] as? Int
            return epoch.map { .hello(epoch: $0) }
        default:
            guard let event = try? CommsRoutes.makeDecoder().decode(CommsEvent.self, from: body) else { return nil }
            return .event(id: id, event)
        }
    }
}
