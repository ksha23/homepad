import Foundation
import HomePadCore

/// Turns Home Assistant entity states into HomePad's backend-neutral models.
/// Pure and synchronous, so it is easy to test against fixture JSON.
enum HAStateMapper {
    struct Context {
        var registry = HARegistry()
        var temperatureUnit: TemperatureUnit = .celsius
        /// Base URL of the instance, for camera URLs.
        var baseURL: URL?
        /// Local entity ID of an extra doorbell trigger the person picked.
        var doorbellTriggerID: String?
    }

    struct Output: Equatable {
        var accessories: [HomeAccessory] = []
        var scenes: [HomeScene] = []
        var cameras: [HomeCamera] = []
    }

    /// The parts of an accessory that depend on the entity's domain.
    struct Mapped: Equatable {
        var kind: AccessoryKind
        var capabilities: Set<AccessoryCapability>
        var state: AccessoryState
    }

    static func map(_ states: [HAState], context: Context) -> Output {
        let visible = states.filter { !context.registry.isHidden($0.entityID) }
        let doorbellDevices = Set(visible.compactMap { state -> String? in
            guard HADoorbellDetector.isDoorbellEntity(state, configuredTriggerID: context.doorbellTriggerID) else { return nil }
            return context.registry.deviceID(for: state.entityID)
        })
        var output = Output()
        for state in visible {
            switch state.domain {
            case "scene", "script":
                output.scenes.append(scene(from: state))
            case "camera":
                output.cameras.append(camera(from: state, context: context, doorbellDevices: doorbellDevices))
            default:
                if let accessory = accessory(from: state, context: context) {
                    output.accessories.append(accessory)
                }
            }
        }
        output.accessories.sort { byName($0.name, $1.name) }
        output.scenes.sort { byName($0.name, $1.name) }
        output.cameras.sort { byName($0.name, $1.name) }
        return output
    }

    static func accessory(from state: HAState, context: Context) -> HomeAccessory? {
        guard var mapped = mapDomain(state, context: context) else { return nil }
        mapped.state.isReachable = !state.isUnavailable
        return HomeAccessory(
            id: BackendID.make(.homeAssistant, state.entityID),
            name: displayName(of: state, registry: context.registry),
            room: context.registry.roomName(for: state.entityID),
            kind: mapped.kind,
            backend: .homeAssistant,
            capabilities: mapped.capabilities,
            state: mapped.state,
            integration: context.registry.platform(of: state.entityID),
            deviceClass: state.deviceClass,
            deviceModel: context.registry.deviceModel(for: state.entityID)
        )
    }

    static func scene(from state: HAState) -> HomeScene {
        let name = state.friendlyName ?? humanized(state.entityID)
        let fallback = state.domain == "script" ? "play.circle.fill" : "sparkles"
        return HomeScene(
            id: BackendID.make(.homeAssistant, state.entityID),
            name: name,
            backend: .homeAssistant,
            systemImage: SceneSymbol.symbol(icon: state["icon"]?.stringValue, name: name) ?? fallback
        )
    }

    static func camera(from state: HAState, context: Context, doorbellDevices: Set<String> = []) -> HomeCamera {
        let name = displayName(of: state, registry: context.registry)
        let deviceID = context.registry.deviceID(for: state.entityID)
        let isDoorbell = deviceID.map(doorbellDevices.contains) ?? false || name.localizedCaseInsensitiveContains("doorbell")
        // The camera's rotating access token lets other modules load these URLs without a header.
        let token = state["access_token"]?.stringValue
        func url(_ path: String) -> URL? {
            guard let base = context.baseURL, var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
            components.path = "/api/\(path)/\(state.entityID)"
            if let token { components.queryItems = [URLQueryItem(name: "token", value: token)] }
            return components.url
        }
        return HomeCamera(
            id: BackendID.make(.homeAssistant, state.entityID),
            name: name,
            room: context.registry.roomName(for: state.entityID),
            backend: .homeAssistant,
            isDoorbell: isDoorbell,
            streamURL: url("camera_proxy_stream"),
            snapshotURL: url("camera_proxy")
        )
    }

    /// The registry name the person set, then the friendly name, then the object ID.
    static func displayName(of state: HAState, registry: HARegistry) -> String {
        registry.entities[state.entityID]?.name ?? state.friendlyName ?? humanized(state.entityID)
    }

    /// `light.kitchen_ceiling` becomes "Kitchen Ceiling".
    static func humanized(_ entityID: String) -> String {
        let object = entityID.split(separator: ".", maxSplits: 1).last.map(String.init) ?? entityID
        return object.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func byName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.localizedStandardCompare(rhs) == .orderedAscending
    }
}
