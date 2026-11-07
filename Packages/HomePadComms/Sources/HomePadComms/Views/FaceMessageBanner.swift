import CommsKit
import HomePadCore
import HomePadUI
import SwiftUI

/// A new message on the always-on face. The face is read from across the room, so by
/// default it names the sender and says "New message". The text shows only when
/// `comms.showPreviewsOnFace` is on. It fades after a few seconds, and a tap dismisses it.
struct FaceMessageBanner: View {
    /// How long it stays before it starts to fade.
    static let lingerSeconds = 8.0

    let message: CommsMessage
    @Environment(CommsRuntime.self) private var runtime
    @State private var isShown = false

    var body: some View {
        let showsPreview = runtime.services.settings[CommsSettings.showPreviewsOnFace]
        let name = message.senderName ?? message.sender
        VStack {
            Spacer()
            HStack(spacing: 16) {
                Avatar(title: name ?? "", isGroup: false, size: 64, handle: message.sender)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name ?? "New message").font(.title2.weight(.semibold)).lineLimit(1)
                    Text(showsPreview ? message.text : "New message")
                        .font(.title3).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
            .frame(maxWidth: 560, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .padding(.bottom, 48)
            .onTapGesture { runtime.store.dismissBanner() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Dismisses the notification")
        }
        .nightModeAware()
        .opacity(isShown ? 1 : 0)
        .task(id: message.id) {
            withAnimation(.easeOut(duration: 0.4)) { isShown = true }
            try? await Task.sleep(for: .seconds(Self.lingerSeconds))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.6)) { isShown = false }
            try? await Task.sleep(for: .seconds(0.6))
            if !Task.isCancelled, runtime.store.banner?.id == message.id { runtime.store.dismissBanner() }
        }
    }
}
