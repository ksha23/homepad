import HomePadCore
import HomePadUI
import SwiftUI

/// The ingredient checklist with serving scaling and units. Unticked items go
/// to the Groceries reminders list with the header's one action, which keeps
/// its words beside the short title. Sharing the list is its last row.
struct IngredientsPanel: View {
    let context: KitchenContext
    @Bindable var session: RecipeSession
    @State private var groceriesMessage: String?
    @State private var isAdding = false

    var body: some View {
        SheetScreen("Ingredients") {
            GlassCapsuleButton(addTitle, systemImage: "cart.badge.plus", isProminent: true, tint: .orange, action: addMissing)
                .disabled(session.missingIngredients.isEmpty || isAdding)
        } content: {
            List {
                Section {
                    if session.canScale {
                        Stepper(value: $session.servings, in: 1...48) {
                            Label("Serves \(session.servings)", systemImage: "person.2")
                                .font(.title3.weight(.semibold))
                        }
                    }
                    Picker("Units", selection: $session.unitSystem) {
                        ForEach(UnitSystem.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                }
                Section {
                    ForEach(Array(session.displayIngredients.enumerated()), id: \.offset) { index, ingredient in
                        row(index: index, ingredient: ingredient)
                    }
                } header: {
                    SectionHeader("Tap what you have", systemImage: "checklist")
                } footer: {
                    if let footer = groceriesMessage ?? (session.missingIngredients.isEmpty ? "Everything is ready." : nil) {
                        Text(footer).font(.callout)
                    }
                }
                Section {
                    ShareLink(item: RecipeShareText.text(for: session.recipe, ingredients: session.displayIngredients.map(\.text))) {
                        Label("Share Ingredients", systemImage: "square.and.arrow.up")
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial)
    }

    /// "Add 3 to Groceries", the unticked items. Dimmed when every item is ticked.
    private var addTitle: String {
        let count = session.missingIngredients.count
        return count == 0 ? "Add to Groceries" : "Add \(count) to Groceries"
    }

    private func row(index: Int, ingredient: DisplayIngredient) -> some View {
        let isChecked = session.checkedIngredients.contains(index)
        return Button {
            session.toggleIngredient(index)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? .orange : .secondary)
                    .font(.title2)
                Group {
                    if let amount = ingredient.amount {
                        Text("\(Text(amount).foregroundStyle(.orange).fontWeight(.semibold)) \(ingredient.name)")
                    } else {
                        Text(ingredient.name)
                    }
                }
                .font(.title3)
                .strikethrough(isChecked, color: .secondary)
                .foregroundStyle(isChecked ? .secondary : .primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }

    private func addMissing() {
        isAdding = true
        Task {
            do {
                let count = try await context.addMissingToGroceries()
                groceriesMessage = "Added \(count) \(count == 1 ? "item" : "items") to Groceries."
            } catch {
                groceriesMessage = "Could not add to Groceries. \(error.localizedDescription)"
            }
            isAdding = false
        }
    }
}
