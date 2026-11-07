import CommsKit
import UniformTypeIdentifiers
import XCTest
@testable import HomePadComms

final class MediaTests: XCTestCase {
    func testStackLayoutChoice() {
        XCTAssertEqual(StackLayout.choose(count: 1), .single)
        XCTAssertEqual(StackLayout.choose(count: 2), .pile(count: 2))
        XCTAssertEqual(StackLayout.choose(count: 3), .pile(count: 3))
        XCTAssertEqual(StackLayout.choose(count: 4), .grid(shown: 4, extra: 0))
        XCTAssertEqual(StackLayout.choose(count: 5), .grid(shown: 4, extra: 2))
        XCTAssertEqual(StackLayout.choose(count: 12), .grid(shown: 4, extra: 9))
    }

    func testPhotosGroupTogetherAndVideosStaySeparate() {
        let list = [
            CommsAttachment(id: "v", mimeType: "video/quicktime", name: "a.mov"),
            CommsAttachment(id: "p1", mimeType: "image/heic", name: "1.heic"),
            CommsAttachment(id: "f", mimeType: "application/pdf", name: "x.pdf"),
            CommsAttachment(id: "p2", mimeType: "image/jpeg", name: "2.jpg"),
        ]
        let groups = AttachmentGroup.make(list)
        XCTAssertEqual(groups.count, 3)
        guard case .photos(let photos) = groups[0] else { return XCTFail("photos first") }
        XCTAssertEqual(photos.map(\.id), ["p1", "p2"])
    }

    func testPickedFilenameAndMime() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertTrue(PickedMedia.filename(for: .heic, index: 0, date: date).hasPrefix("IMG_"))
        XCTAssertTrue(PickedMedia.filename(for: .heic, index: 0, date: date).hasSuffix("_1.heic"))
        XCTAssertTrue(PickedMedia.filename(for: .quickTimeMovie, index: 1, date: date).hasPrefix("VID_"))
        XCTAssertEqual(PickedMedia.mimeType(for: .png), "image/png")
        XCTAssertEqual(PickedMedia.mimeType(for: nil), "application/octet-stream")
    }

    func testViewerPixelSizeIsBounded() {
        XCTAssertEqual(AttachmentLoader.viewerPixelSize(screenPoints: CGSize(width: 1366, height: 1024), scale: 2), 3072)
        XCTAssertEqual(AttachmentLoader.viewerPixelSize(screenPoints: CGSize(width: 100, height: 100), scale: 1), 1024)
    }

    @MainActor
    func testSendingWhileDisconnectedThrows() async {
        let store = CommsStore()
        do {
            try await store.sendAttachment(Data([1]), filename: "a.jpg", mimeType: "image/jpeg", to: "c")
            XCTFail("should throw")
        } catch {
            XCTAssertNotNil(error as? HubClient.Failure)
        }
    }
}
