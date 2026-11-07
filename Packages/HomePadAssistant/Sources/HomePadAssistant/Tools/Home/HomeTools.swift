import Foundation
import HomePadCore

/// Generic smart home tools that work with any backend through `services.smartHome`.
enum HomeTools {
    static func make(_ context: ToolContext) -> [AssistantTool] {
        [listDevices(context), controlDevice(context), activateScene(context)]
    }

    private static let kindNames = AccessoryKind.allCases.map(\.rawValue)

    static func listDevices(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "list_devices",
            description: "List smart home devices with their current state. Optionally filter by room or kind.",
            parameters: Schema.object([
                "room": Schema.string("Room name, for example Kitchen."),
                "kind": Schema.string("Device kind.", enumValues: kindNames),
            ])
        ) { json in
            let args = ToolArguments(json)
            var accessories = try context.services.smartHome.accessories
            if let room = args.string("room") { accessories = accessories.filter { DeviceTargetResolver.matchesRoom($0, room) } }
            if let kind = args.string("kind").flatMap(AccessoryKind.init(rawValue:)) { accessories = accessories.filter { $0.kind == kind } }
            guard !accessories.isEmpty else { return "No devices found." }
            context.emit(CardFactory.accessories(accessories, title: args.string("room") ?? "Devices"))
            return SystemPromptBuilder.homeLines(for: accessories, compact: false).joined(separator: "\n")
        }
    }

    static func controlDevice(_ context: ToolContext) -> AssistantTool {
        let action = Schema.object([
            "device": Schema.string("Device name or kind as the person said it, for example \"kitchen lights\", \"fan\" or \"everything\"."),
            "room": Schema.string("Room, when the person named one."),
            "action": Schema.string("What to do.", enumValues: DeviceAction.allCases.map(\.rawValue)),
            "value": Schema.number("Percent for brightness, position and volume. Degrees for temperature. Kelvin for color temperature."),
            "color": Schema.string("Color name for set_color, for example red or warm white."),
            "mode": Schema.string("Thermostat mode for set_mode.", enumValues: HVACMode.allCases.map(\.rawValue)),
        ], required: ["action"])
        return AssistantTool(
            name: "control_device",
            description: """
            Control one or more smart home devices in one call. Use one action per device group, \
            for example turn off the kitchen lights and set the thermostat to 70. Unlocking, opening \
            garage doors and disarming ask the person to confirm first.
            """,
            parameters: Schema.object(["actions": ["type": "array", "items": action, "description": "Changes to make."]], required: ["actions"])
        ) { json in
            let steps = ToolArguments(json).array("actions").compactMap { step -> DeviceControlExecutor.Step? in
                guard let action = step.string("action").flatMap(DeviceAction.init(rawValue:)) else { return nil }
                return DeviceControlExecutor.Step(
                    device: step.string("device"), room: step.string("room"),
                    instruction: DeviceInstruction(action: action, value: step.double("value"), color: step.string("color"), mode: step.string("mode"))
                )
            }
            guard !steps.isEmpty else { throw ToolError("No valid actions. Each action needs an action name from the list.") }
            let smartHome = try context.services.smartHome
            let executor = DeviceControlExecutor(smartHome: smartHome) { question in
                await context.confirmations.confirm(question)
            }
            let report = await executor.run(steps)
            let touched = report.touchedIDs.compactMap { smartHome.accessory($0) }
            if !touched.isEmpty { context.emit(CardFactory.accessories(touched, title: "Home")) }
            return report.summary
        }
    }

    static func activateScene(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "activate_scene",
            description: "Run a smart home scene such as Good Night.",
            parameters: Schema.object(["scene": Schema.string("Scene name.")], required: ["scene"])
        ) { json in
            let name = try ToolArguments(json).requireString("scene")
            let smartHome = try context.services.smartHome
            let wanted = DeviceTargetResolver.normalize(name)
            let match = smartHome.scenes.first { DeviceTargetResolver.normalize($0.name) == wanted }
                ?? smartHome.scenes.first { DeviceTargetResolver.normalize($0.name).contains(wanted) || wanted.contains(DeviceTargetResolver.normalize($0.name)) }
            guard let scene = match else {
                let names = smartHome.scenes.map(\.name).joined(separator: ", ")
                return "No scene named \(name). Scenes: \(names.isEmpty ? "none" : names)."
            }
            try await smartHome.activateScene(scene.id)
            return "Ran the \(scene.name) scene."
        }
    }
}
