import HomePadCore
import HomePadUI
import SwiftUI

/// Which person the editor works on.
enum PersonEditorRequest: Identifiable {
    case add
    case edit(HouseholdMember)

    var id: String {
        switch self {
        case .add: "add"
        case .edit(let member): member.id.uuidString
        }
    }
}

/// Add or edit a person: name, emoji avatar, accent color from the curated
/// palette, and admin rights. Admin access is checked by the caller.
struct PersonEditorView: View {
    let request: PersonEditorRequest
    @Environment(Household.self) private var household
    @Environment(SettingsStore.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var member: HouseholdMember
    @State private var confirmsRemoval = false

    init(request: PersonEditorRequest) {
        self.request = request
        switch request {
        case .add:
            _member = State(initialValue: HouseholdMember(name: "", avatar: AvatarChoices.emoji[0],
                                                          colorHex: Theme.Palette.swatches[0].hex))
        case .edit(let existing):
            _member = State(initialValue: existing)
        }
    }

    private var isNew: Bool {
        if case .add = request { return true }
        return false
    }

    /// The last admin cannot lose admin rights, and the first person is always an admin.
    private var adminLocked: Bool {
        let otherAdmins = household.members.filter { $0.isAdmin && $0.id != member.id }
        return otherAdmins.isEmpty
    }

    var body: some View {
        SheetScreen(isNew ? "Add Person" : (member.name.isEmpty ? "Edit Person" : member.name)) {
            GlassCapsuleButton(isNew ? "Add" : "Save", isProminent: true, action: save)
                .disabled(member.name.trimmingCharacters(in: .whitespaces).isEmpty)
        } content: {
            Form {
                Section {
                    HStack {
                        Spacer()
                        AvatarView(member: member, size: 112)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }
                Section("Name") {
                    TextField("Name", text: $member.name)
                        .font(.title3)
                        .textContentType(.givenName)
                }
                Section("Avatar") {
                    AvatarEmojiGrid(selection: $member.avatar)
                }
                Section("Color") {
                    PaletteSwatchPicker(selection: $member.colorHex)
                }
                Section {
                    Toggle("Admin", isOn: $member.isAdmin)
                        .disabled(adminLocked)
                } footer: {
                    Text(adminLocked
                         ? "At least one person must be an admin."
                         : "Admins can change kiosk settings and add, edit or remove people.")
                }
                Section("Face Recognition") {
                    Label(member.hasFaceEnrollment ? "Face recognized on this HomePad" : "Not set up on this HomePad yet",
                          systemImage: member.hasFaceEnrollment ? "faceid" : "face.dashed")
                    if !member.hasFaceEnrollment {
                        Text("Set up face recognition in the Presence settings so this HomePad knows who is in front of it. "
                             + "Face data stays on the HomePad that learned it, so each HomePad learns each person itself.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if !isNew {
                    Section {
                        Button("Remove \(member.name)", role: .destructive) { confirmsRemoval = true }
                    }
                }
            }
            .confirmationDialog("Remove \(member.name)?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("Remove", role: .destructive, action: remove)
            } message: {
                Text("Their Home Screen and preferences on this HomePad are deleted.")
            }
        }
        .onAppear {
            if adminLocked { member.isAdmin = true }
        }
    }

    private func remove() {
        household.remove(member.id)
        settings.reset(ShellSettings.homeScreenLayout(for: member.id))
        settings.reset(ShellSettings.wallpaper(for: member.id))
        dismiss()
    }

    private func save() {
        member.name = member.name.trimmingCharacters(in: .whitespaces)
        if isNew {
            household.add(member)
        } else {
            household.update(member)
        }
        dismiss()
    }
}

/// Curated avatar emoji.
enum AvatarChoices {
    static let emoji = ["🙂", "😀", "😎", "🤓", "🥳", "😺", "🐶", "🦊", "🐼", "🐨", "🦁", "🐸",
                        "🐵", "🦄", "🐙", "🌻", "🌈", "⭐️", "🚀", "🎸", "⚽️", "🎨", "☕️", "🍕"]
}

/// A grid of the curated avatar emoji.
struct AvatarEmojiGrid: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s), count: 8), spacing: Theme.Spacing.s) {
            ForEach(AvatarChoices.emoji, id: \.self) { emoji in
                Button {
                    selection = emoji
                } label: {
                    Text(emoji)
                        .font(.system(size: 32))
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(selection == emoji ? Color.primary.opacity(0.25) : .clear))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == emoji ? .isSelected : [])
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
