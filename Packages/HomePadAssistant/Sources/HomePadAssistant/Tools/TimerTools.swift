import Foundation
import HomePadCore

/// Kitchen and household timers through `services.timers`.
enum TimerTools {
    static func make(_ context: ToolContext) -> [AssistantTool] {
        [start(context), list(context), cancel(context)]
    }

    static func start(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "start_timer",
            description: "Start a timer.",
            parameters: Schema.object([
                "seconds": Schema.number("Duration in seconds, for example 600 for ten minutes."),
                "label": Schema.string("Short name, for example Pasta."),
            ], required: ["seconds"])
        ) { json in
            let args = ToolArguments(json)
            guard let seconds = args.double("seconds"), seconds > 0, seconds <= 86_400 else {
                throw ToolError("A timer needs a duration between one second and one day.")
            }
            let label = args.string("label") ?? "Timer"
            let timer = try context.services.timers.start(duration: seconds, label: label)
            context.emit(CardFactory.timers([timer]))
            return "Started \(label) for \(format(seconds))."
        }
    }

    static func list(_ context: ToolContext) -> AssistantTool {
        AssistantTool(name: "list_timers", description: "List running and paused timers.") { _ in
            let timers = try context.services.timers.timers.filter { $0.status != .finished }
            guard !timers.isEmpty else { return "No timers are running." }
            context.emit(CardFactory.timers(timers))
            return timers.map { "\($0.label): \(format($0.remaining())) left\($0.status == .paused ? ", paused" : "")" }
                .joined(separator: "\n")
        }
    }

    static func cancel(_ context: ToolContext) -> AssistantTool {
        AssistantTool(
            name: "cancel_timer",
            description: "Cancel a timer by its label, or all timers.",
            parameters: Schema.object(["label": Schema.string("The timer's label, or \"all\".")], required: ["label"])
        ) { json in
            let label = try ToolArguments(json).requireString("label")
            let service = try context.services.timers
            let wanted = label.lowercased()
            let matches = wanted == "all" ? service.timers : service.timers.filter { $0.label.lowercased().contains(wanted) }
            guard !matches.isEmpty else { return "No timer named \(label)." }
            matches.forEach { service.cancel($0.id) }
            return matches.count == 1 ? "Canceled \(matches[0].label)." : "Canceled \(matches.count) timers."
        }
    }

    /// "10 minutes", "1 hour 5 minutes", "45 seconds".
    static func format(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : seconds >= 60 ? [.minute, .second] : [.second]
        formatter.unitsStyle = .full
        return formatter.string(from: seconds.rounded()) ?? "\(Int(seconds)) seconds"
    }
}
