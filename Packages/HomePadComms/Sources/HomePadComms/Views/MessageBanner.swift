import CommsKit
import HomePadCore
import HomePadUI
import SwiftUI

/// A banner for a new message, drawn by HomePad itself and only while the
/// message's owner is recognized. Nothing goes to the lock screen.
struct MessageBanner: View {
    @Environment(CommsRuntime.self) private var runtime
    @Environment(\.isOnFace) private var isOnFace

    var body: some View {
        if let message = runtime.store.banner, runtime.services.visibleAppID != "messages" {
            if isOnFace {
                FaceMessageBanner(message: message)
            } else {
                homeBanner(message)
            }
        }
    }

    /// The full banner for the Home Screen and other apps, where only people up close see it.
    private func homeBanner(_ message: CommsMessage) -> some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "message.fill").foregroundStyle(.green)
                VStack(alignment: .leading) {
                    Text(message.senderName ?? message.sender ?? "New message").font(.headline)
                    Text(message.text).font(.subheadline).lineLimit(2)
                }
                Spacer()
            }
            .padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)).padding()
            .onTapGesture {
                runtime.services.events.post(.openApp(id: "messages"))
                runtime.store.dismissBanner()
            }
            .task(id: message.id) {
                try? await Task.sleep(for: .seconds(6))
                if runtime.store.banner?.id == message.id { runtime.store.dismissBanner() }
            }
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Control Center tile with the unread count.
struct MessagesTile: View {
    @Environment(CommsRuntime.self) private var runtime

    var body: some View {
        Button { runtime.services.events.post(.openApp(id: "messages")) } label: {
            VStack {
                Image(systemName: "message.fill").font(.title2)
                Text(runtime.store.unreadTotal > 0 ? "\(runtime.store.unreadTotal) unread" : "Messages").font(.caption)
            }
        }
    }
}
