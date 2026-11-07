import Foundation
import HomePadCore

// The HomePad's side of the `photos.*` messages inside a visit.
extension PhonePhotosClient {
    func registerHandlers() {
        let link = visits.link
        link.on(.photosOffer) { [weak self] message, peer in
            guard let offer = try? message.content(PhotoShareOffer.self) else { return }
            self?.receive(offer, from: peer)
        }
        link.on(.photosReply) { [weak self] message, peer in
            guard let reply = try? message.content(PhotosReply.self) else { return }
            self?.visits.deliver(message, answering: reply.requestID, from: peer)
        }
        link.on(.photosImage) { [weak self] message, peer in
            guard let image = try? message.content(PhotosImage.self) else { return }
            self?.receive(image, jpeg: message.attachment, from: peer)
        }
    }

    /// A linked phone starts or stops sharing its photos. A person who stops
    /// leaves nothing of their photos behind on this iPad.
    func receive(_ offer: PhotoShareOffer, from peer: PeerDevice) {
        visits.receiveOffer(from: peer, sharing: offer.isSharing ? [.photos] : [], of: kinds,
                            wakeTag: offer.isSharing ? offer.wakeTag : nil)
    }

    // MARK: Requests

    /// Asks the phone and waits for its answer, on the session it opened.
    func request(_ request: PhotosRequest, in visit: PhoneVisit) async -> PhotosReply? {
        let message = await visits.request(.photosRequest, request, id: request.id, in: visit)
        return try? message?.content(PhotosReply.self)
    }

    /// One image from the phone. Cells that ask at once share one request.
    func fetch(_ photoID: String, size: PhotoImageSize, in state: PhotoVisitState) async -> Data? {
        let key = PhotoVisitState.imageKey(photoID, size)
        let waiterID = UUID()
        let timeout = visits.openTimeout + visits.replyTimeout
        return await withCheckedContinuation { continuation in
            let isNew = state.imageWaiters[key] == nil
            state.imageWaiters[key, default: [:]][waiterID] = continuation
            if isNew {
                state.queued[size, default: []].append(photoID)
                scheduleFlush(state)
            }
            Task {
                try? await Task.sleep(for: .seconds(timeout))
                state.imageWaiters[key]?.removeValue(forKey: waiterID)?.resume(returning: nil)
                if state.imageWaiters[key]?.isEmpty == true { state.imageWaiters[key] = nil }
            }
        }
    }

    private func scheduleFlush(_ state: PhotoVisitState) {
        guard !state.flushScheduled else { return }
        state.flushScheduled = true
        Task {
            // Lets the other cells drawn in the same pass add theirs.
            for _ in 0..<5 { await Task.yield() }
            state.flushScheduled = false
            await flush(state)
        }
    }

    private func flush(_ state: PhotoVisitState) async {
        let queued = state.queued
        state.queued = [:]
        guard !queued.isEmpty else { return }
        let visit = state.visit
        guard await visits.open(visit), current(visit) === state else {
            // Nobody to ask: the cells keep what they show.
            for (size, ids) in queued { ids.forEach { resolve(PhotoVisitState.imageKey($0, size), with: nil, in: state) } }
            return
        }
        for (size, ids) in queued {
            for start in stride(from: 0, to: ids.count, by: PhonePhotosPolicy.imagesPerRequest) {
                let chunk = Array(ids[start..<min(start + PhonePhotosPolicy.imagesPerRequest, ids.count)])
                do {
                    let message = try visits.link.message(.photosRequest, PhotosRequest.images(chunk, size: size))
                    try visits.sendOnGrantedSession(message, in: visit)
                } catch {
                    chunk.forEach { resolve(PhotoVisitState.imageKey($0, size), with: nil, in: state) }
                }
            }
        }
    }

    func receive(_ image: PhotosImage, jpeg: Data?, from peer: PeerDevice) {
        guard let visit = visits.grantedVisit(for: peer), let state = current(visit) else { return }
        let key = PhotoVisitState.imageKey(image.photoID, image.size)
        if let jpeg {
            hold(jpeg, key: key, size: image.size, in: state)
            let member = visit.memberID
            writeCache { $0.saveImage(jpeg, photoID: image.photoID, size: image.size, member: member) }
        }
        resolve(key, with: jpeg, in: state)
    }

    /// Keeps an image for the visit. Full images are large, so only the latest dozen stay in memory.
    private func hold(_ jpeg: Data, key: String, size: PhotoImageSize, in state: PhotoVisitState) {
        state.images[key] = jpeg
        guard size == .screen else { return }
        let screens = state.images.keys.filter { $0.hasPrefix(PhotoImageSize.screen.rawValue + "|") && $0 != key }
        if screens.count > 12, let drop = screens.first { state.images[drop] = nil }
    }

    private func resolve(_ key: String, with data: Data?, in state: PhotoVisitState) {
        state.imageWaiters.removeValue(forKey: key)?.values.forEach { $0.resume(returning: data) }
    }
}
