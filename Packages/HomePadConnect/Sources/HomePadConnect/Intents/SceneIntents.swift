import AppIntents
import Foundation
import HomePadCore

/// A Home scene ("Good Night") from HomeKit, Home Assistant, or a HomePad's report.
public struct SceneEntity: AppEntity, Identifiable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Scene"
    public static let defaultQuery = SceneQuery()

    public let id: String
    public let name: String
    public let systemImage: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: systemImage))
    }

    init(_ scene: HomeScene) {
        self.init(scene, savedID: scene.id)
    }

    /// The scene under the ID a shortcut saved, which may be another
    /// HomePad's HomeKit ID (`SmartHomeService.localID(for:)`).
    init(_ scene: HomeScene, savedID: String) {
        id = savedID
        name = scene.name
        systemImage = scene.systemImage
    }
}

public struct SceneQuery: EntityStringQuery {
    public init() {}

    /// A shortcut made on another HomePad names that HomePad's HomeKit IDs.
    /// Each answers under the ID asked for, with this HomePad's scene.
    @MainActor
    public func entities(for identifiers: [SceneEntity.ID]) async throws -> [SceneEntity] {
        guard let context = try? IntentContext.current() else { return [] }
        let smartHome = context.services.smartHome
        let scenes = smartHome.scenes + context.runtime.remote.scenes
        return identifiers.compactMap { id in
            let local = smartHome.localID(for: id)
            return scenes.first { $0.id == local }.map { SceneEntity($0, savedID: id) }
        }
    }

    @MainActor
    public func entities(matching string: String) async throws -> [SceneEntity] {
        allScenes().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    public func suggestedEntities() async throws -> [SceneEntity] {
        allScenes()
    }

    /// This device's scenes, plus scenes HomePads reported to a companion.
    @MainActor
    private func allScenes() -> [SceneEntity] {
        guard let context = try? IntentContext.current() else { return [] }
        var seen = Set<String>()
        return (context.services.smartHome.scenes + context.runtime.remote.scenes)
            .filter { seen.insert($0.id).inserted }
            .map(SceneEntity.init)
    }
}

/// "Run Good Night with HomePad."
public struct RunSceneIntent: AppIntent {
    public static let title: LocalizedStringResource = "Run Scene"
    public static let description = IntentDescription("Run one of your Home scenes.")

    public init() {}

    @Parameter(title: "Scene")
    public var scene: SceneEntity

    public static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$scene)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentContext.current()
        let localID = context.services.smartHome.localID(for: scene.id)
        if context.services.smartHome.scenes.contains(where: { $0.id == localID }) {
            do {
                try await context.services.smartHome.activateScene(scene.id)
            } catch {
                throw ConnectIntentError.failed(error.localizedDescription)
            }
        } else {
            try await context.perform(.runScene(id: scene.id))
        }
        return .result(dialog: "\(scene.name) is on.")
    }
}
