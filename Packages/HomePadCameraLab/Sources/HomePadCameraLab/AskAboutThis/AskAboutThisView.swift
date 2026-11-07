import HomePadCore
import HomePadUI
import SwiftUI

/// Point the back camera at something, ask by voice or by typing, and read
/// the answer in big type.
struct AskAboutThisView: View {
    @Environment(CameraLab.self) private var lab
    @State private var model = AskAboutThisModel()
    @State private var listener = SpokenQuestionListener()
    @State private var access: CameraBroker.Access?
    @State private var captureProblem: String?

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.l) {
            picture
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            AskPanel(model: model, listener: listener)
                .frame(width: 480)
        }
        .padding([.horizontal, .bottom], Theme.Spacing.l)
        .holdsCamera(AskAboutThisModel.owner, title: CameraLabTool.ask.title, access: $access)
        .onDisappear {
            listener.cancel()
            model.retake(lab: lab)
        }
    }

    @ViewBuilder
    private var picture: some View {
        if let still = model.still {
            Image(uiImage: still)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                .overlay(alignment: .bottom) { controls }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .nightModeAware()
        } else if case .denied(let reason) = access {
            GlassTile {
                EmptyStateView("Camera Unavailable", message: reason, systemImage: "video.slash")
                    .overlay(alignment: .bottom) { PhotoPickerButton(title: "Choose Photo", prominent: true, onImage: model.use(photo:)).padding(Theme.Spacing.m) }
            }
        } else {
            CameraViewport { VStack { Spacer(); controls } }
        }
    }

    private var controls: some View {
        HStack(alignment: .center) {
            PhotoPickerButton(title: "Choose Photo", onImage: model.use(photo:))
                .controlSize(.large)
                .fixedSize()
            Spacer()
            if model.still == nil {
                GlassIconButton("camera.fill", label: "Freeze Picture", size: Theme.Size.heroControl, tint: .white) {
                    Task { await freeze() }
                }
            } else {
                GlassIconButton("arrow.counterclockwise", label: "Back to Camera", size: Theme.Size.heroControl) {
                    model.retake(lab: lab)
                }
            }
            Spacer()
            if let captureProblem {
                Text(captureProblem).font(.callout).padding(Theme.Spacing.s).glassEffect(.regular, in: Capsule())
            } else {
                Color.clear.frame(width: 160, height: 1)
            }
        }
        .padding(Theme.Spacing.l)
    }

    private func freeze() async {
        do {
            try await model.capture(with: lab)
            captureProblem = nil
        } catch {
            captureProblem = error.localizedDescription
        }
    }
}

/// The question input (examples, typing, voice) and the streamed answer.
private struct AskPanel: View {
    @Environment(CameraLab.self) private var lab
    @Bindable var model: AskAboutThisModel
    let listener: SpokenQuestionListener

    var body: some View {
        GlassPanel(padding: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if model.askedQuestion.isEmpty {
                    SectionHeader("Try Asking", systemImage: "sparkles")
                    SuggestionChips(AskAboutThisModel.examples) { model.ask($0, lab: lab) }
                } else {
                    Text(model.askedQuestion)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                    answer
                }
                Spacer(minLength: 0)
                if let problem = listener.problem {
                    Label(problem, systemImage: "mic.slash").font(.callout).foregroundStyle(.orange)
                }
                inputRow
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var answer: some View {
        switch model.phase {
        case .asking where model.answer.isEmpty:
            HStack(spacing: Theme.Spacing.s) {
                ProgressView()
                Text("Looking with \(lab.services.assistant.activeProviderName)").foregroundStyle(.secondary)
            }
            .font(.title3)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.title3).foregroundStyle(.orange)
        default:
            ScrollView {
                Text(model.answer)
                    .font(.title.weight(.regular))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var inputRow: some View {
        HStack(spacing: Theme.Spacing.s) {
            TextField(listener.isListening ? "Listening" : "Ask about what the camera sees", text: listener.isListening ? .constant(listener.transcript) : $model.question)
                .font(.title3)
                .submitLabel(.send)
                .onSubmit { model.ask(model.question, lab: lab) }
                .padding(.horizontal, Theme.Spacing.m)
                .frame(height: 56)
                .glassEffect(.regular, in: Capsule())
            GlassIconButton(
                listener.isListening ? "stop.fill" : "mic.fill",
                label: listener.isListening ? "Stop Listening" : "Ask Out Loud",
                tint: listener.isListening ? .red : .yellow
            ) {
                if listener.isListening {
                    listener.finish()
                } else {
                    Task { await listener.start(services: lab.services) { model.ask($0, lab: lab) } }
                }
            }
        }
    }
}
