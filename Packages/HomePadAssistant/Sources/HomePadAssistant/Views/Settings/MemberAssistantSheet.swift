import HomePadCore
import HomePadUI
import SwiftUI

/// One person's assistant choices: provider, model, personality and a short "About me".
struct MemberAssistantSheet: View {
    let member: HouseholdMember
    let readyProviders: [ProviderDescriptor]

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var prefs: MemberAssistantPreferences

    init(member: HouseholdMember, readyProviders: [ProviderDescriptor]) {
        self.member = member
        self.readyProviders = readyProviders
        _prefs = State(initialValue: MemberAssistantPreferences(member: member))
    }

    var body: some View {
        SheetScreen(member.name) {
            GlassCapsuleButton("Save", isProminent: true) {
                services.household.update(prefs.applied(to: member))
                dismiss()
            }
        } content: {
            Form {
                Section {
                    Picker("Provider", selection: $prefs.providerID) {
                        Text("Household Default").tag(String?.none)
                        ForEach(readyProviders) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    .onChange(of: prefs.providerID) { prefs.model = nil }
                    if let descriptor = prefs.providerID.flatMap(ProviderCatalog.descriptor), descriptor.wireFormat != .appleOnDevice {
                        Picker("Model", selection: $prefs.model) {
                            Text("Provider Default").tag(String?.none)
                            ForEach((descriptor.suggestedModels + [prefs.model].compactMap { $0 }).uniqued(), id: \.self) {
                                Text($0).tag(Optional($0))
                            }
                        }
                    }
                } footer: {
                    Text("Used when HomePad recognizes \(member.name).")
                }
                Section("Personality") {
                    Picker("Personality", selection: $prefs.personality) {
                        Text("Household Default").tag(Personality?.none)
                        ForEach(Personality.allCases) { Text($0.displayName).tag(Optional($0)) }
                    }
                }
                Section {
                    TextField("For example: I'm vegetarian and I wake up at 6.", text: $prefs.aboutMe, axis: .vertical)
                        .lineLimit(3...6)
                        .onChange(of: prefs.aboutMe) {
                            if prefs.aboutMe.count > MemberAssistantPreferences.aboutMeLimit {
                                prefs.aboutMe = String(prefs.aboutMe.prefix(MemberAssistantPreferences.aboutMeLimit))
                            }
                        }
                } header: {
                    Text("About Me")
                } footer: {
                    Text("Shared with the AI provider only after HomePad recognizes \(member.name). \(prefs.aboutMe.count) of \(MemberAssistantPreferences.aboutMeLimit) characters.")
                }
                Section {
                    if prefs.memories.isEmpty {
                        Text("No memories saved yet. When talking to HomePad, ask it to remember things about you.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(prefs.memories, id: \.self) { memory in
                            HStack {
                                Text(memory)
                                Spacer()
                                Button(role: .destructive) {
                                    prefs.memories.removeAll { $0 == memory }
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                } header: {
                    Text("Memories")
                } footer: {
                    Text("Details HomePad remembers when speaking with \(member.name).")
                }
            }
        }
    }
}
