import HomePadUI
import SwiftUI

/// A step's text in huge type, with ingredient amounts in orange and cooking
/// times as tappable orange timer links.
struct StepTextView: View {
    let segments: [StepSegment]
    let fontSize: CGFloat
    let onTimer: (DetectedDuration) -> Void

    /// Links use this scheme and the segment index, handled in `openURL` below.
    private static let scheme = "homepad-kitchen-timer"

    var body: some View {
        composed
            .font(.system(size: fontSize, weight: .medium))
            .lineSpacing(fontSize * 0.18)
            .tint(.orange)
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == Self.scheme, let index = Int(url.host() ?? ""), segments.indices.contains(index),
                      case .duration(let duration) = segments[index].kind else { return .systemAction }
                onTimer(duration)
                return .handled
            })
    }

    private var composed: Text {
        segments.enumerated().reduce(Text(verbatim: "")) { text, item in
            let (index, segment) = item
            switch segment.kind {
            case .text:
                return Text("\(text)\(Text(verbatim: segment.text))")
            case .amount:
                return Text("\(text)\(Text(verbatim: segment.text).foregroundStyle(.orange).fontWeight(.semibold))")
            case .duration:
                var link = AttributedString(segment.text)
                link.link = URL(string: "\(Self.scheme)://\(index)")
                link.foregroundColor = .orange
                let icon = Text(Image(systemName: "timer")).foregroundStyle(.orange)
                return Text("\(text)\(icon)\u{2009}\(Text(link).fontWeight(.semibold))")
            }
        }
    }
}
