import Foundation

/// A feature package. Each package exposes exactly one type conforming to this,
/// and the app lists them in `App/Sources/Modules.swift`.
///
///     public enum SmartHomeModule: HomePadModule {
///         public static let id = "smarthome"
///         public static func register(services: AppServices, registry: ModuleRegistry) {
///             let service = UnifiedSmartHomeService(services: services)
///             services.smartHome = service
///             registry.register(app: AppDescriptor(id: "home", ...) { HomeAppView() })
///             registry.register(tools: SmartHomeTools.make(services: services))
///         }
///     }
///
/// Rules:
/// - `register` runs once at launch on the main actor, in the order listed in Modules.swift.
/// - Replace a service in `services` only if your module owns that service.
/// - Look up other services lazily (at call time), never cache them in `register`,
///   because a later module may replace them.
/// - Start long-running work with `Task {}` from `register` or from `didFinishLaunching`.
@MainActor
public protocol HomePadModule {
    static var id: String { get }
    static func register(services: AppServices, registry: ModuleRegistry)
    /// Called after every module registered. Safe to read other services here.
    static func didFinishLaunching(services: AppServices, registry: ModuleRegistry)
}

public extension HomePadModule {
    static func didFinishLaunching(services: AppServices, registry: ModuleRegistry) {}
}

/// Boots a list of modules in order.
@MainActor
public enum ModuleLoader {
    public static func load(_ modules: [any HomePadModule.Type], services: AppServices, registry: ModuleRegistry) {
        let log = Log.make("Modules")
        for module in modules {
            module.register(services: services, registry: registry)
            registry.noteModule(module.id)
            log.info("Registered module \(module.id, privacy: .public)")
        }
        for module in modules {
            module.didFinishLaunching(services: services, registry: registry)
        }
    }
}
