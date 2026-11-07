import Foundation
import HomePadShareKit
import ImageIO
import Observation
import UIKit
import UniformTypeIdentifiers

/// Loads what was shared and queues it for the HomePad app to deliver.
@MainActor
@Observable
final class ShareComposeModel {
    enum Phase: Equatable { case loading, ready, unsupported, queued, failed(String) }

    var phase = Phase.loading
    var url: URL?
    var text: String?
    var image: UIImage?
    var kind = SharedItem.Kind.link
    var targetID: String?
    let targets: [ShareOutbox.Target]

    @ObservationIgnored private let context: NSExtensionContext?
    @ObservationIgnored private var imageData: Data?
    @ObservationIgnored private let outbox = ShareOutbox.shared()

    init(extensionContext: NSExtensionContext?) {
        context = extensionContext
        targets = outbox?.targets() ?? []
    }

    func load() async {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL, !loaded.isFileURL {
                url = loaded
                kind = SharedItem.classify(loaded)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                      let data = await Self.imageData(from: provider) {
                imageData = data
                image = UIImage(data: data)
                kind = .photo
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                      let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                text = loaded
                if url == nil && image == nil { kind = .text }
            }
        }
        phase = (url != nil || imageData != nil || text != nil) ? .ready : .unsupported
    }

    func send() {
        guard let outbox else {
            phase = .failed("Open HomePad once on this device, then try again.")
            return
        }
        let item = SharedItem(kind: kind, url: url, text: text, title: kind == .photo ? nil : text,
                              senderName: UIDevice.current.name, targetID: targetID)
        do {
            try outbox.enqueue(item, image: kind == .photo ? imageData : nil)
            ShareOutbox.notifyApp()
            phase = .queued
            Task {
                try? await Task.sleep(for: .seconds(1))
                context?.completeRequest(returningItems: nil)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func cancel() {
        context?.cancelRequest(withError: CocoaError(.userCancelled))
    }

    /// Loads an image attachment and scales it to at most 2048 pixels as JPEG.
    private static func imageData(from provider: NSItemProvider) async -> Data? {
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
        let raw: Data? = switch item {
        case let data as Data: data
        case let url as URL: try? Data(contentsOf: url)
        case let image as UIImage: image.jpegData(compressionQuality: 0.9)
        default: nil
        }
        guard let raw, let source = CGImageSourceCreateWithData(raw as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2048,
        ]
        guard let scaled = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: scaled).jpegData(compressionQuality: 0.8)
    }
}
