import HomePadShareKit
import HomePadUI
import SwiftUI

/// The share sheet card: a preview, a HomePad picker and Send. Same tokens,
/// sheet header and dark glass look as the app: Send beside the close button.
struct ShareComposeView: View {
    @Bindable var model: ShareComposeModel

    var body: some View {
        SheetScreen("Send to HomePad", onClose: { model.cancel() }) {
            GlassCapsuleButton("Send", isProminent: true) { model.send() }
                .disabled(model.phase != .ready)
        } content: {
            Form {
                Section { preview }
                if model.kind == .link || model.kind == .recipe {
                    Section {
                        Toggle("Open in Kitchen as a Recipe", isOn: Binding(
                            get: { model.kind == .recipe },
                            set: { model.kind = $0 ? .recipe : .link }
                        ))
                    }
                }
                Section {
                    Picker("Send To", selection: $model.targetID) {
                        Text("All HomePads").tag(String?.none)
                        ForEach(model.targets) { Text($0.name).tag(Optional($0.id)) }
                    }
                } footer: {
                    Text(footer)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var preview: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity)
        case .unsupported:
            Label("HomePad can receive links, text and photos.", systemImage: "exclamationmark.triangle")
        case .queued:
            Label("Sent. Your HomePad shows it in a moment.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let reason):
            Label(reason, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .ready:
            HStack(spacing: Theme.Spacing.m) {
                if let image = model.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
                } else {
                    Image(systemName: model.kind.systemImage)
                        .font(.title)
                        .frame(width: 72, height: 72)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.kind.title).font(.headline)
                    Text(model.url?.absoluteString ?? model.text ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
    }

    private var footer: String {
        model.targets.isEmpty
            ? "Open HomePad on this device and pair it with a HomePad to choose one here."
            : "HomePad delivers it over your Wi-Fi as soon as the app can reach the HomePad."
    }
}
