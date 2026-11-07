import Foundation
import HomePadCore

/// Assistant tools for Find My: where devices are, and ringing one. Both need
/// a recognized member and answer only about the devices that person may see
/// in the Find My app (see `FindMyVisibilityPolicy`).
@MainActor
enum FindMyTools {
    static func make(findMy: FindMyService) -> [AssistantTool] {
        [findDevice(findMy), playSound(findMy)]
    }

    /// The most devices one answer lists, so "where is everything" stays short enough to speak.
    static let maxListed = 8
    /// How long one answer waits for street addresses before saying "away from home".
    static let addressWait: Duration = .seconds(3)

    static func findDevice(_ findMy: FindMyService) -> AssistantTool {
        AssistantTool(
            name: "find_device",
            description: "Where household members' phones, iPads, watches and Macs are, from Home Assistant (iCloud and the Home Assistant app), like Apple's Find My. Says the place (home, a zone such as Work, or a street), when it was last seen and the battery. Use for \"where is Kyle's iPhone\", \"where is everyone's phone\" or \"where did I leave my iPad\". AirTags and AirPods are not included.",
            parameters: Schema.object([
                "device": Schema.string("The device, for example \"iPhone\", \"iPad\", \"watch\" or a name such as \"Kitchen iPad\". Omit for every device."),
                "owner": Schema.string("Whose device: a person's name, \"me\" for the person asking, or \"everyone\". Omit for everyone."),
            ]),
            requiresRecognizedMember: true
        ) { arguments in
            if let problem = setupProblem(findMy) { return problem }
            let devices = FindMyDeviceMatcher.matches(
                device: arguments["device"]?.stringValue, owner: arguments["owner"]?.stringValue,
                in: findMy.visibleDevices, me: findMy.recognizedMember
            )
            guard !devices.isEmpty else { return notFound(arguments, in: findMy) }
            let listed = Array(devices.prefix(maxListed))
            let addresses = await addresses(for: listed, findMy: findMy)
            var lines = listed.map { device in
                FindMyWording.sentence(title: device.title, device: device.tracked, address: addresses[device.id])
            }
            if devices.count > listed.count { lines.append("And \(devices.count - listed.count) more in the Find My app.") }
            return lines.joined(separator: "\n")
        }
    }

    static func playSound(_ findMy: FindMyService) -> AssistantTool {
        AssistantTool(
            name: "play_sound_on_device",
            description: "Plays a sound on a phone, iPad, watch or Mac so someone can find it, like Find My's Play Sound. For example \"ping my iPad\" or \"make Sam's phone ring\".",
            parameters: Schema.object([
                "device": Schema.string("The device, for example \"iPad\", \"phone\" or \"Kitchen iPad\"."),
                "owner": Schema.string("Whose device: a person's name, or \"me\" for the person asking. Optional."),
            ], required: ["device"]),
            requiresRecognizedMember: true
        ) { arguments in
            if let problem = setupProblem(findMy) { return problem }
            let devices = FindMyDeviceMatcher.matches(
                device: arguments["device"]?.stringValue, owner: arguments["owner"]?.stringValue,
                in: findMy.visibleDevices, me: findMy.recognizedMember
            )
            guard let device = devices.first else { return notFound(arguments, in: findMy) }
            guard devices.count == 1 else {
                return "Which one: \(listed(devices.prefix(maxListed).map(\.title), joiner: "or"))?"
            }
            guard device.tracked.canPlaySound else { return FindMyService.cannotRing(device).localizedDescription }
            try await findMy.playSound(device)
            switch device.tracked.source {
            case .iCloud: return "Playing a sound on \(device.title)."
            case .companionApp, .other: return "Sent a loud alert to \(device.title). It rings even on silent."
            }
        }
    }

    /// A sentence when Find My has nothing to answer from, else nil.
    static func setupProblem(_ findMy: FindMyService) -> String? {
        switch findMy.setup {
        case .ready: nil
        case .noHomeAssistant: "Find My needs Home Assistant, which is not connected. An admin can connect it in Settings, under Smart Home."
        case .noTrackers: "Home Assistant has no phones or iPads with locations yet. Add the iCloud integration with an Apple Account, or the Home Assistant app on each device."
        case .nothingForViewer: "There are no devices for you in Find My. An admin can choose whose each device is in Settings, under Personal Info."
        }
    }

    private static func notFound(_ arguments: JSONValue, in findMy: FindMyService) -> String {
        let asked = [arguments["owner"]?.stringValue, arguments["device"]?.stringValue].compactMap { $0 }.joined(separator: " ")
        let names = listed(findMy.visibleDevices.prefix(maxListed).map(\.title), joiner: "and")
        return "I couldn't find \(asked.isEmpty ? "that device" : asked). I can see \(names)."
    }

    /// Street addresses for devices away from every zone, waiting at most `addressWait`.
    private static func addresses(for devices: [FindMyDevice], findMy: FindMyService) async -> [TrackedDevice.ID: String] {
        var found: [TrackedDevice.ID: String] = [:]
        let away = devices.filter { $0.tracked.place == .away && $0.tracked.hasLocation }
        let deadline = ContinuousClock.now + addressWait
        for device in away {
            if let known = findMy.cachedAddress(for: device.tracked) {
                found[device.id] = known
            } else if ContinuousClock.now < deadline, let looked = await withDeadline(deadline, { await findMy.address(for: device.tracked) }) {
                found[device.id] = looked
            }
        }
        return found
    }

    /// Runs `work`, giving up with nil at the deadline.
    private static func withDeadline(_ deadline: ContinuousClock.Instant, _ work: @escaping @MainActor () async -> String?) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(until: deadline, clock: .continuous)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    /// "A, B and C".
    private static func listed(_ names: [String], joiner: String) -> String {
        switch names.count {
        case 0: return "no devices"
        case 1: return names[0]
        default: return names.dropLast().joined(separator: ", ") + " \(joiner) " + (names.last ?? "")
        }
    }
}
