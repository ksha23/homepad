import Foundation
import HomePadCore
import Observation

/// On an iPhone: serves its owner's photo library to the HomePads they turned
/// on Show My Photos for, and to nothing else. One kind of data a visit
/// carries (`PhoneVisitServer`), which opens the session and checks the grant.
@MainActor
@Observable
public final class PhoneLibraryServer: PhoneVisitServing {
    /// Why Show My Photos could not turn on, by HomePad ID.
    public private(set) var errors: [String: String] = [:]
    /// When this phone last sent photos to each HomePad, by HomePad ID.
    public private(set) var lastServed: [String: Date] = [:]
    /// The HomePads this phone shares with, by HomePad ID.
    public private(set) var sharing: [String: PhotoSharingChoice]

    let kinds: Set<PhoneDataKind> = [.photos]
    @ObservationIgnored let visit: PhoneVisitServer
    @ObservationIgnored var reader: any PhoneLibraryReader
    @ObservationIgnored private let log = Log.make("PhonePhotos")

    static let sharingKey = SettingKey<[String: PhotoSharingChoice]>("connect.photos.sharing", default: [:])

    init(visit: PhoneVisitServer) {
        self.visit = visit
        self.sharing = visit.services.settings[Self.sharingKey]
        self.reader = PhotoKitLibraryReader()
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "ConnectPhonePhotosDemo") { reader = DemoPhoneLibrary() }
        #endif
    }

    func start() {
        visit.link.on(.photosRequest) { [weak self] message, peer in
            guard let request = try? message.content(PhotosRequest.self) else { return }
            Task { await self?.serve(request, to: peer) }
        }
    }

    // MARK: Show My Photos

    /// True when this phone shares its photos with that HomePad.
    public func isSharing(with homePadID: String) -> Bool { sharing[homePadID] != nil }

    /// Turns Show My Photos on or off for one HomePad. Turning it on asks for
    /// photo access first, then Bluetooth, so the HomePad can wake this app.
    public func setSharing(_ isOn: Bool, with homePadID: String) async {
        errors[homePadID] = nil
        guard isOn else {
            sharing[homePadID] = nil
            persist()
            await visit.sharingChanged(self, with: homePadID)
            return
        }
        guard visit.linkedMember(on: homePadID) != nil else {
            errors[homePadID] = "Link this iPhone to yourself on that HomePad first."
            return
        }
        guard await reader.requestAccess() else {
            errors[homePadID] = "Allow HomePad to see your photos in Settings, Privacy & Security, Photos."
            return
        }
        let choice = sharing[homePadID] ?? PhotoSharingChoice(wakeTag: visit.wakeTag(for: homePadID))
        sharing[homePadID] = choice
        persist()
        await visit.sharingChanged(self, with: homePadID)
    }

    /// Bluetooth's state for the card, nil while nothing is shared.
    public var wakeProblem: String? { visit.wakeProblem }

    // MARK: PhoneVisitServing

    func sharedKinds(with homePadID: String) -> Set<PhoneDataKind> {
        sharing[homePadID] == nil ? [] : [.photos]
    }

    var readableKinds: Set<PhoneDataKind> { reader.hasAccess ? [.photos] : [] }

    func wakeTag(for homePadID: String) -> Data? { sharing[homePadID]?.wakeTag }

    var wakeTags: [Data] { sharing.values.map(\.wakeTag) }

    func sendOffer(to homePadID: String) async {
        let offer = PhotoShareOffer(isSharing: sharing[homePadID] != nil, wakeTag: sharing[homePadID]?.wakeTag)
        await visit.sendOffer(.photosOffer, offer, to: homePadID)
    }

    func stopSharing(with homePadID: String) {
        guard sharing[homePadID] != nil else { return }
        sharing[homePadID] = nil
        persist()
    }

    // MARK: Requests

    func serve(_ request: PhotosRequest, to peer: PeerDevice) async {
        guard let member = visit.grantedMember(peer, for: .photos) else { return }
        lastServed[peer.id] = visit.now()
        if request.albums == true {
            visit.send(.photosReply, PhotosReply(requestID: request.id, albums: await reader.albums()), to: peer)
        } else if let albumID = request.albumID {
            let photos = await reader.photos(in: albumID, limit: PhonePhotosPolicy.listLimit)
            visit.send(.photosReply, PhotosReply(requestID: request.id, photos: photos, failed: photos == nil ? true : nil), to: peer)
        } else if let ids = request.imageIDs, let size = request.size {
            // One at a time, so a long list never holds many full images in memory.
            for id in ids.prefix(PhonePhotosPolicy.imagesPerRequest) {
                guard visit.isGranted(peer, member: member, kind: .photos) else { return }
                let jpeg = await reader.jpeg(for: id, pixels: size.pixels)
                visit.send(.photosImage, PhotosImage(requestID: request.id, photoID: id, size: size), attachment: jpeg, to: peer)
            }
        }
    }

    private func persist() {
        visit.services.settings[Self.sharingKey] = sharing
    }
}

/// On a phone: Show My Photos for one HomePad.
public struct PhotoSharingChoice: Codable, Equatable, Sendable {
    /// Written over Bluetooth to that HomePad, so it can wake this phone.
    /// Shared with the calendars' choice for the same HomePad.
    public var wakeTag: Data
}
