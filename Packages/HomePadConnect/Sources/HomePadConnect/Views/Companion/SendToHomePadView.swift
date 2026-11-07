import HomePadCore
import HomePadShareKit
import HomePadUI
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// "Send to HomePad" from the companion: a link or recipe, a photo, or a note.
struct SendToHomePadView: View {
    @Environment(ConnectRuntime.self) private var connect
    @State private var targetID: String?
    @State private var link = ""
    @State private var isRecipe = false
    @State private var note = ""
    @State private var photo: PhotosPickerItem?
    @State private var result: String?
    @State private var isSending = false

    var body: some View {
        Form {
            Section {
                Picker("Send To", selection: $targetID) {
                    Text("All HomePads").tag(String?.none)
                    ForEach(connect.link.homePads) { Text($0.name).tag(Optional($0.id)) }
                }
            } footer: {
                if connect.link.household == nil {
                    Text("Pair with a HomePad first, in the HomePads tab.")
                }
            }

            Section("Link or Recipe") {
                HStack {
                    TextField("https://", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: link) { _, text in
                            if let url = URL(string: text) { isRecipe = SharedItem.classify(url) == .recipe }
                        }
                    PasteButton(payloadType: URL.self) { urls in
                        if let url = urls.first { link = url.absoluteString }
                    }
                    .labelStyle(.iconOnly)
                    .buttonBorderShape(.capsule)
                }
                Toggle("Open in Kitchen as a Recipe", isOn: $isRecipe)
                Button("Send Link", systemImage: "paperplane.fill", action: sendLink)
                    .disabled(URL(string: link)?.scheme?.hasPrefix("http") != true || isSending)
            }

            Section("Photo") {
                PhotosPicker(selection: $photo, matching: .images, photoLibrary: .shared()) {
                    Label("Choose a Photo to Send", systemImage: "photo.on.rectangle")
                }
                .onChange(of: photo) { _, item in
                    if let item { sendPhoto(item) }
                }
            }

            Section("Note") {
                TextField("Leave a note on the HomePad", text: $note, axis: .vertical)
                    .lineLimit(2...6)
                Button("Send Note", systemImage: "text.bubble.fill", action: sendNote)
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
            }

            if let result {
                Section { Label(result, systemImage: result.hasPrefix("Sent") ? "checkmark.circle.fill" : "exclamationmark.triangle.fill") }
            }
        }
        .navigationTitle("Send to HomePad")
    }

    private var sender: String { connect.link.identity.name }

    private func sendLink() {
        guard let url = URL(string: link) else { return }
        send(SharedItem(kind: isRecipe ? .recipe : .link, url: url, senderName: sender, targetID: targetID), image: nil) {
            link = ""
        }
    }

    private func sendNote() {
        send(SharedItem(kind: .text, text: note, senderName: sender, targetID: targetID), image: nil) {
            note = ""
        }
    }

    private func sendPhoto(_ item: PhotosPickerItem) {
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self), let jpeg = Self.downsampledJPEG(data) else {
                result = "That photo could not be read."
                return
            }
            send(SharedItem(kind: .photo, senderName: sender, targetID: targetID), image: jpeg) {
                photo = nil
            }
        }
    }

    private func send(_ item: SharedItem, image: Data?, onSuccess: @escaping () -> Void) {
        isSending = true
        result = nil
        Task {
            let delivered = await connect.sharing.send(item, image: image, to: item.targetID)
            let name = item.targetID.flatMap { connect.link.peer($0)?.name } ?? "your HomePads"
            result = delivered ? "Sent to \(name)." : "Could not reach \(name). Make sure you are on the same Wi-Fi."
            if delivered { onSuccess() }
            isSending = false
        }
    }

    /// Scales a photo down to at most 2048 pixels and re-encodes it as JPEG.
    static func downsampledJPEG(_ data: Data, maxPixels: Int = 2048) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
    }
}
