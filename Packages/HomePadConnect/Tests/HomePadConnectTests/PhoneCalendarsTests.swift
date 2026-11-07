import CryptoKit
import Foundation
import HomePadCore
import Testing
@testable import HomePadConnect

/// Each person's own phone calendars and reminders: one visit for every kind,
/// the window fetched and sealed, changes and their states, and who sees what.
@MainActor
@Suite struct PhoneCalendarsTests {
    private func event(_ loop: PhoneLoop, _ title: String) -> PhoneEvent? {
        loop.calendars.snapshot?.events.first { $0.title == title }
    }

    // MARK: One visit

    @Test func oneWakeAndOneChallengeOpenPhotosAndCalendars() async throws {
        let loop = PhoneLoop()
        try await loop.linkAndShare()
        try await loop.shareCalendars()
        let record = try #require(loop.visits.sharedPhones[loop.phoneDevice.id])
        #expect(record.kinds == [.photos, .calendars, .reminders])
        #expect(loop.calendarServer.sharing[loop.pad.id]?.wakeTag == loop.server.sharing[loop.pad.id]?.wakeTag,
                "one tag per HomePad, whatever is shared")

        // The phone is asleep: one wake on recognition.
        loop.session = nil
        loop.padServices.household.recognize(loop.kyle.id)
        await loop.settle()
        #expect(loop.waker.woken == [record.wakeTag])

