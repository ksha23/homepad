import AppIntents
import Foundation
import HomePadCore

/// "Ask HomePad ..." sends the question to whichever AI provider HomePad uses
/// and reads the answer back.
public struct AskHomePadIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ask HomePad"
    public static let description = IntentDescription("Ask HomePad's assistant a question and get the answer back.")

    public init() {}

    @Parameter(title: "Question", requestValueDialog: "What would you like to ask?")
    public var prompt: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Ask HomePad \(\.$prompt)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let context = try IntentContext.current()
        let request = AssistantRequest(text: prompt, speakResponse: false, presentInOverlay: context.runtime.isHomePad)
        var answer = ""
        for try await event in context.services.assistant.ask(request) {
            switch event {
            case .textDelta(let delta): answer += delta
            case .finished(let fullText): answer = fullText
            default: break
            }
        }
        if answer.isEmpty { answer = "HomePad did not have an answer." }
        context.services.events.post(.handoffAssistant(prompt: prompt, answer: answer))
        return .result(value: answer, dialog: "\(answer)")
    }
}

/// "Announce dinner is ready" over intercom, to every room or one.
public struct AnnounceIntent: AppIntent {
    public static let title: LocalizedStringResource = "Announce"
    public static let description = IntentDescription("Speak an announcement on your HomePads.")

    public init() {}

    @Parameter(title: "Message", requestValueDialog: "What should HomePad announce?")
    public var message: String

    @Parameter(title: "Room", optionsProvider: RoomOptions())
    public var room: String?

    public static var parameterSummary: some ParameterSummary {
        Summary("Announce \(\.$message) in \(\.$room)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentContext.current()
        do {
            try await context.services.intercom.announce(text: message, audio: nil, to: room)
        } catch {
            throw ConnectIntentError.noHomePad
        }
        return .result(dialog: "Announced to \(room ?? "every room").")
    }

    struct RoomOptions: DynamicOptionsProvider {
        @MainActor
        func results() async throws -> [String] {
            ConnectRuntime.current?.link.homePads.map(\.name) ?? []
        }
    }
}

/// Starts a timer on the HomePad (from a companion: on every HomePad).
public struct StartTimerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Start Timer"
    public static let description = IntentDescription("Start a timer on HomePad.")

    public init() {}

    @Parameter(title: "Duration", defaultUnit: .minutes, requestValueDialog: "For how long?")
    public var duration: Measurement<UnitDuration>

    @Parameter(title: "Label", default: "Timer")
    public var label: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$duration) timer called \(\.$label)")
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let seconds = duration.converted(to: .seconds).value
        guard seconds > 0 else { throw ConnectIntentError.failed("Pick a duration longer than zero.") }
        try await IntentContext.current().perform(.startTimer(seconds: seconds, label: label))
        let spoken = Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
        return .result(dialog: "\(label) set for \(spoken).")
    }
}

/// Opens the cameras on the HomePad.
public struct ShowCamerasIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Cameras"
    public static let description = IntentDescription("Show your home cameras on HomePad.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = try IntentContext.current()
        let appID = cameraAppID(context)
        try await context.perform(.openApp(id: appID))
        return .result(dialog: "Here are your cameras.")
    }

    /// "cameras", which opens the Home app on its cameras (older HomePads had a
    /// Cameras app under that ID). The Home app when neither is known.
    @MainActor
    private func cameraAppID(_ context: IntentContext) -> String {
        let known = context.runtime.isHomePad
            ? context.runtime.registry.apps.map(\.id) + context.runtime.registry.redirects.map(\.id)
            : context.runtime.remote.statuses.values.flatMap(\.apps).map(\.id)
        return known.contains("cameras") || known.contains("home") ? "cameras" : "home"
    }
}
