import HomePadCore
import HomePadUI
import SwiftUI

/// Root UI when HomePad runs on iPhone or on a Mac ("Designed for iPad"):
/// a companion remote for the HomePads in the house instead of the kiosk shell.
/// It follows the phone's or the Mac's own light or dark appearance.
public struct CompanionRootView: View {
    public init() {}

    public var body: some View {
        if let runtime = ConnectRuntime.current {
            CompanionTabs()
                .environment(runtime)
                .homePadHandoff(runtime.handoff)
        } else {
            EmptyStateView(
                "HomePad Companion",
                message: "Send recipes, talk over intercom and control your HomePads from here.",
                systemImage: "ipad.landscape"
            )
        }
    }
}

/// The companion's tabs. Every tab uses the same HomePadUI tokens as the kiosk.
private struct CompanionTabs: View {
    @Environment(ConnectRuntime.self) private var connect
    @State private var selection = Self.initialTab
    @State private var isComposingNote = false

    var body: some View {
        TabView(selection: $selection) {
            Tab("HomePads", systemImage: "ipad.landscape", value: "homepads") {
                CompanionHomePadsView()
            }
            Tab("Send", systemImage: "paperplane", value: "send") {
                NavigationStack { SendToHomePadView() }
            }
            Tab("Intercom", systemImage: "waveform", value: "intercom") {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: Theme.Spacing.xl) {
                            IntercomPanel(buttonDiameter: 180)
                            IntercomHistoryList()
                        }
                        .padding(Theme.Spacing.l)
                    }
                    .navigationTitle("Intercom")
                }
            }
            Tab("Home", systemImage: "house", value: "home") {
                NavigationStack { CompanionHomeView() }
            }
            Tab("Board", systemImage: "note.text", value: "board") {
                NavigationStack {
                    BoardView(isComposing: $isComposingNote)
                        .padding(.horizontal, Theme.Spacing.m)
                        .navigationTitle("Family Board")
                        .toolbar {
                            Button("New Note", systemImage: "plus") { isComposingNote = true }
                        }
                }
            }
        }
        .overlay(alignment: .top) { CompanionAlertBanner() }
        .approvalPrompts()
    }

    /// `-HomePadOpenApp <tab>` opens a tab, for simulator screenshots.
    private static var initialTab: String {
        let requested = UserDefaults.standard.string(forKey: "HomePadOpenApp") ?? "homepads"
        return ["send", "intercom", "home", "board"].contains(requested) ? requested : "homepads"
    }
}

/// An in-app banner for relayed alerts while the companion is open.
private struct CompanionAlertBanner: View {
    @Environment(ConnectRuntime.self) private var connect

    var body: some View {
        if let alert = connect.alerts.latest {
            GlassBanner(systemImage: alert.alert.systemImage, tint: alert.alert == .doorbell ? .blue : .red,
                        title: alert.title, subtitle: alert.message) {
                EmptyView()
            } actions: {
                CloseButton("Dismiss") { connect.alerts.dismiss() }
            }
            .padding(.horizontal, Theme.Spacing.l)
            .padding(.top, Theme.Spacing.l)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
