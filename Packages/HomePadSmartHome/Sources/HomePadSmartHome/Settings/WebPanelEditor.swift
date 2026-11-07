import HomePadCore
import HomePadUI
import SwiftUI

/// Name, icon (from a small set) and address of one web panel.
struct WebPanelEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var panel: WebPanel
    let onSave: (WebPanel) -> Void

    var body: some View {
        SheetScreen(panel.name.isEmpty ? "Web Panel" : panel.name) {
            GlassCapsuleButton("Save", isProminent: true) {
                onSave(panel)
                dismiss()
            }
            .disabled(panel.name.isEmpty || panel.resolvedURL == nil)
        } content: {
            Form {
                TextField("Name", text: $panel.name)
                TextField("Address, for example http://frigate.local:5000", text: $panel.url)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: Theme.Spacing.m) {
                        ForEach(WebPanelSymbol.allCases, id: \.self) { symbol in
                            Button {
                                panel.symbol = symbol
                            } label: {
                                Image(systemName: symbol.rawValue)
                                    .font(.title2)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(panel.symbol == symbol ? Color.accentColor : Color.secondary.opacity(0.2)))
                                    .foregroundStyle(panel.symbol == symbol ? Color.white : Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.s)
                }
            }
        }
    }
}
