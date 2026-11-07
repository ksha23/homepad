import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// Adds the "Save to Files" sheet and the result alert for a `MediaSaver`.
    func mediaSaving(_ saver: MediaSaver) -> some View {
        modifier(MediaSavingModifier(saver: saver))
    }
}

private struct MediaSavingModifier: ViewModifier {
    @Bindable var saver: MediaSaver

    func body(content: Content) -> some View {
        content
            .fileExporter(isPresented: $saver.isExporting, documents: saver.exportFiles, contentType: .data) { saver.finishExport($0) }
            .alert("Messages", isPresented: Binding(get: { saver.notice != nil }, set: { if !$0 { saver.notice = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saver.notice ?? "")
            }
    }
}
