import Observation
import Photos
import UIKit

/// Plays a timelapse album like a video by stepping through its photos.
/// Frames load on demand, so long albums do not fill memory.
@MainActor
@Observable
final class TimelapsePlayerModel {
    /// Curated playback speeds, in frames per second.
    static let speeds = [4, 8, 15]

    private(set) var assets: [PHAsset] = []
    private(set) var image: UIImage?
    private(set) var isPlaying = false
    var index = 0 {
        didSet { if oldValue != index { Task { await showFrame() } } }
    }
    var speed = 8

    @ObservationIgnored private let imageManager = PHCachingImageManager()
    @ObservationIgnored private var playback: Task<Void, Never>?
    @ObservationIgnored private let targetSize = CGSize(width: 1600, height: 1600)

    var currentDate: Date? { assets.indices.contains(index) ? assets[index].creationDate : nil }

    func load(album: String) async {
        assets = PhotoAlbumLibrary.assets(inAlbum: album)
        index = max(0, assets.count - 1)
        imageManager.startCachingImages(for: Array(assets.suffix(60)), targetSize: targetSize, contentMode: .aspectFit, options: nil)
        await showFrame()
    }

    func togglePlayback() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        guard assets.count > 1 else { return }
        if index >= assets.count - 1 { index = 0 }
        isPlaying = true
        playback = Task { [weak self] in
            while let self, self.isPlaying, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.0 / Double(self.speed)))
                guard self.index < self.assets.count - 1 else {
                    self.pause()
                    return
                }
                self.index += 1
            }
        }
    }

    func pause() {
        isPlaying = false
        playback?.cancel()
        playback = nil
    }

    private func showFrame() async {
        guard assets.indices.contains(index) else {
            image = nil
            return
        }
        let asset = assets[index]
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        let loaded = await withCheckedContinuation { continuation in
            imageManager.requestImage(for: asset, targetSize: targetSize, contentMode: .aspectFit, options: options) { image, _ in
                continuation.resume(returning: image)
            }
        }
        if assets.indices.contains(index), assets[index] == asset { image = loaded }
    }
}
