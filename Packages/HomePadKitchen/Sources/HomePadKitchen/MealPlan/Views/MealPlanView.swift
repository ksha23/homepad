import HomePadCore
import HomePadUI
import SwiftUI

/// The week's meal plan: a column per day in landscape and a row per day in
/// portrait, each with its planned recipes and an Add button. The header moves
/// between weeks and adds the week's ingredients to Groceries.
struct MealPlanView: View {
    let context: KitchenContext
    @State private var pickingDay: MealDay?
    @Environment(\.appAccent) private var appAccent

    private var week: MealWeek { context.mealPlanWeek }

    var body: some View {
        TimelineView(MidnightSchedule(isPaused: false)) { timeline in
            let today = MealDay(timeline.date)
            AppScreen("Meal Plan", onBack: { context.closeMealPlan() }, backLabel: "Back to recipes", accessory: { accessory(today: today) }) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    weekLine(today: today)
                    GeometryReader { proxy in
                        if proxy.size.width > proxy.size.height {
                            columns(today: today)
                        } else {
                            rows(today: today, width: proxy.size.width)
                        }
                    }
                }
            }
        }
        .sheet(item: $pickingDay) { day in
            MealPickerSheet(context: context, day: day)
        }
        .sheet(isPresented: groceriesBinding) {
            MealPlanGroceriesSheet(context: context, week: week)
        }
    }

    private var groceriesBinding: Binding<Bool> {
        Binding(get: { context.showsMealPlanGroceries }, set: { context.showsMealPlanGroceries = $0 })
    }

    // MARK: Header

    /// Previous, This Week and next in one group, then Groceries, the one
    /// prominent action, dimmed while nothing ahead is planned.
    @ViewBuilder
    private func accessory(today: MealDay) -> some View {
        ToolbarGroup {
            GlassIconButton("chevron.left", label: "Previous Week") { show(week.offset(by: -1)) }
            GlassCapsuleButton("This Week") { show(.current()) }
            GlassIconButton("chevron.right", label: "Next Week") { show(week.offset(by: 1)) }
        }
        GlassCapsuleButton("Groceries", systemImage: "cart.badge.plus", isProminent: true) { context.showsMealPlanGroceries = true }
            .disabled(context.shoppableMeals(in: week, today: today).isEmpty)
    }

    private func show(_ week: MealWeek) {
        withAnimation(Theme.Motion.standard) { context.mealPlanWeek = week }
    }

    private func weekLine(today: MealDay) -> some View {
        let title = MealPlanFormat.weekTitle(week, today: today)
        let isEmpty = context.plannedRecipes(from: week.start, through: week.end()).isEmpty
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                if let title { Text(title) }
                Text(MealPlanFormat.weekRange(week)).foregroundStyle(title == nil ? .primary : .secondary)
            }
            .font(.glanceSubtitle)
            if isEmpty {
                Text("Put recipes on days, then add the week's ingredients to Groceries in one go.")
                    .font(.tileDetail)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Layouts

    /// Landscape: seven columns side by side, the week at a glance.
    private func columns(today: MealDay) -> some View {
        ScrollView {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                ForEach(week.days()) { day in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        dayHeader(day, today: today)
                        ForEach(context.plannedRecipes(on: day)) { planned in
                            PlannedMealCard(context: context, planned: planned, week: week, cornerRadius: cardRadius)
                        }
                        addButton(day)
                    }
                    .padding(Theme.Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .background(dayFill(day, today: today), in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                }
            }
            .padding(.bottom, Theme.Spacing.l)
        }
        .scrollIndicators(.hidden)
    }

    /// Portrait: a row per day, its meals side by side under the day, three
    /// cards to the row's width so a title wraps as in a landscape column.
    private func rows(today: MealDay, width: CGFloat) -> some View {
        let perRow: CGFloat = 3
        let cardWidth = (width - Theme.Spacing.s * 2 - Theme.Spacing.s * (perRow - 1)) / perRow
        return ScrollView {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(week.days()) { day in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        dayHeader(day, today: today)
                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                                ForEach(context.plannedRecipes(on: day)) { planned in
                                    PlannedMealCard(context: context, planned: planned, week: week, cornerRadius: cardRadius)
                                        .frame(width: cardWidth)
                                }
                                addButton(day)
                                    .frame(width: cardWidth)
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    .padding(Theme.Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(dayFill(day, today: today), in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
                }
            }
            .padding(.bottom, Theme.Spacing.l)
        }
        .scrollIndicators(.hidden)
    }

    /// Cards sit in a day's container, padded by `Spacing.s`, so their corners
    /// run parallel to it.
    private var cardRadius: CGFloat {
        Theme.Radius.concentric(in: Theme.Radius.tile, inset: Theme.Spacing.s)
    }

    // MARK: Pieces

    /// "THU" over "12", in the app's color today. Days gone by are quieter.
    private func dayHeader(_ day: MealDay, today: MealDay) -> some View {
        let isToday = day == today
        return VStack(alignment: .leading, spacing: 0) {
            Text(MealPlanFormat.shortWeekday(day).uppercased())
                .font(.headline)
                .tracking(0.6)
            Text(MealPlanFormat.dayNumber(day))
                .font(.tileValue)
        }
        .foregroundStyle(isToday ? AnyShapeStyle(appAccent) : AnyShapeStyle(day < today ? .secondary : .primary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(MealPlanFormat.dayName(day, today: today))
    }

    private func dayFill(_ day: MealDay, today: MealDay) -> AnyShapeStyle {
        day == today ? AnyShapeStyle(appAccent.opacity(0.16)) : AnyShapeStyle(.primary.opacity(0.05))
    }

    private func addButton(_ day: MealDay) -> some View {
        Button { pickingDay = day } label: {
            Label("Add", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassCapsule(size: .large))
        .accessibilityLabel("Add a recipe to \(MealPlanFormat.fullDay(day))")
    }
}