        loop.session = UUID()
        loop.visits.peerConnected(loop.phoneDevice)
        await loop.eventually {
            loop.client.library?.albums.count == 3 && loop.calendars.snapshot?.fetchedAt != nil && !loop.sentToPhone(.visitClose).isEmpty
        }
        let hello = try #require(try loop.sentToPhone(.visitHello).first?.content(PhoneVisitHello.self))
        #expect(loop.sentToPhone(.visitHello).count == 1)
        #expect(hello.requestedKinds == [.photos, .calendars, .reminders])
        #expect(loop.sentToPad(.visitChallenge).count == 1)
        #expect(try loop.sentToPad(.visitOpened).first?.content(PhoneVisitOpened.self).grantedKinds == [.photos, .calendars, .reminders])
        #expect(loop.sentToPhone(.visitClose).count == 1)
        // Calendars, a few small answers, go before the photos' many.
        let types = loop.toPhoneLog.map(\.type)
        #expect(try #require(types.firstIndex(of: .calendarRequest)) < (try #require(types.firstIndex(of: .photosRequest))))
    }

    @Test func aVisitOpensOnlyWhatIsSharedAndReadable() throws {
        let key = P256.Signing.PrivateKey()
        let kyle = UUID()
        let session = PhoneGrantBook.Session(peerID: "pad", sessionID: UUID())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let trust = PhoneGrantBook.HomePadTrust(linkedMemberID: kyle, sharing: [.calendars, .reminders],
                                                readable: [.calendars, .photos], homePadKey: key.publicKey.rawRepresentation)
        var book = PhoneGrantBook()

        // A HomePad from before calendars asks for photos only, which this phone does not share.
        #expect(book.hello(PhoneVisitHello(memberID: kyle), on: session, trust: trust, now: now) == .failure(.notSharing))
        #expect(book.hello(PhoneVisitHello(memberID: kyle, kinds: ["reminders"]), on: session, trust: trust, now: now)
                == .failure(.noReminderAccess))

        // Names a newer device adds are skipped, not fatal.
        let hello = PhoneVisitHello(memberID: kyle, kinds: ["photos", "calendars", "reminders", "music"])
        let challenge = try book.hello(hello, on: session, trust: trust, now: now).get()
        let bytes = PhoneVisitOpen.signedBytes(requestID: hello.requestID, nonce: challenge.nonce, memberID: kyle, homePadID: "pad", phoneID: "phone")
        let open = PhoneVisitOpen(requestID: hello.requestID, signature: try key.signature(for: bytes).rawRepresentation)
        #expect(try book.open(open, on: session, phoneID: "phone", trust: trust, now: now).get() == [.calendars])
        #expect(book.isGranted(session, memberID: kyle, kind: .calendars, now: now))
        #expect(!book.isGranted(session, memberID: kyle, kind: .reminders, now: now))
        #expect(!book.isGranted(session, memberID: kyle, kind: .photos, now: now))
        book.revoke(.calendars, peerID: "pad")
        #expect(!book.isGranted(session, memberID: kyle, kind: .calendars, now: now))

        // Records saved before calendars were for photos.
        let old = Data(#"{"memberID":"\#(kyle.uuidString)","wakeTag":"AAAAAAAAAAAAAAAAAAAAAA=="}"#.utf8)
        #expect(try JSONDecoder().decode(SharedPhone.self, from: old).kinds == [.photos])
    }

    // MARK: Who sees what

    @Test func kylesCalendarsShowOnlyWhileKyleIsRecognized() async throws {
        let loop = PhoneLoop()
        try await loop.shareCalendars()

        // Picking Kyle by hand is not enough.
        loop.padServices.household.select(loop.kyle.id)
        await loop.settle()
        #expect(loop.calendars.snapshot == nil)
        #expect(loop.sentToPhone(.visitHello).isEmpty)

        loop.padServices.household.recognize(loop.kyle.id)
        await loop.eventually { loop.calendars.snapshot?.fetchedAt != nil && !loop.sentToPhone(.visitClose).isEmpty }
        let snapshot = try #require(loop.calendars.snapshot)
        #expect(snapshot.memberID == loop.kyle.id)
        #expect(snapshot.calendars.map(\.title) == ["Home", "Work"])
        #expect(Set(snapshot.events.map(\.title)) == ["Dentist", "Standup"])
        #expect(snapshot.reminders.map(\.title) == ["Return library books"])
        // The past week to six weeks ahead.
        let window = PhoneCalendarsPolicy.window(around: Date())
        #expect(snapshot.window == window)
        #expect(loop.store.lastRange == window)
        #expect(window.duration >= 49 * 86_400 - 3600)

        // Saved sealed, never in the clear.
        await loop.eventually { loop.calendars.cache.load(member: loop.kyle.id)?.events.count == 2 }
        let files = FileManager.default.enumerator(at: loop.calendarDirectory, includingPropertiesForKeys: [.isRegularFileKey])?
            .compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true } ?? []
        #expect(!files.isEmpty)
        #expect(try files.allSatisfy { try Data(contentsOf: $0).range(of: Data("Dentist".utf8)) == nil })

        // Sam steps up: Kyle's calendars leave memory at once.
        loop.padServices.household.recognize(loop.sam.id)
        await loop.settle()
        #expect(loop.calendars.snapshot == nil)
        #expect(loop.calendars.state == nil)

        // Kyle again, with the phone asleep: what was saved shows at once.
        loop.session = nil
        loop.padServices.household.recognize(loop.kyle.id)
        await loop.settle()
        #expect(loop.calendars.snapshot?.events.count == 2)
        #expect(loop.calendars.snapshot?.isConnected == false)
    }

    @Test func stoppingSharingTakesItOffTheHomePadAtOnce() async throws {
        let loop = PhoneLoop()
        try await loop.shareCalendars()
        loop.padServices.household.recognize(loop.kyle.id)
        await loop.eventually { loop.calendars.snapshot?.events.count == 2 && !loop.sentToPhone(.visitClose).isEmpty }

        let calendars = loop.store.calendars()
        await loop.calendarServer.setShared(false, try #require(calendars.first { $0.id == "work" }), kind: .calendars, with: loop.pad.id)
        await loop.settle()
        #expect(loop.calendars.snapshot?.calendars.map(\.id) == ["home"])
        #expect(loop.calendars.snapshot?.events.map(\.title) == ["Dentist"])
        await loop.eventually { loop.calendars.cache.load(member: loop.kyle.id)?.events.map(\.title) == ["Dentist"] }

        // Turning everything off leaves nothing on the HomePad.
        await loop.calendarServer.setShared(false, try #require(calendars.first { $0.id == "home" }), kind: .calendars, with: loop.pad.id)
        await loop.calendarServer.setShared(false, try #require(loop.store.lists().first), kind: .reminders, with: loop.pad.id)
        await loop.settle()
        #expect(loop.calendars.snapshot == nil)
        #expect(loop.visits.sharedPhones.isEmpty)
        #expect(loop.calendars.cache.load(member: loop.kyle.id) == nil)
        #expect(!loop.waker.started)
    }

    @Test func thePhoneOpensAndSavesOnlyWhatItShares() async throws {
        let loop = PhoneLoop()
        try await loop.shareCalendars(["home"], lists: [])
        // The HomePad opens a session for calendars, signed with its own key.
        var pad = loop.pad
        pad.sessionID = UUID()
        let hello = PhoneVisitHello(memberID: loop.kyle.id, kinds: ["calendars", "reminders"])
        loop.toPhone(try loop.padLink.message(.visitHello, hello), from: pad)
        await loop.settle()
        let challenge = try #require(try loop.sentToPad(.visitChallenge).last?.content(PhoneVisitChallenge.self))
        let bytes = PhoneVisitOpen.signedBytes(requestID: hello.requestID, nonce: challenge.nonce, memberID: loop.kyle.id,
                                               homePadID: loop.pad.id, phoneID: loop.phoneDevice.id)
        let open = PhoneVisitOpen(requestID: hello.requestID, signature: try loop.padKey.signature(for: bytes).rawRepresentation)
        loop.toPhone(try loop.padLink.message(.visitOpen, open), from: pad)
        await loop.settle()
        #expect(try loop.sentToPad(.visitOpened).last?.content(PhoneVisitOpened.self).grantedKinds == [.calendars])

        // Only the shared calendar comes back.
        let today = FakePhoneCalendars.today
        loop.toPhone(try loop.padLink.message(.calendarRequest, CalendarRequest(start: today - 86_400, end: today + 30 * 86_400)), from: pad)
        loop.toPhone(try loop.padLink.message(.remindersRequest, RemindersRequest(completedSince: today)), from: pad)
        await loop.settle()
        let reply = try #require(try loop.sentToPad(.calendarReply).last?.content(CalendarReply.self))
        #expect(reply.calendars.map(\.id) == ["home"])
        #expect(reply.events.map(\.title) == ["Dentist"])
        #expect(loop.sentToPad(.remindersReply).isEmpty, "lists were not opened")

        // Nothing is added to, changed in or moved into a calendar it does not share.
        let standup = try #require(loop.store.savedEvents.first { $0.title == "Standup" })
        let dentist = try #require(loop.store.savedEvents.first { $0.title == "Dentist" })
        let changes = [
            CalendarChange(fields: PhoneEventFields(calendarID: "work", title: "Added", start: today, end: today + 3600, isAllDay: false, location: nil)),
            CalendarChange(itemID: standup.itemID, occurrenceStart: standup.start,
                           fields: PhoneEventFields(calendarID: "work", title: "Changed", start: standup.start, end: standup.end, isAllDay: false, location: nil)),
            CalendarChange(itemID: dentist.itemID, occurrenceStart: dentist.start,
                           fields: PhoneEventFields(calendarID: "work", title: "Moved", start: dentist.start, end: dentist.end, isAllDay: false, location: nil)),
        ]
        for change in changes { loop.toPhone(try loop.padLink.message(.calendarChange, change), from: pad) }
        await loop.settle()
        let refused = try loop.sentToPad(.calendarChanged).map { try $0.content(CalendarChanged.self) }
        #expect(refused.count == 3)
        #expect(refused.allSatisfy { $0.failure == PhoneChangeFailure.notShared.rawValue })
        #expect(loop.store.savedEvents.map(\.title) == ["Dentist", "Standup"])

        // A change sent again, after its answer got lost, is saved once and answered the same.
        let add = CalendarChange(fields: PhoneEventFields(calendarID: "home", title: "Climbing", start: today, end: today + 3600,
                                                          isAllDay: false, location: nil))
        loop.toPhone(try loop.padLink.message(.calendarChange, add), from: pad)
        loop.toPhone(try loop.padLink.message(.calendarChange, add), from: pad)
        await loop.settle()
        let saved = try loop.sentToPad(.calendarChanged).dropFirst(3).map { try $0.content(CalendarChanged.self) }
        #expect(saved.map(\.event?.itemID) == ["added1", "added1"])
        #expect(loop.store.adds == 1)
    }

    // MARK: Changes

    @Test func aChangeWaitsForAnAsleepPhoneAndIsSavedOnceWhenItWakes() async throws {
        let loop = PhoneLoop()
        try await loop.shareCalendars()
        loop.padServices.household.recognize(loop.kyle.id)
        await loop.eventually { loop.calendars.snapshot?.fetchedAt != nil && !loop.sentToPhone(.visitClose).isEmpty }

        // The phone goes to sleep and its link closes.
        loop.session = nil
        loop.visits.peerDisconnected(loop.phoneDevice.id)
        let start = FakePhoneCalendars.today.addingTimeInterval(2 * 86_400 + 18 * 3600)
        try loop.calendars.addEvent(EventDraft(title: "Climbing", start: start, end: start + 3600, calendarID: "home"))
        #expect(event(loop, "Climbing")?.status?.state == .sending)
        await loop.eventually { event(loop, "Climbing")?.status?.state == .waiting }
        #expect(event(loop, "Climbing")?.status?.message == "Kyle's iPhone isn't reachable. HomePad sends this when it is.")
        #expect(!loop.waker.woken.isEmpty, "the HomePad tried to wake it")

        // It waits, sealed, across visits.
        loop.padServices.household.recognize(loop.sam.id)
        await loop.settle()
        loop.padServices.household.recognize(loop.kyle.id)
        await loop.settle()
        #expect(event(loop, "Climbing")?.status != nil)

        // The phone wakes and saves it, but its answer is lost on the way back.
        var lost = false
        let reply = loop.visitServer.reply
        loop.visitServer.reply = { message, peer in
            if message.type == .calendarChanged && !lost {
                lost = true
                return
            }
            try reply(message, peer)
        }
        loop.session = UUID()
        loop.visits.peerConnected(loop.phoneDevice)
        // The fetch after it says the phone has it, so it shows once, saved.
        await loop.eventually { loop.calendars.state?.outbox.isEmpty == true && event(loop, "Climbing")?.status == nil }
        #expect(lost)
        #expect(loop.calendars.snapshot?.events.filter { $0.title == "Climbing" }.map(\.itemID) == ["added1"])
        #expect(loop.store.adds == 1)
        await loop.eventually { loop.calendars.cache.load(member: loop.kyle.id)?.outbox.isEmpty == true }
    }

    @Test func remindersAreCheckedOffAndAddedOnThePhone() async throws {
        let loop = PhoneLoop()
        try await loop.shareCalendars(["home", "holidays"])
        loop.padServices.household.recognize(loop.kyle.id)
        await loop.eventually { loop.calendars.snapshot?.fetchedAt != nil && !loop.sentToPhone(.visitClose).isEmpty }
        func reminder(_ title: String) -> PhoneReminder? { loop.calendars.snapshot?.reminders.first { $0.title == title } }

        try loop.calendars.setReminderCompleted("r1", completed: true)
        #expect(reminder("Return library books")?.isCompleted == true)
        try loop.calendars.addReminder(title: "Buy stamps", due: nil, listID: "errands")
        await loop.eventually { loop.calendars.state?.outbox.isEmpty == true }
        #expect(loop.store.savedReminders.first { $0.id == "r1" }?.isCompleted == true)
        #expect(loop.store.savedReminders.contains { $0.title == "Buy stamps" })
        #expect(reminder("Buy stamps")?.status == nil)

        // A change the phone refuses fails with the reason, and is not sent again by itself.
        loop.store.failsSaves = true
        try loop.calendars.setReminderCompleted("r1", completed: false)
        await loop.eventually { reminder("Return library books")?.status?.state == .failed }
        #expect(reminder("Return library books")?.status?.message == "Kyle's iPhone couldn't save it.")
        let sent = loop.sentToPhone(.remindersChange).count
        loop.visits.peerConnected(loop.phoneDevice)
        await loop.settle()
        #expect(loop.sentToPhone(.remindersChange).count == sent)

        // Discarding it shows the reminder as the phone has it.
        loop.calendars.discard(try #require(reminder("Return library books")?.status?.writeID))
        #expect(reminder("Return library books")?.isCompleted == true)
        #expect(reminder("Return library books")?.status == nil)

        // A read-only calendar is refused before anything is sent.
        #expect(throws: PhoneCalendarError.notWritable) {
            try loop.calendars.addEvent(EventDraft(title: "Day off", start: Date(), end: Date() + 3600, calendarID: "holidays"))
        }
    }
}
