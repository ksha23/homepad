import SwiftUI

/// A capsule showing where one day's range sits within the whole forecast,
/// colored cool to warm.
struct TemperatureRangeBar: View {
    let low: Double
    let high: Double
    let lowest: Double
    let highest: Double
    let marker: Double?

    /// The bar never draws narrower than this.
    static let minimumWidth: CGFloat = 80

    var body: some View {
        GeometryReader { proxy in
            let span = max(highest - lowest, 1)
            let start = (low - lowest) / span * proxy.size.width
            let end = (high - lowest) / span * proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.2))
                Capsule()
                    .fill(LinearGradient(colors: [.cyan, .green, .yellow, .orange], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(end - start, 8))
                    .offset(x: start)
                if let marker {
                    Circle()
                        .fill(.white)
                        .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 2))
                        .frame(width: 10, height: 10)
                        .offset(x: min(max((marker - lowest) / span * proxy.size.width - 5, 0), proxy.size.width - 10))
                }
            }
        }
        .frame(height: 8)
        .frame(minWidth: Self.minimumWidth)
    }
}
