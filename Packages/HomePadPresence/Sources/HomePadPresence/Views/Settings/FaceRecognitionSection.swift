import HomePadCore
import HomePadUI
import SwiftUI

/// Face recognition switch, strictness and per-member enrollment.
struct FaceRecognitionSection: View {
    let presence: LivePresenceService
    let enroll: (HouseholdMember) -> Void
    @Environment(AppServices.self) private var services
    @State private var pendingDelete: HouseholdMember?

    var body: some View {
        let settings = services.settings
        let recognition = presence.recognition
        Section {
            Toggle("Face Recognition", isOn: settings.binding(CoreSettings.faceRecognitionEnabled))
            if settings[CoreSettings.faceRecognitionEnabled] {
                LabeledSegmentedPicker(
                    "Match", selection: settings.binding(PresenceSettings.recognitionStrictness),
                    options: RecognitionStrictness.allCases, optionTitle: \.title
                )
                if services.household.members.isEmpty {
                    Text("Add people in the People settings first.")
                        .foregroundStyle(.secondary)
                }
                ForEach(services.household.members) { member in
                    row(member, enrolled: recognition.hasEnrollment(member.id), learned: recognition.learnedCount(for: member.id))
                        // Each row asks about its own person. On the section the
                        // dialog's popover would point at another row.
                        .confirmationDialog(
                            "Delete face data for \(member.name)?", isPresented: deleteBinding(for: member), titleVisibility: .visible
                        ) {
                            Button("Delete Face Data", role: .destructive) { recognition.deleteEnrollment(memberID: member.id) }
                        }
                }
            }
            if let error = recognition.storageError {
                Text(error).font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("Face Recognition")
        } footer: {
            Text("Recognizes up to \(Household.maxMembers) people on this iPad and unlocks their personal content. While someone stays recognized, it learns how they look from new angles and distances. Face data is encrypted, stays on this iPad, is never synced to iCloud or to the household's other HomePads, and is deleted when a person is removed. People added on another HomePad set up their face here too. Recognition can be fooled by look-alikes and family resemblance, so keep sensitive actions behind Face ID.")
        }
    }

    private func row(_ member: HouseholdMember, enrolled: Bool, learned: Int) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            AvatarView(member: member, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                Text(status(enrolled: enrolled, learned: learned))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if enrolled {
                Menu("Options") {
                    Button("Set Up Again", systemImage: "arrow.clockwise") { enroll(member) }
                    if learned > 0 {
                        Button("Reset Learned Looks", systemImage: "arrow.counterclockwise") {
                            presence.recognition.resetLearned(memberID: member.id)
                        }
                    }
                    Button("Delete Face Data", systemImage: "trash", role: .destructive) { pendingDelete = member }
                }
            } else {
                Button("Set Up") { enroll(member) }
                    .buttonStyle(.glass)
            }
        }
    }

    private func status(enrolled: Bool, learned: Int) -> String {
        guard enrolled else { return "Not set up on this HomePad yet" }
        switch learned {
        case 0: return "Face set up"
        case 1: return "Face set up, 1 learned look"
        default: return "Face set up, \(learned) learned looks"
        }
    }

    /// Whether this person's row asks to delete their face data.
    private func deleteBinding(for member: HouseholdMember) -> Binding<Bool> {
        Binding(get: { pendingDelete?.id == member.id }, set: { if !$0 { pendingDelete = nil } })
    }
}
