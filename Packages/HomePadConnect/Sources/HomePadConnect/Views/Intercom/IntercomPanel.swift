import HomePadCore
import HomePadUI
import SwiftUI

/// Push to talk, a room picker and a typed announcement field. Used by the
/// HomePad Intercom app and the iPhone and Mac companion. It reopens on the
/// room it was set to, or Everywhere once that HomePad is out of reach.
struct IntercomPanel: View {
    @Environment(AppServices.self) private var services
    @Environment(ConnectRuntime.self) private var connect
    @AppState(ConnectAppState.intercomTarget) private var savedTarget
    @State private var text = ""
    @State private var sendError: String?
    var buttonDiameter: CGFloat = 260

    private var hub: IntercomHub { connect.intercom }

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            ChoiceChips(targets, selection: Binding(get: { target }, set: { savedTarget = $0 }))
            PushToTalkButton(isActive: hub.isRecording, level: services.microphone.level, diameter: buttonDiameter,
                             onPress: { Task { await hub.startRecording(to: target) } },
                             onRelease: { Task { await hub.finishRecording() } })
            statusLine
            announceField
        }
        .frame(maxWidth: .infinity)
    }

    private var targets: [ChoiceChips<IntercomTarget>.Choice] {
        [.init(id: .everyone, title: "Everywhere", systemImage: "house.fill")]
            + connect.link.homePads.map { .init(id: .device(id: $0.id), title: $0.name, systemImage: "speaker.wave.2.fill") }
    }

    /// The room picked last while that HomePad is reachable, otherwise Everywhere.
    private var target: IntercomTarget {
        savedTarget.reachable(among: connect.link.homePads.map(\.id))
    }

    private var targetName: String {
        targets.first { $0.id == target }?.title ?? "Everywhere"
    }

    @ViewBuilder
    private var statusLine: some View {
        if let error = hub.lastError ?? sendError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        } else if let started = hub.recordingStartedAt {
            TimelineView(.periodic(from: started, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(started))
                let limit = Int(services.settings[ConnectSettings.intercomMaxSeconds])
                Text("Talking to \(targetName)  \(elapsed)s of \(limit)s")
                    .font(.title3.monospacedDigit())
            }
        } else {
            Text("Hold to talk to \(targetName)")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var announceField: some View {
        HStack(spacing: Theme.Spacing.s) {
            TextField("Type an announcement", text: $text)
                .font(.title3)
                .padding(.horizontal, Theme.Spacing.m)
                .frame(height: 52)
                .glassEffect(.regular, in: Capsule())
                .submitLabel(.send)
                .onSubmit(sendText)
            GlassIconButton("arrow.up", label: "Send announcement", tint: .accentColor, action: sendText)
                .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .frame(maxWidth: 560)
    }

    private func sendText() {
        let message = text
        sendError = nil
        Task {
            do {
                try await hub.sendText(message, to: target)
                text = ""
            } catch {
                sendError = error.localizedDescription
            }
        }
    }
}
