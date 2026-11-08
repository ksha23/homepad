import HomePadCore
import HomePadUI
import SwiftUI

/// The People menu from the avatar button (HomeView's switcher): pick a member
/// or Guest, add a person, or manage people in Settings.
struct PeopleMenuView: View {
    @Environment(AppServices.self) private var services
    @Environment(Household.self) private var household
    @Environment(ShellNavigator.self) private var navigator
    @State private var editor: PersonEditorRequest?
    @State private var authMessage: String?

    var body: some View {
        GlassPanel(cornerRadius: Theme.Radius.tile, padding: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 0) {
                Text("People")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Spacing.m)
                    .padding(.vertical, Theme.Spacing.s)
                if services.presence.isRecognitionStarting {
                    recognitionStartingNote
                }
                ForEach(household.members) { member in
                    row(title: member.name, subtitle: status(for: member), isSelected: household.activeMemberID == member.id) {
                        AvatarView(member: member, size: 44)
                    } action: {
                        household.select(member.id)
                        navigator.panel = nil
                    }
                }
                row(title: "Guest", subtitle: nil, isSelected: household.isGuest) {
                    AvatarView(member: nil, size: 44)
                } action: {
                    household.signOut()
                    navigator.panel = nil
                }
                Divider().padding(.vertical, Theme.Spacing.xs)
                if household.members.count < Household.maxMembers {
                    row(title: "Add Person", subtitle: nil, isSelected: false) {
                        Image(systemName: "plus").font(.title3.weight(.semibold)).frame(width: 44, height: 44)
                    } action: {
                        Task { await addPerson() }
                    }
                }
                row(title: "Manage People", subtitle: nil, isSelected: false) {
                    Image(systemName: "person.2.badge.gearshape").font(.title3).frame(width: 44, height: 44)
                } action: {
                    navigator.openSettings(pane: ShellPaneID.people)
                }
                if let authMessage {
                    Text(authMessage).font(.footnote).foregroundStyle(.secondary).padding(Theme.Spacing.s)
                }
            }
        }
        .frame(width: 340)
        .sheet(item: $editor) { request in
            PersonEditorView(request: request)
        }
    }

    /// While face recognition loads after launch, nobody can be recognized yet.
    private var recognitionStartingNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            ProgressView()
            Text("Face recognition is starting. Until then HomePad shows guest content.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        .accessibilityElement(children: .combine)
    }

    private func row<Icon: View>(
        title: String, subtitle: String?, isSelected: Bool,
        @ViewBuilder icon: () -> Icon, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.s) {
                icon()
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.title3.weight(.medium))
                    if let subtitle {
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").font(.headline).foregroundStyle(.tint)
                }
            }
            .padding(.horizontal, Theme.Spacing.m)
            .padding(.vertical, Theme.Spacing.xs)
            .frame(minHeight: Theme.Size.tapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func status(for member: HouseholdMember) -> String? {
        guard household.activeMemberID == member.id else { return member.isAdmin ? "Admin" : nil }
        return household.isPersonalContentUnlocked ? "Recognized" : "Not recognized yet"
    }

    private func addPerson() async {
        let outcome = await AdminAuthorizer.authorize(household: household, reason: "Add a person to this HomePad")
        if outcome.isAllowed {
            authMessage = nil
            editor = .add
        } else if case .denied(let message) = outcome {
            authMessage = "Only an admin can add people. \(message)"
        }
    }
}
