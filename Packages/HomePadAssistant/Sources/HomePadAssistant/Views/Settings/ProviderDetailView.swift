import HomePadCore
import HomePadUI
import SwiftUI

/// One provider's settings: on or off, API key, address, model and a test.
struct ProviderDetailView: View {
    let descriptor: ProviderDescriptor
    /// Called after the key changes, since keychain edits are not observable.
    let onKeyChange: () -> Void

    @Environment(AppServices.self) private var services
    @State private var keyDraft = ""
    @State private var addressDraft = ""
    @State private var customModel = ""
    @State private var liveModels: [String] = []
    @State private var isLoadingModels = false
    @State private var modelError: String?
    @State private var testResult: String?
    @State private var isTesting = false
    @State private var revision = 0

    private var store: ProviderStore { ProviderStore(settings: services.settings, keychain: services.keychain) }

    var body: some View {
        let _ = revision
        let status = store.status(of: descriptor)
        // Every change saves as it is made, so the sheet only closes.
        SheetScreen(descriptor.displayName) {
            Form {
                Section {
                    ProviderRow(descriptor: descriptor, status: status, showsChevron: false)
                    if case .unavailable(let reason) = status {
                        Text(reason).foregroundStyle(.secondary)
                    }
                    Toggle("Use \(descriptor.displayName)", isOn: enabledBinding)
                        .disabled(!(status == .ready || status == .off))
                }
                if descriptor.requiresAPIKey { keySection }
                if descriptor.wireFormat != .appleOnDevice {
                    ProviderAddressSection(descriptor: descriptor, draft: $addressDraft) { save(address: $0) }
                    modelSection
                }
                testSection(status)
            }
        }
        .onAppear { addressDraft = store.settings(for: descriptor.id).baseURL ?? "" }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { store.isEnabled(descriptor) }, set: { value in store.update(descriptor.id) { $0.isEnabled = value } })
    }

    private var keySection: some View {
        Section {
            if store.apiKey(for: descriptor) != nil {
                LabeledContent("API Key", value: "Saved")
                Button("Remove Key", role: .destructive) { setKey(nil) }
            } else {
                SecureField("Paste your API key", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save Key") { setKey(keyDraft) }.disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let url = descriptor.keyURL { Link("Get an API Key", destination: url) }
        } header: {
            Text("API Key")
        } footer: {
            Text("Stored in the keychain and shared with your other devices through iCloud Keychain. Never shown again after saving.")
        }
    }

    private var modelSection: some View {
        Section {
            Picker("Model", selection: modelBinding) {
                ForEach(modelChoices, id: \.self) { Text($0).tag($0) }
            }
            Button {
                Task { await loadModels() }
            } label: {
                HStack {
                    Text("Load Available Models")
                    if isLoadingModels { Spacer(); ProgressView() }
                }
            }
            .disabled(isLoadingModels || store.status(of: descriptor) == .needsKey)
            HStack {
                TextField("Other model ID", text: $customModel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Use") {
                    store.update(descriptor.id) { $0.model = customModel.trimmingCharacters(in: .whitespaces) }
                    customModel = ""
                    revision += 1
                }
                .disabled(customModel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Model")
        } footer: {
            Text(modelError ?? "People can also pick their own model in People.")
        }
    }

    private func testSection(_ status: ProviderStatus) -> some View {
        Section {
            Button {
                Task { await runTest() }
            } label: {
                HStack {
                    Text("Test \(descriptor.displayName)")
                    if isTesting { Spacer(); ProgressView() }
                }
            }
            .disabled(isTesting || !(status == .ready || status == .off))
            if let testResult { Text(testResult).foregroundStyle(.secondary) }
        } footer: {
            Text("Sends one short message to check the key, address and model.")
        }
    }

    private var modelBinding: Binding<String> {
        Binding(get: { store.model(for: descriptor) }, set: { value in
            store.update(descriptor.id) { $0.model = value }
            revision += 1
        })
    }

    private var modelChoices: [String] {
        (descriptor.suggestedModels + liveModels + [store.model(for: descriptor)]).uniqued()
    }

    private func setKey(_ key: String?) {
        store.setAPIKey(key, for: descriptor)
        keyDraft = ""
        revision += 1
        onKeyChange()
    }

    private func save(address: String) {
        store.update(descriptor.id) { $0.baseURL = address.isEmpty ? nil : address }
        revision += 1
    }

    private func loadModels() async {
        isLoadingModels = true
        modelError = nil
        defer { isLoadingModels = false }
        do {
            liveModels = try await ProviderFactory.make(store.config(for: descriptor)).listModels()
            if liveModels.isEmpty { modelError = "The provider returned no models." }
        } catch {
            modelError = error.localizedDescription
        }
    }

    private func runTest() async {
        isTesting = true
        defer { isTesting = false }
        switch await ProviderTester.test(store.config(for: descriptor)) {
        case .success(let message): testResult = message
        case .failure(let error): testResult = error.localizedDescription
        }
    }
}
