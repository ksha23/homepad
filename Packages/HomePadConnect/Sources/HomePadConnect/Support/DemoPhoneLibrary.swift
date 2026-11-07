#if DEBUG
import Foundation
import HomePadCore
import UIKit

/// Made-up photos for the simulator, whose library is empty and whose photo
/// access is hard to grant (`-ConnectPhonePhotosDemo YES` on the iPhone).
/// Debug builds only.
@MainActor
final class DemoPhoneLibrary: PhoneLibraryReader {
    private let palette: [(UIColor, UIColor)] = [
        (.systemOrange, .systemPink), (.systemTeal, .systemBlue), (.systemGreen, .systemMint),
        (.systemPurple, .systemIndigo), (.systemYellow, .systemOrange), (.systemRed, .systemPurple),
    ]

    var hasAccess: Bool { true }
    func requestAccess() async -> Bool { true }

    func albums() async -> [PhoneAlbum] {
        [
            album("phone.recents", "Recents", .recents, 0..<30),
            album("phone.favorites", "Favorites", .favorites, 0..<8),
            album("demo.lake", "Lake Weekend", .album, 8..<17),
            album("demo.hikes", "Hikes", .album, 17..<23),
        ]
    }

    func photos(in albumID: String, limit: Int) async -> [PhonePhoto]? {
        guard let album = await albums().first(where: { $0.id == albumID }) else { return nil }
        return Array(range(of: album).map(photo).prefix(limit))
    }

    func jpeg(for photoID: String, pixels: Int) async -> Data? {
        guard let index = Int(photoID.replacingOccurrences(of: "demo-photo-", with: "")) else { return nil }
        let source = photo(index)
        let scale = Double(pixels) / Double(max(source.pixelWidth, source.pixelHeight))
        let size = CGSize(width: Double(source.pixelWidth) * scale, height: Double(source.pixelHeight) * scale)
        let colors = palette[index % palette.count]
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let gradient = CGGradient(colorsSpace: nil, colors: [colors.0.cgColor, colors.1.cgColor] as CFArray, locations: [0, 1])
            if let gradient {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            }
            let sun = CGRect(x: size.width * 0.62, y: size.height * 0.18, width: size.width * 0.18, height: size.width * 0.18)
            UIColor.white.withAlphaComponent(0.55).setFill()
            context.cgContext.fillEllipse(in: sun)
            UIColor.black.withAlphaComponent(0.22).setFill()
            context.cgContext.fill(CGRect(x: 0, y: size.height * 0.72, width: size.width, height: size.height * 0.28))
        }
        return image.jpegData(compressionQuality: 0.8)
    }

    private func album(_ id: String, _ title: String, _ kind: PhoneAlbum.Kind, _ range: Range<Int>) -> PhoneAlbum {
        PhoneAlbum(id: id, title: title, kind: kind, count: range.count, keyPhoto: photo(range.lowerBound))
    }

    private func range(of album: PhoneAlbum) -> Range<Int> {
        switch album.id {
        case "phone.favorites": 0..<8
        case "demo.lake": 8..<17
        case "demo.hikes": 17..<23
        default: 0..<30
        }
    }

    /// Every third photo is upright, the rest 4:3.
    private func photo(_ index: Int) -> PhonePhoto {
        let upright = index % 3 == 2
        return PhonePhoto(id: "demo-photo-\(index)", pixelWidth: upright ? 3024 : 4032, pixelHeight: upright ? 4032 : 3024,
                          date: Date(timeIntervalSince1970: 1_790_000_000 - Double(index) * 86_400))
    }
}
#endif
