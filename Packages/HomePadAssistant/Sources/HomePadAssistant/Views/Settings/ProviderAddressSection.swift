import HomePadCore
import SwiftUI

/// The server address. Prominent for local servers (Ollama, LM Studio), tucked
/// under Advanced for cloud providers where it is only for proxies.
struct ProviderAddressSection: View {
    let descriptor: ProviderDescriptor
    @Binding var draft: String
    let save: (String) -> Void
    @State private var showsAdvanced = false

    var body: some View {
        Section {
            if descriptor.allowsCustomBaseURL {
                field
            } else {
                DisclosureGroup("Advanced", isExpanded: $showsAdvanced) { field }
            }
        } header: {
            Text(descriptor.allowsCustomBaseURL ? "Server Address" : "Address")
        } footer: {
            Text(footer)
        }
    }

    private var field: some View {
        TextField(descriptor.defaultBaseURL?.absoluteString ?? "https://", text: $draft)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onSubmit { save(draft.trimmingCharacters(in: .whitespaces)) }
    }

    private var footer: String {
        if descriptor.allowsCustomBaseURL {
            return "Use the computer's network address, for example http://192.168.1.20\(descriptor.defaultBaseURL.map { ":\($0.port ?? 80)\($0.path())" } ?? ""). The server must accept connections from other devices."
        }
        return "Only for proxies or compatible gateways. Leave empty to use \(descriptor.defaultBaseURL?.absoluteString ?? "the default")."
    }
}
