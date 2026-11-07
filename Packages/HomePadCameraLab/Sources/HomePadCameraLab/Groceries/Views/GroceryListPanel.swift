import HomePadUI
import SwiftUI

/// The running list for this scanning session, with Undo and Add Now.
struct GroceryListPanel: View {
    @Environment(CameraLab.self) private var lab

    var body: some View {
        let session = lab.groceries
        GlassPanel(padding: Theme.Spacing.l) {
            content(session)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .animation(.smooth, value: session.items)
    }

    private func content(_ session: GrocerySession) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack {
                SectionHeader("Adding to \(session.listName)", systemImage: "checklist")
                Spacer()
                if session.addedCount > 0 {
                    Text("\(session.addedCount) added").font(.headline).foregroundStyle(.green)
                }
            }
            if session.items.isEmpty {
                Text("Scanned items appear here. Each one waits \(Int(GrocerySession.undoWindow)) seconds before it goes to Reminders, so you can undo.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.s) {
                        ForEach(session.items) { item in
                            GroceryItemRow(item: item)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            if let message = session.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
            HStack(spacing: Theme.Spacing.m) {
                Button { session.undo() } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .disabled(!session.items.contains(where: \.canUndo))
                Button { session.addAllNow() } label: {
                    Label("Add Now", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(!session.hasPending)
            }
            .controlSize(.large)
        }
    }
}

/// One scanned item with its product photo and where it is in the flow.
private struct GroceryItemRow: View {
    let item: GroceryItem

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            AsyncImage(url: item.imageURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: item.barcode == nil ? "text.cursor" : "barcode")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, height: 52)
            .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.Radius.thumbnail, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.reminderTitle).font(.title3.weight(.semibold)).lineLimit(1)
                if let detail = [item.brand, item.quantity].compactMap({ $0 }).joined(separator: ", ").nilIfEmpty {
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            status
        }
        .padding(Theme.Spacing.s)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    @ViewBuilder
    private var status: some View {
        switch item.status {
        case .lookingUp, .adding:
            ProgressView()
        case .pending(let commitAt):
            Text(timerInterval: Date()...max(Date(), commitAt), countsDown: true)
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 44)
        case .added:
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.green)
        case .notFound:
            Text("Not found").font(.callout).foregroundStyle(.orange)
        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).help(message)
                .accessibilityLabel(message)
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
