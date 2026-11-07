import HomePadCore
import HomePadUI
import SwiftUI

/// The week's shopping list: every planned recipe's ingredients from today on,
/// scaled to each meal's servings and added up, with the one action that
/// adds them to Groceries. Like the Ingredients panel, a tap marks what is
/// already in the kitchen, and items the Groceries list already has are set
/// apart so they are not added twice.
struct MealPlanGroceriesSheet: View {
    let context: KitchenContext
    let week: MealWeek
    @State private var groceries: MealPlanGroceries?
    /// Keys of the items marked as already in the kitchen.
    @State private var have: Set<String> = []
    @State private var message: String?
    @State private var isAdding = false
    @State private var hasAdded = false

    private var toAdd: [GroceryItem] {
        (groceries?.toAdd ?? []).filter { !have.contains($0.key) }
    }

    var body: some View {
        // Short like the Ingredients panel's title, so "Add 14 to Groceries"
        // keeps its words beside it. The section header names the days.
        SheetScreen("Ingredients") {
            GlassCapsuleButton(addTitle, systemImage: hasAdded ? "checkmark" : "cart.badge.plus", isProminent: true, action: add)
                .disabled(toAdd.isEmpty || isAdding || hasAdded)
        } content: {
            if let groceries {
                if groceries.mealCount == 0 {
                    EmptyStateView("Nothing Planned Ahead", message: "Put recipes on this week's days from today on, then come back.",
                                   systemImage: "calendar")
                } else {
                    list(groceries)
                }
            } else {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .presentationDetents([.large])
        .task {
            groceries = await context.groceries(for: context.shoppableMeals(in: week))
        }
    }

    /// "Add 14 to Groceries", the items not marked as at home.
    private var addTitle: String {
        if hasAdded { return "Added to Groceries" }
        return toAdd.isEmpty ? "Add to Groceries" : "Add \(toAdd.count) to Groceries"
    }

    private func list(_ groceries: MealPlanGroceries) -> some View {
        List {
            Section {
                ForEach(groceries.toAdd) { item in
                    row(item, isChecked: have.contains(item.key)) { toggle(item) }
                }
            } header: {
                SectionHeader(summary(groceries), systemImage: "cart")
            } footer: {
                Text(message ?? "Tap what you have. Amounts are each meal's servings, added up.")
                    .font(.callout)
            }
            if !groceries.onList.isEmpty {
                Section {
                    ForEach(groceries.onList) { item in
                        row(item, isChecked: true, action: nil)
                    }
                } header: {
                    SectionHeader("Already on Groceries", systemImage: "checkmark.circle")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// "Thursday to Sunday, 5 meals".
    private func summary(_ groceries: MealPlanGroceries) -> String {
        let meals = groceries.mealCount == 1 ? "1 meal" : "\(groceries.mealCount) meals"
        guard let days = groceries.days else { return meals }
        return "\(MealPlanFormat.days(days)), \(meals)"
    }

    /// The amount in orange and the name, with the recipes that need it under them.
    private func row(_ item: GroceryItem, isChecked: Bool, action: (() -> Void)?) -> some View {
        Button { action?() } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? .orange : .secondary)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Group {
                        if let amount = item.amount {
                            Text("\(Text(amount).foregroundStyle(.orange).fontWeight(.semibold)) \(item.name)")
                        } else {
                            Text(item.text)
                        }
                    }
                    .font(.title3)
                    .strikethrough(isChecked, color: .secondary)
                    .foregroundStyle(isChecked ? .secondary : .primary)
                    Text(item.recipes.joined(separator: ", "))
                        .font(.tileDetail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityAddTraits(isChecked ? .isSelected : [])
    }

    private func toggle(_ item: GroceryItem) {
        guard !hasAdded else { return }
        if have.contains(item.key) { have.remove(item.key) } else { have.insert(item.key) }
    }

    private func add() {
        isAdding = true
        let items = toAdd
        Task {
            do {
                let count = try await context.addToGroceries(items.map(\.text))
                message = "Added \(count) \(count == 1 ? "item" : "items") to Groceries."
                hasAdded = true
            } catch {
                message = "Could not add to Groceries. \(error.localizedDescription)"
            }
            isAdding = false
        }
    }
}
