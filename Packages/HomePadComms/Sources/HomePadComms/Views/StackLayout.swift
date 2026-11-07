import Foundation

/// How several photos from one message are drawn, like iMessage: a tidy pile for two
/// or three, a two-by-two grid for four or more with a "+N" tile when there are more.
enum StackLayout: Equatable {
    case single
    case pile(count: Int)
    /// `shown` tiles in the grid. `extra` is the number on the last tile ("+N"), or 0 for none.
    case grid(shown: Int, extra: Int)

    static func choose(count: Int) -> StackLayout {
        switch count {
        case ...1: .single
        case 2...3: .pile(count: count)
        default: .grid(shown: 4, extra: count > 4 ? count - 3 : 0)
        }
    }
}
