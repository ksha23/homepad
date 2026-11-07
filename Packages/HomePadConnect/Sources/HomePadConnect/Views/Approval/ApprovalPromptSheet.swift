import HomePadCore
import HomePadUI
import SwiftUI

extension View {
    /// Shows a HomePad's approval request as a sheet over the companion.
    func approvalPrompts() -> some View {
        modifier(ApprovalPromptPresenter())
    }
}

/// Presents `ApprovalResponder.prompt` until it is answered, closed or runs
/// out. It needs an answer, so it does not swipe away.
private struct ApprovalPromptPresenter: ViewModifier {
    @Environment(ConnectRuntime.self) private var connect

    func body(content: Content) -> some View {
        // Read here, so the body follows the prompt and the sheet closes with it.
        let prompt = connect.approvals.prompt
        content.sheet(item: Binding(get: { prompt }, set: { _ in })) { prompt in
            ApprovalPromptSheet(prompt: prompt)
                .environment(connect)
                .presentationDetents([.medium])
                .interactiveDismissDisabled()
        }
    }
}

/// "Unlock Messages?" Unlock verifies with Face ID or the passcode and sends
/// a signed approval. Don't Allow and the close button say no. On a phone the
/// header has room for the title and the close button only, so both answers
/// sit in the content, side by side.
struct ApprovalPromptSheet: View {
    @Environment(ConnectRuntime.self) private var connect
    @Environment(\.dismiss) private var dismiss
    let prompt: ApprovalResponder.Prompt

    private var request: ApprovalRequest { prompt.request }
    private var approvals: ApprovalResponder { connect.approvals }

    var body: some View {
        SheetScreen("Unlock \(request.appTitle)?", closeLabel: "Don't Allow", onClose: deny) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Text("Someone at \(request.homePadName) wants to open \(request.appTitle) as \(prompt.memberName).")
                        .font(.title3)
                    Text("Unlocking lets them see \(prompt.memberName)'s personal apps on \(request.homePadName) for a few minutes. Approve only if it's you. This request ends after 30 seconds.")
                        .foregroundStyle(.secondary)
                    if let error = approvals.promptError {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Theme.Spacing.s) { answers }
                        VStack(alignment: .leading, spacing: Theme.Spacing.s) { answers }
                    }
                    .padding(.top, Theme.Spacing.s)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.l)
            }
        }
        .task(id: approvals.prompt?.id) { await dismissWhenClosed() }
    }

    /// Closes the sheet once its request is answered, withdrawn or run out.
    /// UIKit drops a dismissal that comes while a sheet is still coming up,
    /// which left an approved request on screen in the simulator, so this
    /// tries again until the sheet goes.
    private func dismissWhenClosed() async {
        guard approvals.prompt?.id != prompt.id else { return }
        dismiss()
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    @ViewBuilder
    private var answers: some View {
        GlassCapsuleButton("Don't Allow", systemImage: "hand.raised", action: deny)
        GlassCapsuleButton("Unlock", systemImage: biometrySymbol, isProminent: true, action: approve)
            .disabled(approvals.isApproving)
    }

    private var biometrySymbol: String {
        connect.link.identity.kind == .mac ? "touchid" : "faceid"
    }

    private func approve() {
        Task { await approvals.approve() }
    }

    private func deny() {
        Task { await approvals.deny() }
    }
}
