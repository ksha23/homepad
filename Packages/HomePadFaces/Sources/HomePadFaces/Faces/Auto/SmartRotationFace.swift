import HomePadCore
import HomePadUI
import SwiftUI

/// `faces.auto`: shows whichever face fits the moment. Rules (night,
/// mornings, a ringing doorbell, a recognized person) are checked in order,
/// and the fallback is the household's choice. Rules are edited in the Faces
/// app and in Settings.
struct SmartRotationFace: View {
    static let rules = FaceOption(id: "rules", title: "Rules", kind: .custom { _ in AnyView(RotationRulesEditor()) })

    static let definition = FaceDefinition(
        id: RotationEngine.selfID, title: "Smart Rotation", summary: "Picks the right face for the moment",
        systemImage: "wand.and.stars", sortOrder: 0, options: [rules],
        // It shows other faces, each with its own widgets.
        widgets: .unsupported
    ) { SmartRotationFace() }

    @Environment(\.faceInsets) private var faceInsets

    @Environment(FacesRuntime.self) private var runtime
    @Environment(ModuleRegistry.self) private var registry
    @Environment(AppServices.self) private var services
    @Environment(\.displayCondition) private var condition
    @Environment(\.proximity) private var proximity

    var body: some View {
        FaceTimeline(.minute) { date in
            let decision = RotationEngine.decide(runtime.rotation.current, context: context(at: date))
            ZStack(alignment: .bottom) {
                if let face = registry.face(decision.faceID) {
                    face.makeView()
                        .id(decision.faceID)
                        .transition(.opacity)
                }
                // Why this face shows, up close. Behind the Home Screen only the
                // face it shows draws, as its own backdrop.
                if proximity >= .mid {
                    reason(for: decision)
                        .padding(.bottom, faceInsets.bottom)
                        .faceForeground()
                        .transition(.proximityDetail)
                }
            }
            .animation(.smooth(duration: 1.2), value: decision)
        }
    }

    private func context(at date: Date) -> RotationContext {
        RotationContext(
            now: date,
            displayCondition: condition,
            lastActivity: runtime.activity.lastSeen,
            memberFaceID: memberFaceID,
            availableFaceIDs: Set(registry.faces.map(\.id))
        )
    }

    /// The recognized member's own current face, when they saved faces of their own.
    private var memberFaceID: String? {
        guard services.household.isPersonalContentUnlocked, let member = services.household.activeMember else { return nil }
        let owner = FaceOwner.member(member.id)
        guard runtime.library.hasOwnList(owner) else { return nil }
        return runtime.library.current(for: owner).faceID
    }

    /// A small pill saying why this face is showing, visible up close (the
    /// same distance every face shows its detail at).
    private func reason(for decision: RotationDecision) -> some View {
        let rule = runtime.rotation.current.rules.first { $0.id == decision.ruleID }
        return GlassPill(rule?.trigger.title ?? "Your Choice", systemImage: rule?.trigger.systemImage ?? "wand.and.stars")
            .nightModeAware()
    }
}
