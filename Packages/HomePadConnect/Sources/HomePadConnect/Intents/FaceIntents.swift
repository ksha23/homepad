import AppIntents
import Foundation
import HomePadCore

/// An always-on face ("Photos", "Night").
public struct FaceEntity: AppEntity, Identifiable {
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Face"
    public static let defaultQuery = FaceQuery()

    public let id: String
    public let title: String
    public let systemImage: String

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", image: .init(systemName: systemImage))
    }
}

public struct FaceQuery: EntityStringQuery {
    public init() {}

    @MainActor
    public func entities(for identifiers: [FaceEntity.ID]) async throws -> [FaceEntity] {
        await faces().filter { identifiers.contains($0.id) }
    }

    @MainActor
    public func entities(matching string: String) async throws -> [FaceEntity] {
        await faces().filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    public func suggestedEntities() async throws -> [FaceEntity] {
        await faces()
    }

    /// The registry's faces on a HomePad. On a companion, faces the HomePads reported.
    @MainActor
    private func faces() async -> [FaceEntity] {
        guard let runtime = ConnectRuntime.current else { return [] }
        if runtime.isHomePad {
            return runtime.registry.faces.map { FaceEntity(id: $0.id, title: $0.title, systemImage: $0.systemImage) }
        }
        if runtime.remote.statuses.isEmpty {
            await runtime.remote.refresh()
            try? await Task.sleep(for: .milliseconds(600))
        }
        var seen = Set<String>()
        return runtime.remote.statuses.values.flatMap(\.faces)
            .filter { seen.insert($0.id).inserted }
            .map { FaceEntity(id: $0.id, title: $0.title, systemImage: $0.systemImage) }
    }
}

/// "Show the Photos face on HomePad."
public struct SetFaceIntent: AppIntent {
    public static let title: LocalizedStringResource = "Set Face"
    public static let description = IntentDescription("Switch HomePad to one of its faces.")

    public init() {}

    @Parameter(title: "Face")
    public var face: FaceEntity

    public static var parameterSummary: some ParameterSummary {
        Summary("Show the \(\.$face) face")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        try await IntentContext.current().perform(.showFace(id: face.id))
        return .result(dialog: "Showing \(face.title).")
    }
}
