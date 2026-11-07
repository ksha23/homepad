import HomePadCore
import HomePadUI
import SwiftUI

/// Settings, AI Assistant: providers, who uses which, personality, voice and listening.
/// A grouped Form like iOS Settings, with curated choices.
struct AssistantSettingsView: View {
    @Environment(AppServices.self) private var services
    @State private var selectedProvider: ProviderDescriptor?
    @State private var editingMember: HouseholdMember?
    @State private var showingFallbackOrder = false
    /// Bumped after keychain edits, which SwiftUI cannot observe.
    @State private var keyRevision = 0

    var body: some View {
        let store = ProviderStore(settings: services.settings, keychain: services.keychain)
        let _ = keyRevision
        Form {
            providers(store)
            routing(store)
            people(store)
            personality
            VoiceSettingsSection()
            ListeningSettingsSection()
            history
        }
        .onAppear { selectedProvider = selectedProvider ?? AssistantDemo.requestedProvider }
        .sheet(item: $selectedProvider) { descriptor in
            ProviderDetailView(descriptor: descriptor) { keyRevision += 1 }
        }
        .sheet(item: $editingMember) { member in
            MemberAssistantSheet(member: member, readyProviders: store.readyProviders)
        }
        .sheet(isPresented: $showingFallbackOrder) {
            FallbackOrderSheet(readyProviders: store.readyProviders)
        }
    }

    private func providers(_ store: ProviderStore) -> some View {
        Section {
            ForEach(ProviderCatalog.all) { descriptor in
                Button { selectedProvider = descriptor } label: {
                    ProviderRow(descriptor: descriptor, status: store.status(of: descriptor))
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Providers")
        } footer: {
            Text("Apple Intelligence runs on this iPad. Other providers need an account and an API key, and receive your requests.")
        }
    }

    private func routing(_ store: ProviderStore) -> some View {
        Section {
            Picker("Default Provider", selection: services.settings.binding(AssistantSettings.defaultProvider)) {
                Text("Automatic").tag("")
                ForEach(store.readyProviders) { Text($0.displayName).tag($0.id) }
            }
            Button("Fallback Order") { showingFallbackOrder = true }
        } header: {
            Text("Choosing a Provider")
        } footer: {
            Text("If a provider cannot answer, HomePad tries the next one in the fallback order.")
        }
    }

    @ViewBuilder
    private func people(_ store: ProviderStore) -> some View {
        let members = services.household.members
        if !members.isEmpty {
            Section("People") {
                ForEach(members) { member in
                    Button { editingMember = member } label: {
                        HStack(spacing: Theme.Spacing.m) {
                            AvatarView(member: member, size: 36)
                            Text(member.name)
                            Spacer()
                            Text(summary(for: member, store: store)).foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                        }
                        // The whole row takes the tap, not only its words. A plain
                        // button left the gap in the middle dead.
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var personality: some View {
        Section {
            Picker("Personality", selection: services.settings.binding(AssistantSettings.personality)) {
                ForEach(Personality.allCases) { style in
                    VStack(alignment: .leading) {
                        Text(style.displayName)
                        Text(style.summary).font(.footnote).foregroundStyle(.secondary)
                    }
                    .tag(style)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Personality")
        } footer: {
            Text("The household default. Each person can pick their own.")
        }
    }

    private var history: some View {
        Section {
            Button("Clear Conversation History", role: .destructive) {
                (services.assistant as? AssistantRuntime)?.conversations.clear(for: services.household.unlockedMember?.id)
            }
        } footer: {
            Text("Conversations stay on this iPad, kept separately for each recognized person and for guests. Someone picked by hand without being recognized sees the guest conversation.")
        }
    }

    private func summary(for member: HouseholdMember, store: ProviderStore) -> String {
        let prefs = MemberAssistantPreferences(member: member)
        let provider = prefs.providerID.flatMap(ProviderCatalog.descriptor)?.displayName ?? "Default"
        return [provider, prefs.personality?.displayName].compactMap { $0 }.joined(separator: ", ")
    }
}
