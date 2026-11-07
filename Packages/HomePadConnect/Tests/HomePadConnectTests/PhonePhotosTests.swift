import CryptoKit
import Foundation
import HomePadCore
import Testing
@testable import HomePadConnect

/// Each person's own phone photos: the wire, the phone's rules for opening
/// its photos, and what the HomePad shows when.
@MainActor
@Suite struct PhonePhotosTests {
    /// Why the phone refused, or nil when it opened.
    private func refusal(_ result: Result<Set<PhoneDataKind>, PhoneVisitRefusal>) -> PhoneVisitRefusal? {
        if case .failure(let reason) = result { return reason }
        return nil
    }

    // MARK: Wire

    @Test func requestsAndAnswersSurviveTheWire() throws {
        let photo = PhonePhoto(id: "A/L0/001", pixelWidth: 3024, pixelHeight: 4032, date: Date(timeIntervalSince1970: 1_790_000_000))
        let album = PhoneAlbum(id: "phone.recents", title: "Recents", kind: .recents, count: 12, keyPhoto: photo)
        let request = PhotosRequest.images((0..<40).map { "id\($0)" }, size: .screen)
        #expect(request.imageIDs?.count == PhonePhotosPolicy.imagesPerRequest)

        let reply = PhotosReply(requestID: request.id, albums: [album], photos: [photo])
        let message = try PeerMessage(type: .photosReply, sender: "phone", content: reply)
        #expect(try RemoteLoop.overTheWire(message).content(PhotosReply.self) == reply)

        let jpeg = Data((0..<5000).map { UInt8($0 % 251) })
        let image = try PeerMessage(type: .photosImage, sender: "phone",
                                    content: PhotosImage(requestID: request.id, photoID: photo.id, size: .thumbnail), attachment: jpeg)
        let received = RemoteLoop.overTheWire(image)
        #expect(received.attachment == jpeg)
        #expect(try received.content(PhotosImage.self).photoID == "A/L0/001")
        #expect(photo.aspectRatio == 0.75)
    }

    @Test func theSignatureCoversEveryField() {
        let request = UUID(), member = UUID(), nonce = Data(repeating: 7, count: 32)
        let base = PhoneVisitOpen.signedBytes(requestID: request, nonce: nonce, memberID: member, homePadID: "pad", phoneID: "phone")
        #expect(base != PhoneVisitOpen.signedBytes(requestID: UUID(), nonce: nonce, memberID: member, homePadID: "pad", phoneID: "phone"))
        #expect(base != PhoneVisitOpen.signedBytes(requestID: request, nonce: Data(repeating: 8, count: 32), memberID: member, homePadID: "pad", phoneID: "phone"))
        #expect(base != PhoneVisitOpen.signedBytes(requestID: request, nonce: nonce, memberID: UUID(), homePadID: "pad", phoneID: "phone"))
        #expect(base != PhoneVisitOpen.signedBytes(requestID: request, nonce: nonce, memberID: member, homePadID: "other", phoneID: "phone"))
        #expect(base != PhoneVisitOpen.signedBytes(requestID: request, nonce: nonce, memberID: member, homePadID: "pad", phoneID: "other"))
    }

    @Test func wakeTagsSplitIntoSixteenBytes() {
        let first = Data(repeating: 1, count: 16), second = Data(repeating: 2, count: 16)
        #expect(ProximityWake.tags(in: first + second) == [first, second])
        #expect(ProximityWake.tags(in: Data(repeating: 3, count: 10)).isEmpty)
    }

    // MARK: The phone's rules

