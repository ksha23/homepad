import HomePadCore
import HomePadUI
import SwiftUI

/// Home Screen and face widget: what is planned to eat. The small size shows
/// today, or tomorrow once today has nothing planned. The medium size shows
/// today and tomorrow side by side. Each day lists as many whole meals as fit
/// and counts the rest. It moves on at midnight, and a tap opens the plan.
struct MealPlanWidget: View {
    let size: WidgetSize
    let context: KitchenContext
    @Environment(\.isThumbnail) private var isThumbnail
    @Environment(\.displayCondition) private var displayCondition

    var body: some View {
        GlassTile {
            TimelineView(MidnightSchedule(isPaused: isThumbnail || displayCondition == .sleeping)) { timeline in
                content(today: MealDay(timeline.date))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { context.showMealPlan(.current(), bringToFront: true) }
    }

    private func content(today: MealDay) -> some View {
        let tomorrow = today.adding(days: 1)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("Meal Plan", systemImage: "fork.knife")
                .font(.headline)
                .foregroundStyle(.orange)
                .lineLimit(1)
            if size == .small {
                let todays = context.plannedRecipes(on: today)
                let shown = todays.isEmpty ? tomorrow : today
                day(shown, today: today, meals: todays.isEmpty ? context.plannedRecipes(on: tomorrow) : todays)
            } else {
                HStack(alignment: .top, spacing: Theme.Spacing.m) {
                    day(today, today: today, meals: context.plannedRecipes(on: today))
                    day(tomorrow, today: today, meals: context.plannedRecipes(on: tomorrow))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// "TODAY" over the day's meals, as many as fit, then "2 more".
    private func day(_ day: MealDay, today: MealDay, meals: [PlannedRecipe]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(MealPlanFormat.dayName(day, today: today).uppercased())
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if meals.isEmpty {
                Text("Nothing planned")
                    .font(.tileDetail)
                    .foregroundStyle(.secondary)
            } else {
                ViewThatFits(in: .vertical) {
                    ForEach(Array((1...meals.count).reversed()), id: \.self) { count in
                        mealList(Array(meals.prefix(count)), hidden: meals.count - count)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func mealList(_ meals: [PlannedRecipe], hidden: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(meals) { planned in
                Text(planned.recipe.title)
                    .font(.tileTitle)
                    .lineLimit(2)
            }
            if hidden > 0 {
                Text("\(hidden) more")
                    .font(.tileDetail)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
