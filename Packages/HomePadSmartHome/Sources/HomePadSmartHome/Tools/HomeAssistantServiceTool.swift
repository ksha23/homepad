import HomePadCore

/// The assistant's raw Home Assistant tool, for anything the generic device tools
/// do not cover (media_player.join, script.turn_on with variables, notify, and so on).
/// Needs a recognized household member.
enum HomeAssistantServiceTool {
    static let name = "home_assistant_service"

    @MainActor
    static func make(service: UnifiedSmartHomeService) -> AssistantTool {
        AssistantTool(
            name: name,
            description: """
            Call any Home Assistant service directly, for example domain "media_player", service "join", \
            or domain "script", service "turn_on". Use the generic device tools for ordinary lights, locks \
            and thermostats. Put the target in entity_id or inside data.
            """,
            parameters: Schema.object([
                "domain": Schema.string("Service domain, such as light, media_player, script or notify."),
                "service": Schema.string("Service name, such as turn_on, join or play_media."),
                "entity_id": Schema.string("Optional target entity ID, such as media_player.kitchen."),
                "data": .object(["type": "object", "description": "Optional service data fields."]),
            ], required: ["domain", "service"]),
            requiresRecognizedMember: true
        ) { arguments in
            guard let domain = arguments["domain"]?.stringValue, let serviceName = arguments["service"]?.stringValue else {
                return "Missing domain or service."
            }
            var data = arguments["data"]?.objectValue ?? [:]
            if let entityID = arguments["entity_id"]?.stringValue, !entityID.isEmpty { data["entity_id"] = .string(entityID) }
            try await service.callService(domain: domain, service: serviceName, data: .object(data))
            return "Called \(domain).\(serviceName)."
        }
    }
}
