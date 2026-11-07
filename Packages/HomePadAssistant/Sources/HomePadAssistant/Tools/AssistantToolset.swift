import Foundation
import HomePadCore

/// The generic tools the assistant registers. Other modules add their own
/// domain tools to the registry, and the engine offers all of them.
enum AssistantToolset {
    static func make(_ context: ToolContext) -> [AssistantTool] {
        HomeTools.make(context) + InfoTools.make(context) + PersonalTools.make(context)
            + TimerTools.make(context) + MediaTools.make(context) + SystemTools.make(context)
    }

    /// Tools that ask their own precise confirmation questions.
    static let selfConfirming: Set<String> = ["control_device"]
}
