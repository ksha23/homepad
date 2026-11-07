import HomePadCore
import HomePadUI
import SwiftUI

/// HomeView's privacy gate for personal apps: "Recognition Required to Open
/// Messages". Continue waits for the Presence module to recognize someone
/// (`household.isPersonalContentUnlocked`). Use Personal Device asks the
/// member's paired iPhone or Mac (`services.personalDevices`), where they
/// approve with Face ID or a passcode, and shows only when they have one. Use
/// Face ID verifies with the system sheet. Both then recognize the member.
/// When content unlocks, the shell opens the app.
///
/// The glyph, text and buttons are one group centered on the screen, as on HomeView.
struct RecognitionGateView: View {
    let appID: String
    @Environment(AppServices.self) private var services
    @Environment(ModuleRegistry.self) private var registry
    @Environment(Household.self) private var household
    @Environment(ShellNavigator.self) private var navigator
    @State private var isRecognizing = false
    @State private var chosenMemberID: HouseholdMember.ID?
    @State private var message: String?
    @State private var timeout: Task<Void, Never>?
    /// The device asked to approve, while it is being asked.
    @State private var askedDevice: String?
    @State private var approval: Task<Void, Never>?

    /// How long Continue waits before suggesting Face ID.
    private let recognitionTimeout: Duration = .seconds(20)

    private var appTitle: String {
        registry.app(appID)?.title ?? KnownAppID.displayName(for: appID)
    }

    /// Who Face ID would unlock: the picked member, the active one, or the only one.
    private var targetMember: HouseholdMember? {
        if let chosenMemberID { return household.members.first { $0.id == chosenMemberID } }
        if let active = household.activeMember { return active }
        return household.members.count == 1 ? household.members.first : nil
    }

    /// The member's paired iPhone or Mac, such as "Kyle's iPhone". Nil hides Use Personal Device.
    private var personalDevice: String? {
        targetMember.flatMap { services.personalDevices.approvingDeviceName(for: $0.id) }
    }

    /// Waiting for the camera or for a personal device.
    private var isWaiting: Bool { isRecognizing || askedDevice != nil }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Frosted toward the page color: dark in Dark, light in Light.
            Rectangle().fill(.regularMaterial).overlay(Color.screenBackground.opacity(0.35)).ignoresSafeArea()
            VStack(spacing: Theme.Spacing.l) {
                RecognitionGlyph(member: isWaiting ? targetMember : nil, isAnimating: isWaiting)
                VStack(spacing: Theme.Spacing.s) {
                    Text(title)
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text(detail)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                if household.members.isEmpty {
                    Text("Add yourself in People first, then come back.")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                } else if targetMember == nil {
                    memberChooser
                }
                buttons
                    .padding(.top, Theme.Spacing.m)
                if let message {
                    Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 560)
            .padding(Theme.Spacing.xl)
            // One group, centered on the screen.
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            CloseButton(action: cancel)
                .padding(Theme.Spacing.l)
        }
        .onDisappear {
            timeout?.cancel()
            approval?.cancel()
        }
        #if DEBUG
        .task { await debugUsePersonalDevice() }
        #endif
    }

    private var title: String {
        if let askedDevice { return "Check \(askedDevice)" }
        return isRecognizing ? "Recognizing…" : "Recognition Required to Open \(appTitle)"
    }

    private var detail: String {
        if let askedDevice { return "Approve on \(askedDevice) to open \(appTitle)." }
        return isRecognizing
            ? "Keep looking at this screen until you're recognized."
            : "\(appTitle) shows personal information, so HomePad needs to know it's you."
    }

