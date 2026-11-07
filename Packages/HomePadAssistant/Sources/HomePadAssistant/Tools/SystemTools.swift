import Foundation
import HomePadCore

/// Intercom and navigation: announce to other HomePads, open apps, show faces.
enum SystemTools {
    static func make(_ context: ToolContext) -> [AssistantTool] {
        [announce(context), openApp(context), showFace(context)]
    }

    static func announce(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "intercom_announce",
            description: "Announce a short message on the other HomePads in the home, or one of them.",
            parameters: Schema.object([
                "message": Schema.string("What to announce."),
                "room": Schema.string("Optional HomePad or room to send to. Leave out for everyone."),
            ], required: ["message"])
        ) { json in
            let args = ToolArguments(json)
            let message = try args.requireString("message")
            let intercom = try context.services.intercom
            let peer = args.string("room").flatMap { room in
                intercom.peers.first { $0.localizedCaseInsensitiveContains(room) }
            }
            if let room = args.string("room"), peer == nil {
                return "No HomePad named \(room). Available: \(intercom.peers.isEmpty ? "none" : intercom.peers.joined(separator: ", "))."
            }
            try await intercom.announce(text: message, audio: nil, to: peer)
            return "Announced" + (peer.map { " to \($0)" } ?? " to everyone") + "."
        }
    }

    static func openApp(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "open_app",
            description: "Open one of HomePad's apps, for example Home, Music, Timers or Calendar.",
            parameters: Schema.object(["app": Schema.string("App name.")], required: ["app"])
        ) { json in
            let wanted = try ToolArguments(json).requireString("app")
            let apps = context.registry?.apps ?? []
            guard let app = bestMatch(wanted, in: apps.map { ($0.id, $0.title) }) else {
                return "No app named \(wanted). Apps: \(apps.map(\.title).joined(separator: ", "))."
            }
            try context.services.events.post(.openApp(id: app.id))
            return "Opened \(app.title)."
        }
    }

    static func showFace(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "show_face",
            description: "Switch the always-on screen to a face, for example Photos, Clock or Cameras.",
            parameters: Schema.object(["face": Schema.string("Face name.")], required: ["face"])
        ) { json in
            let wanted = try ToolArguments(json).requireString("face")
            let faces = context.registry?.faces ?? []
            guard let face = bestMatch(wanted, in: faces.map { ($0.id, $0.title) }) else {
                return "No face named \(wanted). Faces: \(faces.map(\.title).joined(separator: ", "))."
            }
            try context.services.events.post(.showFace(id: face.id))
            return "Showing the \(face.title) face."
        }
    }

    /// Exact title or id first, then a title that contains the request or the other way round.
    static func bestMatch(_ wanted: String, in items: [(id: String, title: String)]) -> (id: String, title: String)? {
        let needle = DeviceTargetResolver.normalize(wanted)
        return items.first { DeviceTargetResolver.normalize($0.title) == needle || $0.id.lowercased() == needle }
            ?? items.first {
                let title = DeviceTargetResolver.normalize($0.title)
                return !title.isEmpty && (title.contains(needle) || needle.contains(title))
            }
    }
}
