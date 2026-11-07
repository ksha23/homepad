import HomePadCore
import HomePadUI
import PhotosUI
import SwiftUI

/// HomeView's recipe card: a full-bleed photo with the title, source, time and
/// servings, and big Ingredients and Start Cooking buttons.
struct RecipeCardView: View {
    let context: KitchenContext
    let session: RecipeSession
    @Environment(AppServices.self) private var services
    @State private var showsIngredients = false
    @State private var photoItem: PhotosPickerItem?

    private var recipe: Recipe { context.library.recipe(session.recipe.id) ?? session.recipe }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RecipeHeroImage(recipe: recipe, library: context.library)
                .ignoresSafeArea()
            LinearGradient(stops: [.init(color: .clear, location: 0.35), .init(color: .black.opacity(0.9), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            details
                .padding(Theme.Spacing.l)
        }
        .overlay(alignment: .top) { topBar.padding(Theme.Spacing.l) }
        // The title, the buttons and the header sit on the photo's dark
        // gradient in every appearance. The ingredients sheet follows the app.
        .environment(\.colorScheme, .dark)
        .sheet(isPresented: $showsIngredients) {
            IngredientsPanel(context: context, session: session)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    context.library.setPhoto(data, for: recipe.id)
                }
                photoItem = nil
            }
        }
    }

    private var details: some View {
        // The session starts unknown servings at 4 for scaling. Only a stated number is shown.
        let parts = RecipeMetadata.parts(for: recipe, servings: session.canScale ? session.servings : nil)
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(recipe.title)
                    .font(.farTitle.bold())
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                HStack(spacing: Theme.Spacing.xs) {
                    if let source = parts.source { Text(source).foregroundStyle(.secondary) }
                    ForEach(parts.details, id: \.self) { detail in
                        Text("·").foregroundStyle(.secondary)
                        Text(detail).foregroundStyle(.orange)
                    }
                }
                .font(.title2)
                .lineLimit(1)
            }
            .frame(maxWidth: 880, alignment: .leading)
            // Across the whole card, as on HomeView, so they read from the stove.
            HStack(spacing: Theme.Spacing.m) {
                cardButton("Ingredients", systemImage: "checklist") { showsIngredients = true }
                cardButton("Start Cooking", systemImage: "frying.pan") { context.startCooking() }
                    .disabled(session.steps.isEmpty)
            }
        }
    }

    /// A wide `GlassCapsuleButton` look, `roundControl` tall, so the two buttons
    /// share the card's full width.
    private func cardButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassCapsule(size: .extraLarge))
    }

    /// Back on the leading side, More and the close button on the trailing
    /// side, like every app's header. The title sits over the photo instead.
    private var topBar: some View {
        AppHeader("", onBack: { context.closeRecipe() }, backLabel: "Back to recipes", accessory: { moreMenu })
    }

    /// Puts the recipe on one of the next seven days, at the servings chosen
    /// on the card when it can be scaled.
    private var planMenu: some View {
        let today = MealDay.today()
        return Menu {
            ForEach((0..<7).map { today.adding(days: $0) }) { day in
                Button(MealPlanFormat.dayName(day, today: today)) {
                    context.plan(recipe, on: day, servings: session.canScale ? session.servings : nil)
                }
            }
        } label: {
            Label("Add to Meal Plan", systemImage: "calendar.badge.plus")
        }
    }

    private var moreMenu: some View {
        HeaderMenu("More", systemImage: "ellipsis") {
            ShareLink(item: RecipeShareText.text(for: recipe), subject: Text(recipe.title)) {
                Label("Share Recipe", systemImage: "square.and.arrow.up")
            }
            // The picker browses the iPad's whole library, so only its owner gets it (`PhotoAccessPolicy`).
            if services.photoAccess.allowsLibrary {
                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label(recipe.localImageName == nil ? "Choose Photo" : "Replace Photo", systemImage: "photo")
                }
            }
            Button(recipe.isPinned ? "Unpin" : "Pin", systemImage: recipe.isPinned ? "pin.slash" : "pin") {
                context.library.togglePin(recipe.id)
            }
            planMenu
            if let url = recipe.sourceURL {
                Link(destination: url) { Label("Open Original Page", systemImage: "safari") }
            }
        }
    }
}
