import HomePadCore
import HomePadUI
import SwiftUI

/// A photo frame tile rotating through the photo sources from Settings, or
/// the newest photos in the library when those sources are empty.
struct PhotoWidgetView: View {
    @Environment(PhotoLibraryService.self) private var photos
    @Environment(SettingsStore.self) private var settings
    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.displayCondition) private var displayCondition
    let size: WidgetSize
    @State private var list: [PhotoRef] = []
    @State private var hasLoadedList = false
    @State private var index = 0

    var body: some View {
        Group {
            if !hasLoadedList {
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous).fill(.primary.opacity(0.06))
            } else if list.isEmpty {
                GlassTile {
                    Label("Photos", systemImage: "photo.fill").font(.headline)
                    Spacer(minLength: 0)
                    Text(placeholder)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.7)
                }
            } else {
                PhotoView(photo: list[index % list.count], targetSize: CGSize(width: 900, height: 900))
                    .id(index % list.count)
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                    .nightModeAware()
            }
        }
        .task(id: Sources(revision: photos.revision, selection: settings[PersonalSettings.photoSources],
                          isDemo: photos.isUsingDemoData, canShow: photos.canShowPhotos)) {
            photos.loadIfNeeded()
            let loaded = photos.canShowPhotos ? await photos.slideshowPhotos() : []
            guard !Task.isCancelled else { return }
            list = loaded
            hasLoadedList = true
        }
        // Turns to the next photo only where someone can see it: not in a
        // thumbnail, and not while the display sleeps.
        .task(id: Rotation(count: list.count, isPaused: isThumbnail || displayCondition == .sleeping)) {
            guard !isThumbnail, displayCondition != .sleeping, list.count > 1 else { return }
            let interval = max(5, settings[PersonalSettings.slideshowInterval]) * 2
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                withAnimation(.easeInOut(duration: 1.2)) { index += 1 }
            }
        }
    }

    private var placeholder: String {
        if photos.isDenied { return "Photos access is off for HomePad." }
        if !photos.canShowPhotos { return "Open Photos to show your photos here." }
        return "Photos saved on this iPad show here."
    }

    /// What the photo rotation depends on.
    private struct Rotation: Hashable {
        var count: Int
        var isPaused: Bool
    }

    /// What the photo list depends on.
    private struct Sources: Hashable {
        var revision: Int
        var selection: PhotoSourceSelection
        var isDemo: Bool
        var canShow: Bool
    }
}
