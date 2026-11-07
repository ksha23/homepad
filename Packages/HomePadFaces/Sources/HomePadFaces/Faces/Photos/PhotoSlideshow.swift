import CoreGraphics
import Foundation
import HomePadCore
import Observation

/// Drives one Photos face: fetches the photos for its query, processes each
/// one for the depth effect, and advances on a slow interval. Falls back to
/// generated demo scenes when the library is unavailable or empty.
@MainActor
@Observable
final class PhotoSlideshow {
    enum Status: Equatable {
        /// Showing your photos.
        case library
        /// Demo scenes while access has not been asked for yet.
        case needsAccess
        /// Demo scenes because access was denied.
        case denied
        /// Demo scenes because the chosen source has no photos.
        case empty
    }

    private(set) var frame: PhotoFrame?
    private(set) var status: Status = PhotoSlideshow.statusBeforeLoading
    /// Increments on every new slide. Drives the crossfade and Ken Burns direction.
    private(set) var slideNumber = 0
    /// True once the first photo of the current query is in, or there is none to show.
    private(set) var hasLoaded = false

    /// Runs until the calling task is cancelled.
    func run(query: PhotoQuery, interval: TimeInterval, maxPixel: Int, advances: Bool, processor: PhotoDepthProcessor) async {
        hasLoaded = false
        let refs = await loadRefs(for: query)
        guard !refs.isEmpty else {
            hasLoaded = true
            return
        }
        var index = 0
        while !Task.isCancelled {
            let ref = refs[index % refs.count]
            if let next = await processor.frame(for: ref, maxPixel: maxPixel, load: Self.loader(for: ref, maxPixel: maxPixel)),
               !Task.isCancelled {
                frame = next
                slideNumber += 1
            }
            if !Task.isCancelled { hasLoaded = true }
            guard advances, refs.count > 1 else { return }
            let upcoming = refs[(index + 1) % refs.count]
            async let prefetch: PhotoFrame? = processor.frame(for: upcoming, maxPixel: maxPixel,
                                                              load: Self.loader(for: upcoming, maxPixel: maxPixel))
            try? await Task.sleep(for: .seconds(interval))
            _ = await prefetch
            index += 1
        }
    }

    private func loadRefs(for query: PhotoQuery) async -> [PhotoRef] {
        switch PhotoLibrarySource.access {
        case .allowed, .limited:
            let refs = await PhotoLibrarySource.refs(for: query)
            status = refs.isEmpty ? .empty : .library
            return refs.isEmpty ? Self.demoRefs : refs.shuffled()
        case .notAsked:
            status = .needsAccess
            return Self.demoRefs
        case .denied:
            status = .denied
            return Self.demoRefs
        }
    }

    static let demoRefs = (0..<DemoPhotoScenes.count).map { PhotoRef(source: .demo(index: $0), date: nil) }

    /// The status while the photos load, from the access the iPad already
    /// has. Starting at `.needsAccess` flashed the Allow Photos card for the
    /// moment the fetch took, every time the face appeared.
    static var statusBeforeLoading: Status {
        switch PhotoLibrarySource.access {
        case .allowed, .limited: .library
        case .notAsked: .needsAccess
        case .denied: .denied
        }
    }

    private static func loader(for ref: PhotoRef, maxPixel: Int) -> @Sendable () async -> (image: CGImage, mask: CGImage?)? {
        { @Sendable in
            switch ref.source {
            case .demo(let index):
                guard let scene = DemoPhotoScenes.render(index, side: maxPixel) else { return nil }
                return (scene.image, scene.mask)
            case .library(let identifier):
                guard let image = await PhotoLibrarySource.image(localIdentifier: identifier, maxPixel: maxPixel) else { return nil }
                return (image, nil)
            }
        }
    }
}
