import HomePadUI
import SwiftUI

/// A planned meal in a day of the plan: the recipe's photo, its title and the
/// servings it is planned for. A tap opens the recipe at those servings. Its
/// menu, like a recipe tile's in the library, changes the servings, moves it
/// to another day or takes it off the plan.
struct PlannedMealCard: View {
    let context: KitchenContext
    let planned: PlannedRecipe
    let week: MealWeek
    let cornerRadius: CGFloat

    var body: some View {
        Button { context.open(planned) } label: { card }
            .buttonStyle(.pressable(scale: 0.97))
            .contextMenu { menu }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the recipe.")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear
                .aspectRatio(4 / 3, contentMode: .fit)
                .overlay { RecipeHeroImage(recipe: planned.recipe, library: context.library) }
                .clipped()
            VStack(alignment: .leading, spacing: 2) {
                Text(planned.recipe.title)
                    .font(.tileTitle)
                    .lineLimit(3)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                if let servings = planned.servingsText {
                    Text(servings)
                        .font(.tileDetail)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(Theme.Spacing.s)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.raisedBackground)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private var menu: some View {
        Button("Open Recipe", systemImage: "book") { context.open(planned) }
        if let servings = planned.meal.servings {
            Picker(selection: Binding(get: { servings }, set: { context.setServings($0, for: planned.meal) })) {
                ForEach(servingChoices(including: servings), id: \.self) { Text("Serves \($0)").tag($0) }
            } label: {
                Label("Servings", systemImage: "person.2")
            }
            .pickerStyle(.menu)
        }
        Menu {
            ForEach(week.days().filter { $0 != planned.meal.day }) { day in
                Button(MealPlanFormat.dayName(day)) { context.move(planned.meal, to: day) }
            }
        } label: {
            Label("Move To", systemImage: "calendar")
        }
        Button("Remove from Plan", systemImage: "minus.circle", role: .destructive) {
            context.mealPlan.remove(planned.meal.id)
        }
    }

    /// The curated choices, plus the recipe's own number when it is not one of them.
    private func servingChoices(including current: Int) -> [Int] {
        Array(Set(KitchenSettings.servingChoices + [current, planned.recipe.servings].compactMap { $0 })).sorted()
    }
}
