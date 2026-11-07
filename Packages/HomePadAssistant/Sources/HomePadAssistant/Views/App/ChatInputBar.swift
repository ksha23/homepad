import HomePadCore
import HomePadUI
import PhotosUI
import SwiftUI

/// Type a request, attach a photo, or switch to voice.
struct ChatInputBar: View {
    let runtime: AssistantRuntime
    @Environment(AppServices.self) private var services
    @State private var draft = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: Data?
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.m) {
            // The picker browses the iPad's whole library, so only its owner gets it (`PhotoAccessPolicy`).
            if services.photoAccess.allowsLibrary {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Attach Photo", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.glassIcon())
                .accessibilityLabel("Attach Photo")
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                if let photo {
                    attachment(photo)
                }
                TextField("Ask anything", text: $draft, axis: .vertical)
                    .font(.title3)
                    .lineLimit(1...4)
                    .focused($isFocused)
                    .submitLabel(.send)
                    .onSubmit(send)
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.vertical, Theme.Spacing.m)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))

            if draft.trimmingCharacters(in: .whitespaces).isEmpty, photo == nil {
                GlassIconButton("mic.fill", label: "Speak") { runtime.startListening() }
            } else {
                GlassIconButton("arrow.up", label: "Send", tint: AssistantPalette.accent, action: send)
            }
        }
        .onChange(of: photoItem) {
            Task { await loadPhoto() }
        }
    }

    private func attachment(_ data: Data) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            PhotoThumbnail(data: data, side: 64)
            GlassIconButton("xmark", label: "Remove Photo", size: Theme.Size.toolbarItem) {
                photo = nil
                photoItem = nil
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || photo != nil else { return }
        let request = AssistantRequest(
            text: text.isEmpty ? "What is in this photo?" : text, images: photo.map { [$0] } ?? [],
            speakResponse: false, presentInOverlay: false
        )
        runtime.submit(request, isVoice: false)
        draft = ""
        photo = nil
        photoItem = nil
        isFocused = false
    }

    /// Shrinks the picked photo away from the main thread. A full camera photo
    /// takes a noticeable moment to decode and redraw.
    private func loadPhoto() async {
        guard let item = photoItem, let data = try? await item.loadTransferable(type: Data.self) else { return }
        photo = await Task.detached(priority: .userInitiated) { ImageDownscaler.jpeg(from: data) }.value
    }
}
