import Foundation
import HomePadCore

/// Assistant tools Camera Lab contributes to every AI provider.
@MainActor
enum CameraLabTools {
    static func make(lab: CameraLab) -> [AssistantTool] {
        [lookWithCamera(lab), scanGroceries(lab), securityCamera(lab)]
    }

    /// Takes a still and returns a text description of it. Tool results are
    /// text only, so the picture goes to the assistant in a separate side
    /// request (no overlay, no speech) and the description comes back here.
    static func lookWithCamera(_ lab: CameraLab) -> AssistantTool {
        AssistantTool(
            name: "look_with_camera",
            description: """
            Take a photo with the HomePad's camera and get a description of it. Use it when the person asks about \
            something they are holding up or something in front of the display, for example "what is this", \
            "is this avocado ripe" or "what does this label say". Pass their question so the description focuses on it.
            """,
            parameters: Schema.object([
                "question": Schema.string("What the person wants to know about what the camera sees."),
                "camera": Schema.string("Which camera to use. The back camera faces away from the screen.", enumValues: ["back", "front"]),
            ], required: ["question"])
        ) { arguments in
            let question = arguments["question"]?.stringValue ?? "What is this?"
            let camera = CameraPosition(rawValue: arguments["camera"]?.stringValue ?? "back") ?? .back
            let still: CapturedStill
            do {
                still = try await lab.stills.grab(owner: "cameralab.assistant", title: "Assistant", camera: camera)
            } catch {
                return "The camera could not take a picture: \(error.localizedDescription)"
            }
            let request = AssistantRequest(
                text: "Describe this photo from a home display's \(camera.rawValue) camera in detail, focusing on this question: \(question)",
                images: [still.jpeg], speakResponse: false, presentInOverlay: false
            )
            var description = ""
            for try await event in lab.services.assistant.ask(request) {
                switch event {
                case .textDelta(let delta): description += delta
                case .finished(let fullText): if description.isEmpty { description = fullText }
                default: break
                }
            }
            let demoNote = still.isDemo ? "This picture came from the simulator's demo feed, not a real camera. " : ""
            return "\(demoNote)The \(camera.rawValue) camera shows: \(description)"
        }
    }

    static func scanGroceries(_ lab: CameraLab) -> AssistantTool {
        AssistantTool(
            name: "scan_groceries",
            description: "Open the grocery barcode scanner on the HomePad so the person can scan items into their Groceries list in Reminders.",
            parameters: Schema.object([:])
        ) { _ in
            lab.router.open(.groceries)
            lab.services.events.post(.openApp(id: CameraLabModule.appID))
            return "The grocery scanner is open. Hold each barcode up to the back camera. Items go to the \(lab.groceries.listName) list after a few seconds, and Undo takes the last one back."
        }
    }

    /// Needs a recognized person, so nobody can switch off the camera by asking from the doorway.
    static func securityCamera(_ lab: CameraLab) -> AssistantTool {
        AssistantTool(
            name: "security_camera",
            description: "Turn HomePad's Security Camera mode on or off, or report its status and the last motion.",
            parameters: Schema.object([
                "action": Schema.string("What to do.", enumValues: ["on", "off", "status"]),
            ], required: ["action"]),
            requiresRecognizedMember: true
        ) { arguments in
            let security = lab.security
            switch arguments["action"]?.stringValue {
            case "on": security.setEnabled(true)
            case "off": security.setEnabled(false)
            default: break
            }
            var status = security.isEnabled
                ? (security.isWatching ? "Security Camera is on and watching." : "Security Camera is on and waiting for its \(security.schedule.title.lowercased()) schedule.")
                : "Security Camera is off."
            if let last = security.lastAlertAt {
                status += " Last motion was \(last.formatted(.relative(presentation: .named)))."
            }
            return status
        }
    }
}