    private var memberChooser: some View {
        VStack(spacing: Theme.Spacing.s) {
            Text("Who's opening \(appTitle)?").font(.headline).foregroundStyle(.secondary)
            HStack(spacing: Theme.Spacing.l) {
                ForEach(household.members) { member in
                    Button {
                        chosenMemberID = member.id
                    } label: {
                        VStack(spacing: Theme.Spacing.xs) {
                            AvatarView(member: member, size: Theme.Size.roundControl)
                            Text(member.name).font(.subheadline)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var buttons: some View {
        VStack(spacing: Theme.Spacing.s) {
            if household.members.isEmpty {
                Button {
                    navigator.openSettings(pane: ShellPaneID.people)
                } label: {
                    Text("Add People").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glassProminent)
            } else {
                if !isWaiting {
                    Button(action: startRecognizing) {
                        Text("Continue").frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glassProminent)
                }
                if let personalDevice {
                    Button(action: usePersonalDevice) {
                        Text(askedDevice == nil ? "Use Personal Device" : "Waiting for \(personalDevice)")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.glass)
                    .disabled(askedDevice != nil)
                }
                Button {
                    Task { await useFaceID() }
                } label: {
                    Label("Use Face ID", systemImage: "faceid").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.glass)
                .disabled(targetMember == nil)
            }
        }
        .font(.title3.weight(.semibold))
        .controlSize(.large)
    }

    private func startRecognizing() {
        stopAskingDevice()
        isRecognizing = true
        message = nil
        services.events.post(.wake)
        services.events.post(.custom(name: "shell.recognitionRequested", payload: ["appID": .string(appID)]))
        timeout?.cancel()
        timeout = Task {
            try? await Task.sleep(for: recognitionTimeout)
            guard !Task.isCancelled else { return }
            isRecognizing = false
            message = personalDevice == nil
                ? "HomePad couldn't recognize you. Try Face ID instead."
                : "HomePad couldn't recognize you. Try your personal device or Face ID instead."
        }
    }

    /// Asks the member's paired device. Approved there, the member is
    /// recognized here, as with Use Face ID.
    private func usePersonalDevice() {
        guard let member = targetMember, let device = personalDevice else { return }
        timeout?.cancel()
        isRecognizing = false
        message = nil
        askedDevice = device
        approval?.cancel()
        approval = Task {
            let outcome = await services.personalDevices.requestApproval(for: member.id, appID: appID, appTitle: appTitle)
            guard !Task.isCancelled else { return }
            askedDevice = nil
            switch outcome {
            case .approved:
                household.recognize(member.id)
            case .denied:
                message = "\(device) didn't allow it."
            case .expired:
                message = "\(device) didn't answer in time."
            case .unavailable(let reason):
                message = reason
            }
        }
    }

    /// Withdraws a request to a personal device, which puts its prompt away.
    private func stopAskingDevice() {
        approval?.cancel()
        approval = nil
        askedDevice = nil
    }

    private func useFaceID() async {
        guard let member = targetMember else { return }
        stopAskingDevice()
        let outcome = await DeviceOwnerAuthentication.verify(reason: "Open \(appTitle) as \(member.name)")
        switch outcome {
        case .allowed, .allowedWithoutPasscode:
            household.recognize(member.id)
        case .denied(let reason):
            message = reason
        }
    }

    private func cancel() {
        timeout?.cancel()
        stopAskingDevice()
        navigator.cancelGate()
    }

    #if DEBUG
    /// `-HomePadGateAction personalDevice` taps Use Personal Device once a
    /// paired device shows up, to check the approval between two simulators.
    private func debugUsePersonalDevice() async {
        guard UserDefaults.standard.string(forKey: "HomePadGateAction") == "personalDevice" else { return }
        for _ in 0..<120 where personalDevice == nil {
            try? await Task.sleep(for: .seconds(1))
        }
        // Gives a phone that is already paired time to find this iPad.
        try? await Task.sleep(for: .seconds(5))
        usePersonalDevice()
    }
    #endif
}

/// The face glyph, or the member's avatar with a spinning ring while recognizing.
private struct RecognitionGlyph: View {
    let member: HouseholdMember?
    let isAnimating: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(.primary.opacity(0.25), lineWidth: 6)
            if isAnimating {
                SpinningArc()
            }
            if let member {
                AvatarView(member: member, size: 116)
            } else {
                Image(systemName: "face.smiling")
                    .font(.system(size: 64, weight: .light))
            }
        }
        .frame(width: 140, height: 140)
        .accessibilityHidden(true)
    }
}

/// A quarter ring turning clockwise without end. A phase animator between 0
/// and 360 degrees turned it back the other way on every second pass.
private struct SpinningArc: View {
    @State private var isSpinning = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.25)
            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
            .padding(3)
            .rotationEffect(.degrees(isSpinning ? 360 : 0))
            .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: isSpinning)
            .onAppear { isSpinning = true }
    }
}
