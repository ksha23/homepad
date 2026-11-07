import HomePadUI
import SwiftUI
import UIKit

/// A horizontal strip of recent motion snapshots. Tapping one opens it large.
struct MotionSnapshotStrip: View {
    @Environment(CameraLab.self) private var lab
    @State private var selected: MotionSnapshot?

    var body: some View {
        let snapshots = lab.security.snapshots
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader("Recent Motion", systemImage: "photo.stack")
            if snapshots.isEmpty {
                Text("Snapshots of confirmed motion appear here.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            } else {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Theme.Spacing.m) {
                        ForEach(snapshots) { snapshot in
                            Button { selected = snapshot } label: {
                                SnapshotThumbnail(url: lab.security.url(for: snapshot), snapshot: snapshot)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .frame(height: 150)
            }
        }
        .sheet(item: $selected) { snapshot in
            SnapshotViewer(url: lab.security.url(for: snapshot), snapshot: snapshot)
        }
    }
}

/// One snapshot, loaded off the main thread as a small thumbnail.
struct SnapshotThumbnail: View {
    let url: URL
    let snapshot: MotionSnapshot
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.primary.opacity(0.08)
                }
            }
            .frame(width: 240, height: 135)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            HStack(spacing: Theme.Spacing.xs) {
                if snapshot.personDetected { Image(systemName: "figure.stand") }
                Text(snapshot.date, format: .dateTime.hour().minute())
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .glassEffect(.regular, in: Capsule())
            .padding(Theme.Spacing.s)
        }
        .task(id: url) {
            image = await Task.detached(priority: .utility) {
                UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 480, height: 270))
            }.value
        }
        .accessibilityLabel(snapshot.personDetected ? "Person detected" : "Motion")
        .accessibilityValue(snapshot.date.formatted(date: .abbreviated, time: .shortened))
    }
}

/// A full snapshot in a sheet, with share. The picture is decoded once, off the
/// main thread, instead of from disk on every redraw of the sheet.
struct SnapshotViewer: View {
    let url: URL
    let snapshot: MotionSnapshot
    @State private var image: UIImage?
    @State private var isMissing = false

    var body: some View {
        SheetScreen(snapshot.date.formatted(.dateTime.month().day().hour().minute())) {
            ShareLink(item: url) { Label("Share Snapshot", systemImage: "square.and.arrow.up") }
                .buttonStyle(.glassIcon())
                .headerItem()
        } content: {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                } else if isMissing {
                    EmptyStateView("Snapshot Missing", message: "This snapshot was removed.", systemImage: "photo.badge.exclamationmark")
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: url) {
                let loaded = await Task.detached(priority: .userInitiated) {
                    UIImage(contentsOfFile: url.path)?.preparingForDisplay()
                }.value
                image = loaded
                isMissing = loaded == nil
            }
            .padding([.horizontal, .bottom], Theme.Spacing.l)
        }
        .preferredColorScheme(.dark)
    }
}
