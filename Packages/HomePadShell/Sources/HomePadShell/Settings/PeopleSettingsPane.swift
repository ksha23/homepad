import HomePadCore
import HomePadUI
import SwiftUI

/// Settings > People: who lives here, who is using HomePad now, and (for
/// admins) adding, editing and removing people.
struct PeopleSettingsPane: View {
    @Environment(Household.self) private var household
    @State private var editor: PersonEditorRequest?
    @State private var authMessage: String?

    var body: some View {
        Form {
            Section("Using HomePad Now") {
                HStack(spacing: Theme.Spacing.m) {
                    AvatarView(member: household.activeMember, size: 52)
                    VStack(alignment: .leading) {
                        Text(household.activeMember?.name ?? "Guest").font(.headline)
                        Text(sessionText).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !household.isGuest {
                        Button("Switch to Guest") { household.signOut() }
                    }
                }
            }
            Section {
                ForEach(household.members) { member in
                    Button {
                        Task { await requestEditor(.edit(member)) }
                    } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            AvatarView(member: member, size: 44)
                            VStack(alignment: .leading) {
                                Text(member.name).foregroundStyle(.primary)
                                Text(details(for: member)).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                }
                if household.members.count < Household.maxMembers {
                    Button {
                        Task { await requestEditor(.add) }
                    } label: {
                        Label("Add Person", systemImage: "plus.circle.fill")
                    }
                }
            } header: {
                Text("People")
            } footer: {
                Text(footerText)
            }
        }
        .sheet(item: $editor) { request in
            PersonEditorView(request: request)
        }
    }

    private var sessionText: String {
        if household.isGuest { return "Personal apps and widgets are hidden." }
        return household.isPersonalContentUnlocked ? "Recognized. Personal content is showing." : "Picked by hand. Personal content stays locked."
    }

    private var footerText: String {
        let base = "Up to \(Household.maxMembers) people. Each person gets their own Home Screen, wallpaper and face, "
            + "the same on every HomePad paired in the household. Face recognition is set up on each HomePad."
        guard let authMessage else { return base }
        return "\(base)\n\n\(authMessage)"
    }

    private func details(for member: HouseholdMember) -> String {
        var parts: [String] = []
        if member.isAdmin { parts.append("Admin") }
        parts.append(member.hasFaceEnrollment ? "Face recognition on" : "Face recognition not set up on this HomePad")
        return parts.joined(separator: " · ")
    }

    private func requestEditor(_ request: PersonEditorRequest) async {
        let outcome = await AdminAuthorizer.authorize(household: household, reason: "Manage the people on this HomePad")
        if outcome.isAllowed {
            authMessage = nil
            editor = request
        } else if case .denied(let reason) = outcome {
            authMessage = "Only an admin can change people. \(reason)"
        }
    }
}
