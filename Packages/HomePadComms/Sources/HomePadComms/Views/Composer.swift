import HomePadCore
import PhotosUI
import HomePadUI
import SwiftUI

/// The text entry bar: a "+" button and a rounded field that grows to five lines, with a
/// send button that appears once there is text. Return sends from either keyboard and
/// Shift-Return starts a new line.
struct Composer: View {
    @Binding var text: String
    let onSend: () -> Void
    /// Called with photos or videos chosen from the library.
    let onPick: ([PhotosPickerItem]) -> Void
    @Environment(AppServices.self) private var services
    @FocusState private var focused: Bool
    @State private var picked: [PhotosPickerItem] = []
    /// Set while Shift-Return is down, so the new line it types is kept instead of sent.
    @State private var keepsNewline = false

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // The picker browses the iPad's whole library, so only its owner gets it (`PhotoAccessPolicy`).
            if services.photoAccess.allowsLibrary {
                PhotosPicker(selection: $picked, maxSelectionCount: 10, matching: .any(of: [.images, .videos])) {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(width: 40, height: 40)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Send photos")
                .accessibilityIdentifier("composer-photos")
                .onChange(of: picked) { _, items in
                    guard !items.isEmpty else { return }
                    onPick(items)
                    picked = []
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                TextField("iMessage", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .padding(.leading, 16)
                    .padding(.vertical, 10)
                    .onKeyPress(.return, phases: .down) { press in
                        keepsNewline = press.modifiers.contains(.shift)
                        return .ignored
                    }
                    // Return on the on-screen keyboard types a new line, so a trailing one means "send".
                    .onChange(of: text) { _, value in
                        guard value.hasSuffix("\n") else { return }
                        if keepsNewline { keepsNewline = false; return }
                        text = String(value.dropLast())
                        if canSend { onSend() }
                    }
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Color.blue, in: Circle())
                }
                .opacity(canSend ? 1 : 0)
                .disabled(!canSend)
                .padding(.trailing, 5)
                .padding(.bottom, 5)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("composer-send")
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
