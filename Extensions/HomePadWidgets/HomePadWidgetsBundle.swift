import SwiftUI
import WidgetKit

/// Widget extension: the kitchen timer Live Activity (Lock Screen and Dynamic
/// Island) and the small Home Screen timers widget.
@main
struct HomePadWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TimerLiveActivityWidget()
        TimersHomeWidget()
    }
}
