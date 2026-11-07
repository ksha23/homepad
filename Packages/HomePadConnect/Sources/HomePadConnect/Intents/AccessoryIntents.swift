import AppIntents
import Foundation
import HomePadCore

/// A light, lock, fan, shade or other accessory HomePad controls.
public struct AccessoryEntity: AppEntity, Identifiable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Accessory"
    public static let defaultQuery = AccessoryQuery()

    public let id: String
    public let name: String
    public let room: String?
    public let systemImage: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: room.map { "\($0)" }, image: .init(systemName: systemImage))
    }

    init(_ accessory: HomeAccessory) {
        self.init(accessory, savedID: accessory.id)
    }

    /// This HomePad's accessory under the ID a shortcut saved, which may be
    /// another HomePad's HomeKit ID (`SmartHomeService.localID(for:)`).
    init(_ accessory: HomeAccessory, savedID: String) {
        id = savedID
        name = accessory.name
        room = accessory.room
        systemImage = accessory.kind.systemImage
    }
}

public struct AccessoryQuery: EntityStringQuery {
    public init() {}

    /// A shortcut made on another HomePad names that HomePad's HomeKit IDs.
    /// Each answers under the ID asked for, with this HomePad's accessory.
    @MainActor
    public func entities(for identifiers: [AccessoryEntity.ID]) async throws -> [AccessoryEntity] {
        guard let smartHome = AppServices.current?.smartHome else { return [] }
        return identifiers.compactMap { id in
            smartHome.accessory(id).map { AccessoryEntity($0, savedID: id) }
        }
    }

    @MainActor
    public func entities(matching string: String) async throws -> [AccessoryEntity] {
        guard let smartHome = AppServices.current?.smartHome else { return [] }
        return smartHome.findAccessories(matching: string).map(AccessoryEntity.init)
    }

    @MainActor
    public func suggestedEntities() async throws -> [AccessoryEntity] {
        guard let smartHome = AppServices.current?.smartHome else { return [] }
        let favorites = smartHome.favorites
        return (favorites.isEmpty ? smartHome.accessories : favorites).map(AccessoryEntity.init)
    }
}

/// What to do to an accessory.
public enum AccessoryAction: String, AppEnum {
    case turnOn, turnOff, toggle, lock, unlock, open, close

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Action"
    public static let caseDisplayRepresentations: [AccessoryAction: DisplayRepresentation] = [
        .turnOn: "Turn On", .turnOff: "Turn Off", .toggle: "Toggle", .lock: "Lock",
        .unlock: "Unlock", .open: "Open", .close: "Close",
    ]

    var command: AccessoryCommand {
        switch self {
        case .turnOn: .setPower(true)
        case .turnOff: .setPower(false)
        case .toggle: .toggle
        case .lock: .lock
        case .unlock: .unlock
        case .open: .open
        case .close: .close
        }
    }

    var pastTense: String {
        switch self {
        case .turnOn: "on"
        case .turnOff: "off"
        case .toggle: "toggled"
        case .lock: "locked"
        case .unlock: "unlocked"
        case .open: "open"
        case .close: "closed"
        }
    }
}

/// "Turn on Kitchen Lights with HomePad." Needs an unlocked device, since it can unlock doors.
public struct ControlAccessoryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Control Accessory"
    public static let description = IntentDescription("Turn an accessory on or off, lock or unlock it, or open or close it.")

    public init() {}
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "Accessory")
    public var accessory: AccessoryEntity

    @Parameter(title: "Action", default: .toggle)
    public var action: AccessoryAction

    public static var parameterSummary: some ParameterSummary {
        Summary("\(\.$action) \(\.$accessory)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentContext.current()
        guard context.services.smartHome.accessory(accessory.id) != nil else {
            throw ConnectIntentError.notFound(accessory.name)
        }
        do {
            try await context.services.smartHome.perform(action.command, on: accessory.id)
        } catch {
            throw ConnectIntentError.failed(error.localizedDescription)
        }
        return .result(dialog: "\(accessory.name) is \(action.pastTense).")
    }
}
