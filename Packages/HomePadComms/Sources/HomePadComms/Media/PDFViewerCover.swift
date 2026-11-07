import PDFKit
import SwiftUI

/// A PDF attachment full screen: downloads the original, then shows it with page scrolling and zoom.
struct PDFViewerCover: View {
    @Environment(CommsRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    let attachmentID: String
    let name: String
    @State private var document: PDFDocument?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            Group {
                if let document {
                    PDFKitView(document: document)
                } else if failed {
                    ContentUnavailableView("Cannot open this PDF", systemImage: "doc.badge.ellipsis")
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("viewer-done") } }
        }
        .task {
            if let data = try? await runtime.store.attachments?.original(attachmentID), let loaded = PDFDocument(data: data) { document = loaded } else { failed = true }
        }
    }
}

private struct PDFKitView: UIViewRepresentable {
    let document: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
