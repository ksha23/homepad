import HomePadCore
import SwiftUI

extension View {
    /// Advertises HomePad's current recipe, music and assistant conversation for
    /// Handoff, and accepts activities handed to this device.
    func homePadHandoff(_ center: HandoffCenter) -> some View {
        modifier(HandoffModifier(center: center))
    }
}

private struct HandoffModifier: ViewModifier {
    let center: HandoffCenter

    func body(content: Content) -> some View {
        content
            .userActivity(HandoffCenter.ActivityType.recipe, isActive: center.advertisesRecipe) { center.fill(recipe: $0) }
            .userActivity(HandoffCenter.ActivityType.nowPlaying, isActive: center.nowPlaying != nil) { center.fill(nowPlaying: $0) }
            .userActivity(HandoffCenter.ActivityType.assistant, isActive: center.advertisesAssistant) { center.fill(assistant: $0) }
            .onContinueUserActivity(HandoffCenter.ActivityType.recipe, perform: center.receive)
            .onContinueUserActivity(HandoffCenter.ActivityType.nowPlaying, perform: center.receive)
            .onContinueUserActivity(HandoffCenter.ActivityType.assistant, perform: center.receive)
            .onContinueUserActivity(HandoffCenter.ActivityType.camera, perform: center.receive)
    }
}
