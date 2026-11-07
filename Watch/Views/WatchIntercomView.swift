import SwiftUI

/// Hold the big button to talk to every HomePad, or pick a room first.
struct WatchIntercomView: View {
    @Environment(WatchLink.self) private var link
    @State private var recorder = WatchRecorder()
    @State private var targetID: String?

    var body: some View {
        VStack(spacing: 8) {
            Picker("To", selection: $targetID) {
                Text("Everywhere").tag(String?.none)
                ForEach(link.homePads) { Text($0.name).tag(Optional($0.id)) }
            }
            .pickerStyle(.navigationLink)
            ZStack {
                Circle().fill(recorder.isRecording ? Color.green.gradient : Color.gray.opacity(0.3).gradient)
                Image(systemName: "waveform")
                    .font(.system(size: 40, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: recorder.isRecording)
            }
            .frame(width: 100, height: 100)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !recorder.isRecording else { return }
                        Task { await recorder.start() }
                    }
                    .onEnded { _ in
                        if let clip = recorder.stop() {
                            link.sendIntercom(clip.url, duration: clip.duration, to: targetID)
                        }
                    }
            )
            .accessibilityLabel("Hold to talk")
            Text(recorder.error ?? link.message ?? (recorder.isRecording ? "Release to send" : "Hold to talk"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .navigationTitle("Intercom")
    }
}
