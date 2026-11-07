import CommsKit
import HomePadCore
import SwiftUI

/// Hub address and token for the recognized member. Only that person can edit
/// their own, so nobody reads or replaces someone else's connection.
struct CommsSettingsView: View {
    @Environment(CommsRuntime.self) private var runtime
    @State private var address = ""
    @State private var token = ""
    @State private var result: String?

    var body: some View {
        Form {
            if let member = runtime.currentMember {
                Section("Your Mac for \(member.name)") {
                    TextField("https://your-mac.tailnet.ts.net", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Hub token", text: $token)
                    Button("Save and connect") { save(member.id) }
                    Button("Clear saved messages on this iPad", role: .destructive) {
                        runtime.store.forgetSavedMessages(for: member.id)
                        result = "Saved copy removed. It is rebuilt the next time you open Messages."
                    }
                    if let result { Text(result).font(.footnote).foregroundStyle(.secondary) }
                }
                Section {
                    Toggle("Require face recognition", isOn: Binding(
                        get: { runtime.requiresRecognition },
                        set: { runtime.services.settings[CommsSettings.requireRecognition] = $0; runtime.sync() }
                    ))
                } footer: {
                    Text("When on, your messages show only while the iPad recognizes your face. On by default once the household has more than one person.")
                }
                Section {
                    Toggle("Show previews on the face", isOn: Binding(
                        get: { runtime.services.settings[CommsSettings.showPreviewsOnFace] },
                        set: { runtime.services.settings[CommsSettings.showPreviewsOnFace] = $0 }
                    ))
                } footer: {
                    Text("A new message on the face shows who wrote it. Turn this on to show the text too. Anyone who can see the iPad can read it.")
                }
                Section {
                    Text("Run homepad-hub on a Mac signed in with your Apple ID. See docs/COMMS.md.").font(.footnote)
                }
                .onAppear { load(member.id) }
            } else {
                ContentUnavailableView("Look at the iPad", systemImage: "faceid", description: Text("Messages settings open for the person it recognizes."))
            }
        }
    }

    private func load(_ member: UUID) {
        let stored = runtime.credentials.credentials(for: member)
        address = stored?.baseURL.absoluteString ?? ""
        token = stored?.token ?? ""
    }

    private func save(_ member: UUID) {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespaces)), url.scheme != nil, !token.isEmpty else {
            result = "Enter the hub address and token."
            return
        }
        runtime.credentials.save(HubCredentials(baseURL: url, token: token), for: member)
        runtime.sync()
        result = "Saved. Connecting."
    }
}
