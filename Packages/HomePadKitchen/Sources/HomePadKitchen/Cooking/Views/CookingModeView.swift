import HomePadCore
import HomePadUI
import SwiftUI

/// Cooking mode: one step at a time in huge type with step dots, orange amounts,
/// tappable timers, and next and previous by touch, swipe or voice.
struct CookingModeView: View {
    let context: KitchenContext
    let session: RecipeSession
    @Environment(AppServices.self) private var services
    @Environment(\.proximity) private var proximity
    @State private var showsIngredients = false
    @State private var isCookAcrossRoom = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if let step = session.currentStep {
                stepContent(step)
                    .id(step.number)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 40)), removal: .opacity))
            }
            footer
        }
        .padding(Theme.Spacing.l)
        .animation(Theme.Motion.standard, value: session.stepIndex)
        .contentShape(Rectangle())
        .gesture(swipe)
        .sheet(isPresented: $showsIngredients) {
            IngredientsPanel(context: context, session: session)
        }
        .keepsDisplayActive("kitchen.cooking")
        .background { CookDistanceReader(isAcrossRoom: $isCookAcrossRoom) }
    }

    // MARK: Header

    private var header: some View {
        DetailHeader(session.recipe.title, closeLabel: "Leave cooking mode", onClose: { context.stopCooking() }, detail: {
            VStack(spacing: Theme.Spacing.s) {
                PageDots(count: session.steps.count, selection: Binding(get: { session.stepIndex }, set: { session.go(to: $0) }))
                RunningTimerPills()
            }
        })
        // Its own pills show every timer, so the shell's timer pill steps aside.
        .showsRunningTimers()
    }

    // MARK: Step

    private func stepContent(_ step: RecipeStep) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack(spacing: Theme.Spacing.s) {
                    Text("Step \(step.number)")
                    if let section = step.sectionTitle { Text("· \(section)") }
                }
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)

                StepTextView(segments: session.segments(for: step), fontSize: fontSize) { duration in
                    context.startTimer(for: duration, in: step)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                StepTimerChips(context: context, session: session, step: step)

                if let next = session.steps.first(where: { $0.number == step.number + 1 }) {
                    nextStepPreview(next)
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.l)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .frame(maxHeight: .infinity)
    }

    /// The following step, dimmed, so the cook can read ahead as on HomeView.
    private func nextStepPreview(_ next: RecipeStep) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Next")
                .font(.title3.weight(.semibold))
            Text(StepTextAnalyzer.plainText(for: next.text, adjustment: session.adjustment))
                .font(.system(size: fontSize * 0.55, weight: .medium))
                .lineLimit(4)
        }
        .foregroundStyle(.secondary)
        .padding(.top, Theme.Spacing.xl)
        .onTapGesture { session.next() }
        .accessibilityLabel("Next step: \(next.text)")
    }

    /// Bigger from across the room, as HomeView scales recipe text with distance.
    ///
    /// Cooking mode holds the display awake, and the shell then reports `.near`
    /// whenever anyone is in view, however far away. So `\.proximity` alone grew
    /// the text only once the room was empty. The camera's own reading says
    /// when the cook is across the room. `\.proximity` still gives `.far` with
    /// nobody in view and when pinned with `-HomePadProximity far`.
    private var fontSize: CGFloat {
        proximity <= .far || isCookAcrossRoom ? 58 : 46
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            GlassIconButton("chevron.left", label: "Previous step", size: Theme.Size.roundControl) { session.previous() }
                .disabled(session.isFirstStep)
            Spacer()
            GlassCapsuleButton("Ingredients", systemImage: "checklist") { showsIngredients = true }
            Spacer()
            if session.isLastStep {
                GlassIconButton("checkmark", label: "Finish", size: Theme.Size.roundControl, tint: .orange) { context.stopCooking() }
            } else {
                GlassIconButton("chevron.right", label: "Next step", size: Theme.Size.roundControl, tint: .orange) { session.next() }
            }
        }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 40)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < 0 { session.next() } else { session.previous() }
            }
    }
}

/// Watches the camera's distance reading for cooking mode. It sits in the
/// background so that only a change between across the room and closer redraws
/// the step, not every presence update.
private struct CookDistanceReader: View {
    @Environment(AppServices.self) private var services
    @Binding var isAcrossRoom: Bool

    var body: some View {
        let snapshot = services.presence.snapshot
        let isFar = snapshot.isSomeonePresent && snapshot.proximity <= .far
        Color.clear
            .onChange(of: isFar, initial: true) { isAcrossRoom = isFar }
    }
}
