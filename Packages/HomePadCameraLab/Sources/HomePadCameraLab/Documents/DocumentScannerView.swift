import HomePadCore
import HomePadUI
import SwiftUI
import VisionKit

/// Scans recipe cards into the Kitchen module, flyers, invitations and school
/// letters into calendar events, or any document into text to copy.
struct DocumentScannerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case recipe
        case events
        case text

        var id: String { rawValue }

        var title: String {
            switch self {
            case .recipe: "Recipe Card"
            case .events: "Calendar Events"
            case .text: "Copy Text"
            }
        }

        var explanation: String {
            switch self {
            case .recipe: "Scan a recipe card or a cookbook page. HomePad reads it and sends it to Kitchen."
            case .events: "Scan a flyer, an invitation or a school letter. HomePad finds the dates on this iPad, and you choose what goes in your calendar."
            case .text: "Scan a letter, a manual or a label, then copy or share the text."
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case recognizing
        case result
        case failed(String)
    }

    /// The Kitchen module imports recipes posted with this event name.
    static let recipeImportEvent = "kitchen.importRecipeText"
    private static let owner = "cameralab.documents"

    @Environment(AppServices.self) private var services
    @Environment(CameraLab.self) private var lab
    @State private var mode: Mode = .recipe
    @State private var phase: Phase = .idle
    @State private var text = ""
    @State private var pages: [UIImage] = []
    @State private var showingCamera = false
    @State private var cameraProblem: String?
    @State private var sentToKitchen = false
    /// The events found in the text, while the review sheet is open.
    @State private var review: EventScanReview?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            // Chips rather than a segmented control, so each mode is a walk-up target.
            ChoiceChips(Mode.allCases.map { .init(id: $0, title: $0.title) }, selection: $mode)
                .accessibilityLabel("Mode")

            HStack(alignment: .top, spacing: Theme.Spacing.l) {
                sourcePanel.frame(width: 380)
                resultPanel.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding([.horizontal, .bottom], Theme.Spacing.l)
        .sheet(isPresented: $showingCamera, onDismiss: { lab.broker.release(Self.owner) }) {
            DocumentCameraSheet(onFinish: { images in
                showingCamera = false
                recognize(images)
            }, onCancel: { showingCamera = false })
            .ignoresSafeArea()
            .preferredColorScheme(.dark)
        }
        .sheet(item: $review) { review in
            EventReviewSheet(review: review)
        }
        .onChange(of: mode) { sentToKitchen = false }
        #if DEBUG
        .onAppear(perform: showDemoFlyerIfAsked)
        #endif
    }

    /// Finds the events in the text on this iPad and opens them for review.
    private func findEvents() {
        let found = EventScanReview(services: services)
        found.load(text)
        review = found
    }

    #if DEBUG
    /// `-CameraLabDemoFlyer YES` reads a sample invitation as if it were
    /// scanned, for simulator screenshots of the review.
    private func showDemoFlyerIfAsked() {
        guard UserDefaults.standard.bool(forKey: "CameraLabDemoFlyer"), phase == .idle else { return }
        mode = .events
        text = DemoFlyer.text
        phase = .result
        findEvents()
    }
    #endif

    private var sourcePanel: some View {
        GlassPanel(padding: Theme.Spacing.l) { sources.controlSize(.large) }
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(mode.explanation)
                .font(.title3)
                .foregroundStyle(.secondary)
            if lab.capabilities.supportsDocumentCamera {
                Button(action: openCamera) {
                    Label("Scan with Camera", systemImage: "doc.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
            }
            PhotoPickerButton(title: "Choose Photo", prominent: !lab.capabilities.supportsDocumentCamera) { image in
                recognize([image])
            }
            if let cameraProblem {
                Label(cameraProblem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            if !pages.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(pages.indices, id: \.self) { index in
                            Image(uiImage: pages[index]).resizable().scaledToFill()
                                .frame(width: 110, height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var resultPanel: some View {
        switch phase {
        case .idle:
            GlassTile {
                EmptyStateView("Nothing Scanned Yet", message: "The recognized text appears here for you to check and edit.", systemImage: "text.viewfinder")
            }
        case .recognizing:
            GlassTile { ProgressView("Reading the page").controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity) }
        case .failed(let message):
            GlassTile { EmptyStateView("Could Not Read It", message: message, systemImage: "exclamationmark.triangle") }
        case .result:
            RecognizedTextEditor(text: $text, mode: mode, sentToKitchen: sentToKitchen, sendToKitchen: sendToKitchen,
                                 findEvents: findEvents)
        }
    }

    private func openCamera() {
        if case .denied(let reason) = lab.broker.acquire(Self.owner, title: "Document Scanner", camera: .back, usesSystemCapture: true) {
            cameraProblem = reason
            return
        }
        cameraProblem = nil
        showingCamera = true
    }

    private func recognize(_ images: [UIImage]) {
        let cgImages = images.compactMap(\.cgImage)
        guard !cgImages.isEmpty else { return }
        pages = images
        phase = .recognizing
        sentToKitchen = false
        Task {
            do {
                let recognized = try await DocumentTextRecognizer.text(from: cgImages)
                text = recognized
                phase = recognized.isEmpty ? .failed("No text was found. Try more light, or hold the page flat.") : .result
                if mode == .events, !recognized.isEmpty { findEvents() }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    private func sendToKitchen() {
        services.events.post(.custom(name: Self.recipeImportEvent, payload: .string(text)))
        sentToKitchen = true
    }
}

/// The editable recognized text with the actions for the current mode.
private struct RecognizedTextEditor: View {
    @Binding var text: String
    let mode: DocumentScannerView.Mode
    let sentToKitchen: Bool
    let sendToKitchen: () -> Void
    /// Finds the events in the text, as edited, and opens them for review.
    let findEvents: () -> Void
    @State private var copied = false

    var body: some View {
        GlassPanel(padding: Theme.Spacing.l) { editor }
            .onChange(of: text) { copied = false }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            TextEditor(text: $text)
                .font(.title3)
                .scrollContentBackground(.hidden)
                .padding(Theme.Spacing.m)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            // Side by side when the panel is wide enough, and stacked in the
            // narrow panel portrait leaves, where a row wrapped each title a
            // letter to a line.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.m) { actions }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) { actions }
            }
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private var actions: some View {
        if mode == .recipe {
            Button(action: sendToKitchen) {
                Label(sentToKitchen ? "Sent to Kitchen" : "Send to Kitchen", systemImage: sentToKitchen ? "checkmark" : "fork.knife")
            }
            .buttonStyle(.glassProminent)
            .disabled(sentToKitchen || text.isEmpty)
        }
        if mode == .events {
            Button(action: findEvents) {
                Label("Find Events", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.glassProminent)
            .disabled(text.isEmpty)
        }
        Button {
            UIPasteboard.general.string = text
            copied = true
        } label: {
            Label(copied ? "Copied" : "Copy Text", systemImage: copied ? "checkmark" : "doc.on.doc")
        }
        .glassButtonStyle(isProminent: mode == .text)
        ShareLink(item: text) { Label("Share", systemImage: "square.and.arrow.up") }
            .buttonStyle(.glass)
    }
}
