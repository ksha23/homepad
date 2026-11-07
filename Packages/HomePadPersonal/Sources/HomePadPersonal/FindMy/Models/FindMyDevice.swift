import Foundation
import HomePadCore

/// A tracked device as Find My shows it: the backend's device, whose it is,
/// and what kind of device it is.
struct FindMyDevice: Identifiable, Hashable, Sendable {
    let tracked: TrackedDevice
    let ownership: FindMyOwnership
    /// The household member it belongs to, when there is one.
    let owner: HouseholdMember?

    var id: TrackedDevice.ID { tracked.id }

    var kind: FindMyDeviceKind { FindMyDeviceKind(model: tracked.model, name: tracked.name) }

    /// "Kyle's iPhone": the device's name, with its owner in front when the name
    /// does not already say whose it is.
    var title: String {
        guard let owner, !FindMyOwnerMatcher.normalized(tracked.name).contains(FindMyOwnerMatcher.normalized(firstName(of: owner))) else {
            return tracked.name
        }
        return "\(firstName(of: owner))'s \(tracked.name)"
    }

    /// The owner's member color, else white, for pins and row icons.
    var colorHex: String? { owner?.colorHex }

    private func firstName(of member: HouseholdMember) -> String {
        String(member.name.split(separator: " ").first ?? Substring(member.name))
    }
}
