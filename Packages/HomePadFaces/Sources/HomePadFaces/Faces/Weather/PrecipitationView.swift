import SwiftUI
import UIKit

/// Rain or snow from a Core Animation particle emitter. The render server
/// animates the particles, so the app's CPU stays idle.
struct PrecipitationView: UIViewRepresentable {
    enum Kind { case rain, snow }

    let kind: Kind
    /// False stops new drops. Those already falling finish, so the sky empties gently.
    var isRunning = true

    func makeUIView(context: Context) -> EmitterHostView {
        let view = EmitterHostView()
        view.configure(kind, isRunning: isRunning)
        return view
    }

    func updateUIView(_ uiView: EmitterHostView, context: Context) {
        uiView.configure(kind, isRunning: isRunning)
    }

    /// A view whose emitter line follows its top edge.
    final class EmitterHostView: UIView {
        private let emitter = CAEmitterLayer()
        private var kind: Kind?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
            layer.addSublayer(emitter)
        }

        required init?(coder: NSCoder) { nil }

        func configure(_ kind: Kind, isRunning: Bool) {
            emitter.birthRate = isRunning ? 1 : 0
            guard kind != self.kind else { return }
            self.kind = kind
            emitter.emitterShape = .line
            emitter.emitterCells = [kind == .rain ? Self.rainCell() : Self.snowCell()]
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            emitter.frame = bounds
            emitter.emitterPosition = CGPoint(x: bounds.midX, y: -20)
            emitter.emitterSize = CGSize(width: bounds.width * 1.2, height: 1)
        }

        private static func rainCell() -> CAEmitterCell {
            let cell = CAEmitterCell()
            cell.contents = streak(size: CGSize(width: 2, height: 28))
            cell.birthRate = 260
            cell.lifetime = 2.2
            cell.velocity = 900
            cell.velocityRange = 200
            cell.emissionLongitude = .pi
            cell.emissionRange = 0.05
            cell.scaleRange = 0.4
            cell.alphaRange = 0.3
            cell.color = UIColor.white.withAlphaComponent(0.35).cgColor
            return cell
        }

        private static func snowCell() -> CAEmitterCell {
            let cell = CAEmitterCell()
            cell.contents = dot(diameter: 14)
            cell.birthRate = 45
            cell.lifetime = 20
            cell.velocity = 70
            cell.velocityRange = 30
            cell.emissionLongitude = .pi
            cell.emissionRange = 0.4
            cell.scale = 0.6
            cell.scaleRange = 0.5
            cell.spinRange = 1
            cell.alphaRange = 0.4
            cell.color = UIColor.white.withAlphaComponent(0.85).cgColor
            return cell
        }

        private static func streak(size: CGSize) -> CGImage? {
            UIGraphicsImageRenderer(size: size).image { context in
                UIColor.white.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.width / 2).fill()
            }.cgImage
        }

        private static func dot(diameter: CGFloat) -> CGImage? {
            UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter)).image { context in
                let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(0).cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.3, 1]) else { return }
                let center = CGPoint(x: diameter / 2, y: diameter / 2)
                context.cgContext.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                                     endRadius: diameter / 2, options: [])
            }.cgImage
        }
    }
}
