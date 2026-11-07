import HomePadCore
import HomePadShareKit
import HomePadUI
import SwiftUI

/// Shows what was just sent to this HomePad ("Photo from Kyle's iPhone") with
/// quick actions. Disappears on its own after a minute.
struct ShareOverlay: View {
    @Environment(ConnectRuntime.self) private var connect

    var body: some View {
        VStack {
            if let received = connect.sharing.latest {
                banner(received)
                    .task(id: received.id) {
                        try? await Task.sleep(for: .seconds(60))
                        if connect.sharing.latest?.id == received.id { connect.sharing.dismissLatest() }
                    }
            }
            Spacer()
        }
        .animation(.smooth, value: connect.sharing.latest)
    }

    private func banner(_ received: ShareCenter.Received) -> some View {
        let item = received.item
        return GlassBanner(
            systemImage: item.kind.systemImage,
            tint: item.kind == .recipe ? .orange : .blue,
            title: "\(item.kind.title) from \(item.senderName)",
            subtitle: subtitle(item)
        ) {
            if let url = received.imageURL, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.concentric(in: Theme.Radius.tile, inset: Theme.Spacing.l), style: .continuous))
            }
        } actions: {
            if item.kind == .text, let text = item.text {
                GlassIconButton("pin", label: "Pin to Family Board") {
                    connect.board.add(text, color: .yellow)
                    connect.sharing.dismissLatest()
                }
            }
            if let url = item.url {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.glassIcon())
            }
            CloseButton("Dismiss") { connect.sharing.dismissLatest() }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.top, Theme.Spacing.l)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func subtitle(_ item: SharedItem) -> String? {
        switch item.kind {
        case .recipe: item.title ?? (item.url == nil ? "Added to Kitchen" : "Opening in Kitchen")
        case .link: item.title ?? item.url?.host()
        case .text: item.text
        case .photo: nil
        }
    }
}

/// Holds the Handoff advertising and receiving modifiers. Draws nothing.
struct HandoffAnchor: View {
    @Environment(ConnectRuntime.self) private var connect

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .homePadHandoff(connect.handoff)
    }
}
