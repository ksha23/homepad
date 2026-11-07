import Foundation

/// A member's own iPhone or Mac vouching for them, for the recognition gate's
/// Use Personal Device. The gate asks the member's paired device, the person
/// approves there with Face ID or a passcode, and the gate then recognizes
/// them as Use Face ID does. The Connect module installs the real service.
@MainActor
public protocol PersonalDeviceService: AnyObject {
    /// The device that can approve for `member`, such as "Kyle's iPhone", or
    /// nil when none is set up. The gate shows Use Personal Device only when
    /// there is one.
    func approvingDeviceName(for member: HouseholdMember.ID) -> String?

    /// Asks the member's device to approve opening an app, and returns once
    /// the person answers, the request expires or the device cannot be
    /// reached. Cancelling the calling task withdraws the request.
    func requestApproval(for member: HouseholdMember.ID, appID: String, appTitle: String) async -> PersonalDeviceApproval
}

/// How a personal device answered.
public enum PersonalDeviceApproval: Equatable, Sendable {
    /// The person approved on their device with Face ID or a passcode.
    case approved
    /// The person said no on their device.
    case denied
    /// Nobody answered before the request ran out.
    case expired
    /// The request never reached a device, with the reason in words.
    case unavailable(String)
}

/// Used until a module installs a real service: no member has a personal device.
@MainActor
public final class NoPersonalDevices: PersonalDeviceService {
    public init() {}

    public func approvingDeviceName(for member: HouseholdMember.ID) -> String? { nil }

    public func requestApproval(for member: HouseholdMember.ID, appID: String, appTitle: String) async -> PersonalDeviceApproval {
        .unavailable("No personal device is set up for this person.")
    }
}