    @Test func thePhoneOpensOnlyForTheLinkedMemberWithTheHomePadsKey() {
        let key = P256.Signing.PrivateKey()
        let kyle = UUID()
        let session = PhoneGrantBook.Session(peerID: "pad", sessionID: UUID())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let trust = PhoneGrantBook.HomePadTrust(linkedMemberID: kyle, sharing: [.photos], readable: [.photos],
                                                homePadKey: key.publicKey.rawRepresentation)
        var book = PhoneGrantBook()

        #expect(book.hello(PhoneVisitHello(memberID: UUID()), on: session, trust: trust, now: now) == .failure(.notLinked))
        var off = trust
        off.sharing = []
        #expect(book.hello(PhoneVisitHello(memberID: kyle), on: session, trust: off, now: now) == .failure(.notSharing))
        var noAccess = trust
        noAccess.readable = []
        #expect(book.hello(PhoneVisitHello(memberID: kyle), on: session, trust: noAccess, now: now) == .failure(.noPhotoAccess))
        var noKey = trust
        noKey.homePadKey = nil
        #expect(book.hello(PhoneVisitHello(memberID: kyle), on: session, trust: noKey, now: now) == .failure(.notVerified))

        // Another household device can say it is the HomePad, but cannot sign with its key.
        let hello = PhoneVisitHello(memberID: kyle)
        guard case .success(let challenge) = book.hello(hello, on: session, trust: trust, now: now) else { return #expect(Bool(false)) }
        let bytes = PhoneVisitOpen.signedBytes(requestID: hello.requestID, nonce: challenge.nonce, memberID: kyle, homePadID: "pad", phoneID: "phone")
        let forged = PhoneVisitOpen(requestID: hello.requestID, signature: try! P256.Signing.PrivateKey().signature(for: bytes).rawRepresentation)
        #expect(refusal(book.open(forged, on: session, phoneID: "phone", trust: trust, now: now)) == .notVerified)
        #expect(!book.isGranted(session, memberID: kyle, kind: .photos, now: now))

        // A challenge is used once.
        let signed = PhoneVisitOpen(requestID: hello.requestID, signature: try! key.signature(for: bytes).rawRepresentation)
        #expect(refusal(book.open(signed, on: session, phoneID: "phone", trust: trust, now: now)) == .expired)
    }

    @Test func aGrantBelongsToOneSessionAndRunsOut() {
        let key = P256.Signing.PrivateKey()
        let kyle = UUID()
        let session = PhoneGrantBook.Session(peerID: "pad", sessionID: UUID())
        let other = PhoneGrantBook.Session(peerID: "pad", sessionID: UUID())
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let trust = PhoneGrantBook.HomePadTrust(linkedMemberID: kyle, sharing: [.photos], readable: [.photos],
                                                homePadKey: key.publicKey.rawRepresentation)
        var book = PhoneGrantBook()

        func opened(on issued: PhoneGrantBook.Session, answeredOn answered: PhoneGrantBook.Session, after delay: TimeInterval) -> Bool {
            let hello = PhoneVisitHello(memberID: kyle)
            guard case .success(let challenge) = book.hello(hello, on: issued, trust: trust, now: start) else { return false }
            let bytes = PhoneVisitOpen.signedBytes(requestID: hello.requestID, nonce: challenge.nonce, memberID: kyle, homePadID: "pad", phoneID: "phone")
            let open = PhoneVisitOpen(requestID: hello.requestID, signature: try! key.signature(for: bytes).rawRepresentation)
            return (try? book.open(open, on: answered, phoneID: "phone", trust: trust, now: start.addingTimeInterval(delay)).get()) != nil
        }

        #expect(!opened(on: session, answeredOn: other, after: 1), "a signature on another session opens nothing")
        #expect(!opened(on: session, answeredOn: session, after: PhoneVisitPolicy.challengeLifetime + 1), "too late")
        #expect(opened(on: session, answeredOn: session, after: 1))
        #expect(book.isGranted(session, memberID: kyle, kind: .photos, now: start.addingTimeInterval(2)))
        #expect(!book.isGranted(other, memberID: kyle, kind: .photos, now: start.addingTimeInterval(2)), "a new session with the same ID starts with nothing")
        #expect(!book.isGranted(session, memberID: UUID(), kind: .photos, now: start.addingTimeInterval(2)))
        #expect(!book.isGranted(session, memberID: kyle, kind: .photos, now: start.addingTimeInterval(PhoneVisitPolicy.grantLifetime + 2)))
        book.revoke(peerID: "pad")
        #expect(!book.isGranted(session, memberID: kyle, kind: .photos, now: start.addingTimeInterval(2)))
    }

    // MARK: What shows when

    @Test func kylesPhotosShowOnlyWhileKyleIsRecognized() async throws {
        let loop = PhoneLoop()
        try await loop.linkAndShare()
        #expect(loop.client.sharedPhones[loop.phoneDevice.id]?.memberID == loop.kyle.id)
        #expect(loop.waker.started)
        #expect(loop.client.library == nil)

        // Picking Kyle by hand is not enough.
        loop.padServices.household.select(loop.kyle.id)
        await loop.settle()
        #expect(loop.client.library == nil)
        #expect(loop.sentToPhone(.visitHello).isEmpty)

        loop.padServices.household.recognize(loop.kyle.id)
        await loop.eventually { loop.client.library?.albums.count == 3 }
        let library = try #require(loop.client.library)
        #expect(library.memberID == loop.kyle.id)
        #expect(library.deviceName == "Kyle's iPhone")
        #expect(library.albums.map(\.title) == ["Recents", "Favorites", "Trip"])
        // Thumbnails came first, then a few full images, and the phone heard that was all.
        await loop.eventually { !loop.sentToPhone(.visitClose).isEmpty }
        #expect(await loop.client.thumbnail(of: "p3") == Data("jpeg p3 360".utf8))
        #expect(loop.sentToPad(.photosImage).count >= 4)

        // Sam steps up: Kyle's photos are gone at once, and Sam has no phone sharing.
        let hellos = loop.sentToPhone(.visitHello).count
        loop.padServices.household.recognize(loop.sam.id)
        await loop.settle()
        #expect(loop.client.library == nil)
        #expect(await loop.client.thumbnail(of: "p3") == nil)
        #expect(loop.sentToPhone(.visitHello).count == hellos)
    }

    @Test func aPhoneAwayIsWokenOverBluetoothAndAnswersWhenItJoins() async throws {
        let loop = PhoneLoop()
        try await loop.linkAndShare()
        loop.session = nil
        loop.padServices.household.recognize(loop.kyle.id)
        await loop.settle()
        let tag = try #require(loop.server.sharing[loop.pad.id]?.wakeTag)
        #expect(loop.waker.woken == [tag])
        #expect(loop.client.library == nil)

        // The woken phone joins the peer link.
        loop.session = UUID()
        loop.visits.peerConnected(loop.phoneDevice)
        await loop.eventually { loop.client.library?.albums.isEmpty == false }
        #expect(loop.client.library?.memberID == loop.kyle.id)
    }

    @Test func stoppingSharingLeavesNothingOnTheHomePad() async throws {
        let loop = PhoneLoop()
        try await loop.linkAndShare()
        loop.padServices.household.recognize(loop.kyle.id)
        await loop.eventually { !loop.sentToPhone(.visitClose).isEmpty && loop.client.cache.loadIndex(member: loop.kyle.id) != nil }
        #expect(loop.client.cache.loadIndex(member: loop.kyle.id) != nil)

        await loop.server.setSharing(false, with: loop.pad.id)
        await loop.settle()
        #expect(loop.client.sharedPhones.isEmpty)
        #expect(loop.client.library == nil)
        #expect(loop.client.cache.loadIndex(member: loop.kyle.id) == nil)
        #expect(!loop.waker.started)
    }

    @Test func removingAPersonForgetsTheirPhoneAndCache() async throws {
        let loop = PhoneLoop()
        try await loop.linkAndShare()
        loop.padServices.household.recognize(loop.kyle.id)
        await loop.eventually { !loop.sentToPhone(.visitClose).isEmpty }
        loop.padServices.household.remove(loop.kyle.id)
        loop.approver.pruneLinks()
        await loop.settle()
        #expect(loop.client.library == nil)
        #expect(loop.client.sharedPhones.isEmpty)
        #expect(loop.client.cache.loadIndex(member: loop.kyle.id) == nil)
    }

    @Test func anotherDeviceCannotReadThePhoneEvenWithTheHomePadsID() async throws {
        let loop = PhoneLoop()
        try await loop.linkAndShare()
        // A household device opens its own session saying it is the Kitchen HomePad.
        var impostor = loop.pad
        impostor.sessionID = UUID()
        let hello = PhoneVisitHello(memberID: loop.kyle.id)
        loop.toPhone(try loop.padLink.message(.visitHello, hello), from: impostor)
        await loop.settle()
        let challenge = try #require(try loop.sentToPad(.visitChallenge).last?.content(PhoneVisitChallenge.self))
        // It signs with its own key, not the HomePad's.
        let bytes = PhoneVisitOpen.signedBytes(requestID: hello.requestID, nonce: challenge.nonce, memberID: loop.kyle.id,
                                           homePadID: loop.pad.id, phoneID: loop.phoneDevice.id)
        let open = PhoneVisitOpen(requestID: hello.requestID, signature: try P256.Signing.PrivateKey().signature(for: bytes).rawRepresentation)
        loop.toPhone(try loop.padLink.message(.visitOpen, open), from: impostor)
        loop.toPhone(try loop.padLink.message(.photosRequest, PhotosRequest.albumList()), from: impostor)
        await loop.settle()
        #expect(loop.sentToPad(.visitOpened).isEmpty)
        #expect(loop.sentToPad(.photosReply).isEmpty)
        #expect(try loop.sentToPad(.visitRefused).last?.content(PhoneVisitRefused.self).reason == .notVerified)
    }

    // MARK: The cache

    @Test func theCacheIsSealedPerMember() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("phone-cache-\(UUID().uuidString)")
        let cache = PhonePhotosCache(directory: directory, keychain: MemorySecrets())
        let kyle = UUID(), sam = UUID()
        let jpeg = Data("a private photo".utf8)
        #expect(cache.saveImage(jpeg, photoID: "p1", size: .thumbnail, member: kyle))
        #expect(cache.image("p1", size: .thumbnail, member: kyle) == jpeg)
        #expect(cache.image("p1", size: .thumbnail, member: sam) == nil)

        let files = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent(kyle.uuidString), includingPropertiesForKeys: nil)
        let bytes = try Data(contentsOf: try #require(files.first))
        #expect(bytes.range(of: jpeg) == nil, "photos must not be stored in the clear")
        #expect(!files.contains { $0.lastPathComponent.contains("p1") }, "file names do not list the phone's photo IDs")

        cache.prune(keeping: [sam])
        #expect(cache.image("p1", size: .thumbnail, member: kyle) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(kyle.uuidString).path))
    }
}
