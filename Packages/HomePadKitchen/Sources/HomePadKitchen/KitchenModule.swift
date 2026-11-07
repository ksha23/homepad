import HomePadCore
import HomePadUI
import SwiftUI

/// Recipes, cooking mode, timers and wake-up alarms.
///
/// Installs `KitchenTimerService` as `services.timers` and contributes the Timers
/// and Recipes apps, the timer-finished overlay, two widgets, a Control Center
/// tile, the Kitchen settings pane and the recipe assistant tools, plus the
/// Alarms app with its alert, widget and tools (`KitchenAlarms`).
///
/// Other modules hand recipes over with events:
///
///     services.events.post(.custom(name: KitchenModule.importURLEvent, payload: .string(link)))
///     services.events.post(.custom(name: KitchenModule.importTextEvent, payload: .string(scannedText)))
public enum KitchenModule: HomePadModule {
    public static let id = "kitchen"
    public static let timersAppID = "timers"
    public static let recipesAppID = "recipes"
    /// Payload `.string(url)`: import the recipe at that link and open it.
    public static let importURLEvent = "kitchen.importRecipeURL"
    /// Payload `.string(text)`: structure scanned or pasted recipe text and open it.
    public static let importTextEvent = "kitchen.importRecipeText"

    public static func register(services: AppServices, registry: ModuleRegistry) {
        let settings = services.settings
        let alarms = AlarmKitTimerScheduler(isEnabled: { settings[KitchenSettings.backgroundAlarms] })
        services.timers = KitchenTimerService(
            events: services.events, alarms: alarms,
            surfaces: TimerSurfaceSync(liveActivitiesEnabled: { settings[KitchenSettings.liveActivities] }))

        #if DEBUG
        let context = KitchenContext(services: services, catalog: KitchenDebugLaunch.catalog())
        #else
        let context = KitchenContext(services: services)
        #endif
        registerApps(context: context, registry: registry)
        registerSurfaces(context: context, alarms: alarms, registry: registry)
        KitchenAlarms.register(services: services, registry: registry, permission: alarms)
        registry.register(tools: KitchenAssistantTools.make(context: context))
        registry.register(screenContext: RecipeScreenContext.provider(context: context))
        listen(to: services, context: context)
        // The starter recipes and Discover load in the background, after launch work.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            context.prepareRecipes()
        }
        #if DEBUG
        KitchenDebugLaunch.apply(context: context, services: services)
        #endif
    }

    private static func registerApps(context: KitchenContext, registry: ModuleRegistry) {
        registry.register(app: AppDescriptor(
            id: timersAppID, title: "Timers", systemImage: "timer", tint: .orange, category: .kitchen, sortOrder: 40
        ) {
            TimersAppView()
        })
        registry.register(app: AppDescriptor(
            id: recipesAppID, title: "Recipes", systemImage: "fork.knife", tint: .orange, category: .kitchen, sortOrder: 41
        ) {
            RecipesAppView(context: context)
        })
    }

    private static func registerSurfaces(context: KitchenContext, alarms: AlarmKitTimerScheduler, registry: ModuleRegistry) {
        registry.register(overlay: OverlayDescriptor(id: "kitchen.timerFinished", zIndex: 80) {
            TimerFinishedOverlay(context: context)
        })
        // A running timer asks a widget stack to show Timers.
        registry.register(widget: WidgetDescriptor(id: "kitchen.timers", title: "Timers", systemImage: "timer", opensApp: Self.timersAppID,
                                                   relevance: { context in
            context.services.timers.timers.contains { $0.status == .running } ? .timely() : nil
        }) { size in
            RunningTimersWidget(size: size)
        })
        registry.register(widget: WidgetDescriptor(id: "kitchen.recipeOfTheDay", title: "Recipe of the Day", systemImage: "fork.knife") { size in
            RecipeOfTheDayWidget(size: size, context: context)
        })
        registry.register(widget: WidgetDescriptor(id: "kitchen.mealPlan", title: "Meal Plan", systemImage: "calendar",
                                                   supportedSizes: [.small, .medium]) { size in
            MealPlanWidget(size: size, context: context)
        })
        registry.register(control: ControlDescriptor(id: "kitchen.quickTimers", title: "Timers", systemImage: "timer", size: .large, sortOrder: 40) {
            QuickTimersControl()
        })
        registry.register(settings: SettingsPaneDescriptor(id: "kitchen", title: "Kitchen", systemImage: "fork.knife", tint: .yellow, sortOrder: 60) {
            KitchenSettingsPane(context: context, alarms: alarms)
        })
    }

    /// Subscribes synchronously so no event posted after registration is missed.
    private static func listen(to services: AppServices, context: KitchenContext) {
        let stream = services.events.stream()
        Task { @MainActor in
            for await event in stream {
                context.handle(event)
            }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                (services.timers as? KitchenTimerService)?.refresh()
            }
        }
    }
}
