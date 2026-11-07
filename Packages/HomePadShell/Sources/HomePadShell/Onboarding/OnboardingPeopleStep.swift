import HomePadCore
import HomePadUI
import SwiftUI

/// Step 3: add the people who live here. Each new person gets the next color
/// and emoji from the curated sets, and the first one is an admin.
struct OnboardingPeopleStep: View {
    @Environment(Household.self) private var household
    @State private var name = ""

    var body: some View {
        OnboardingStepLayout(
            systemImage: "person.2.fill",
            title: "Who Lives Here?",
            message: "Everyone gets their own Home Screen, wallpaper and face. Add up to \(Household.maxMembers) people now or later in Settings."
        ) {
            VStack(spacing: Theme.Spacing.m) {
                if !household.members.isEmpty {
                    HStack(spacing: Theme.Spacing.l) {
                        ForEach(household.members) { member in
                            VStack(spacing: Theme.Spacing.xs) {
                                AvatarView(member: member, size: Theme.Size.roundControl)
                                Text(member.name).font(.headline)
                            }
                        }
                    }
                }
                if household.members.count < Household.maxMembers {
                    HStack(spacing: Theme.Spacing.s) {
                        TextField("Name", text: $name)
                            .font(.title3)
                            .padding(Theme.Spacing.m)
                            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                            .onSubmit(add)
                            .submitLabel(.done)
                        Button("Add", systemImage: "plus", action: add)
                            .buttonStyle(.glassProminent)
                            .controlSize(.large)
                            .disabled(trimmedName.isEmpty)
                    }
                    .frame(maxWidth: 480)
                }
            }
        }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespaces)
    }

    private func add() {
        guard !trimmedName.isEmpty else { return }
        let index = household.members.count
        let swatches = Theme.Palette.swatches
        household.add(HouseholdMember(
            name: trimmedName,
            avatar: AvatarChoices.emoji[index % AvatarChoices.emoji.count],
            colorHex: swatches[index % swatches.count].hex,
            isAdmin: index == 0
        ))
        name = ""
    }
}
