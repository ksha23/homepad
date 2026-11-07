import CoreGraphics
import Foundation

/// Generated pictures for the Photos and Cameras faces when there is no
/// photo library (the simulator) or no camera feed. Each scene comes with a
/// subject mask, so the depth effect is visible without Vision.
enum DemoPhotoScenes {
    static let titles = ["Desert Dusk", "Alpine Lake", "Monstera", "Lighthouse"]
    static var count: Int { titles.count }

    /// Renders a scene as a square picture and its subject mask.
    static func render(_ index: Int, side: Int) -> (image: CGImage, mask: CGImage)? {
        guard let painter = ScenePainter(side: side) else { return nil }
        switch index % count {
        case 0: desert(painter)
        case 1: alpine(painter)
        case 2: monstera(painter)
        default: lighthouse(painter)
        }
        return painter.images()
    }

    // MARK: Scenes

    private static func desert(_ s: ScenePainter) {
        s.sky(["#241A4E", "#7B3F7A", "#E0607E", "#F7B267"], from: 0.05, to: 0.66)
        s.glow(center: s.p(0.66, 0.6), radius: 0.4, hex: "#FFD08A", alpha: 0.6)
        s.fill(CGPath(ellipseIn: s.rect(0.59, 0.53, 0.73, 0.67), transform: nil), "#FFE6B8")
        s.fill(s.polygon([(0, 0.66), (0.08, 0.6), (0.2, 0.6), (0.24, 0.645), (0.5, 0.645), (0.55, 0.58), (0.7, 0.58),
                          (0.74, 0.63), (1, 0.63), (1, 1), (0, 1)]), "#8A4A72")
        let dunes = CGMutablePath()
        dunes.move(to: s.p(0, 0.73))
        dunes.addQuadCurve(to: s.p(1, 0.75), control: s.p(0.5, 0.63))
        dunes.addLines(between: [s.p(1, 0.75), s.p(1, 1), s.p(0, 1)])
        dunes.closeSubpath()
        s.fill(dunes, gradient: ["#6B3358", "#3D1E3C"], from: s.p(0, 0.68), to: s.p(0, 1))
        let ground = CGMutablePath()
        ground.move(to: s.p(0, 0.88))
        ground.addQuadCurve(to: s.p(1, 0.86), control: s.p(0.55, 0.8))
        ground.addLines(between: [s.p(1, 0.86), s.p(1, 1), s.p(0, 1)])
        ground.closeSubpath()
        s.fill(ground, "#2A1530")

        let cactus = CGMutablePath()
        cactus.addPath(s.roundedRect(0.4, 0.26, 0.47, 0.93, radius: 0.035))
        cactus.addPath(s.roundedRect(0.31, 0.56, 0.43, 0.61, radius: 0.025))
        cactus.addPath(s.roundedRect(0.31, 0.4, 0.36, 0.61, radius: 0.025))
        cactus.addPath(s.roundedRect(0.44, 0.5, 0.56, 0.545, radius: 0.0225))
        cactus.addPath(s.roundedRect(0.51, 0.34, 0.56, 0.545, radius: 0.025))
        s.fill(cactus, gradient: ["#5E9A68", "#2F5E3D", "#1B3624"], from: s.p(0.3, 0), to: s.p(0.57, 0), subject: true)
        for x in [0.42, 0.435, 0.45] as [CGFloat] {
            let rib = CGMutablePath()
            rib.addLines(between: [s.p(x, 0.29), s.p(x, 0.9)])
            s.stroke(rib, "#8CC79A", width: 0.002, alpha: 0.35)
        }
    }

    private static func alpine(_ s: ScenePainter) {
        s.sky(["#3E7CC0", "#9CC7EA", "#E3F1FB"], from: 0.02, to: 0.6)
        for (x, y, w) in [(0.12, 0.12, 0.22), (0.55, 0.08, 0.3), (0.82, 0.18, 0.2)] as [(CGFloat, CGFloat, CGFloat)] {
            s.fill(CGPath(ellipseIn: s.rect(x, y, x + w, y + w * 0.22), transform: nil), "#FFFFFF", alpha: 0.55)
        }
        s.fill(s.polygon([(0, 0.55), (0.12, 0.42), (0.22, 0.5), (0.35, 0.37), (0.48, 0.52), (0.62, 0.4), (0.78, 0.5),
                          (0.9, 0.38), (1, 0.46), (1, 0.64), (0, 0.64)]), "#A3B9D3")
        let peak = s.polygon([(0.16, 0.64), (0.45, 0.22), (0.55, 0.3), (0.62, 0.26), (0.88, 0.64)])
        s.fill(peak, gradient: ["#7189A9", "#4A5F7E"], from: s.p(0, 0.25), to: s.p(0, 0.64))
        s.fill(s.polygon([(0.37, 0.335), (0.45, 0.22), (0.55, 0.3), (0.62, 0.26), (0.69, 0.35), (0.62, 0.37), (0.56, 0.335),
                          (0.5, 0.38), (0.44, 0.35)]), "#F4F8FC")
        var ridge: [(CGFloat, CGFloat)] = [(0, 0.67)]
        for step in 0...40 {
            let x = CGFloat(step) / 40
            ridge.append((x, step % 2 == 0 ? 0.625 : 0.645))
        }
        ridge.append((1, 0.67))
        s.fill(s.polygon(ridge), "#2F5140")
        s.fill(CGPath(rect: s.rect(0, 0.665, 1, 1), transform: nil), gradient: ["#6E9CC4", "#2D5A80"], from: s.p(0, 0.665), to: s.p(0, 1))
        s.fill(s.polygon([(0.2, 0.665), (0.45, 0.98), (0.55, 0.9), (0.62, 0.94), (0.86, 0.665)]), "#C8D8EA", alpha: 0.18)
        for y in stride(from: 0.7, to: 0.98, by: 0.035) as StrideTo<CGFloat> {
            let line = CGMutablePath()
            line.addLines(between: [s.p(0.1 + y * 0.2, y), s.p(0.3 + y * 0.25, y)])
            s.stroke(line, "#FFFFFF", width: 0.002, alpha: 0.25)
        }
        pine(s, x: 0.79, top: 0.2, base: 1.0, width: 0.22)
        pine(s, x: 0.94, top: 0.33, base: 1.0, width: 0.17)
        pine(s, x: 0.66, top: 0.5, base: 1.0, width: 0.11)
    }

    private static func pine(_ s: ScenePainter, x: CGFloat, top: CGFloat, base: CGFloat, width: CGFloat) {
        let tree = CGMutablePath()
        tree.addRect(s.rect(x - 0.012, base - 0.08, x + 0.012, base))
        let tiers = 5
        let height = (base - 0.06) - top
        for tier in 0..<tiers {
            let t = CGFloat(tier) / CGFloat(tiers)
            let tierTop = top + height * t * 0.82
            let tierBottom = top + height * (t * 0.82 + 0.3)
            let half = width / 2 * (0.35 + 0.65 * (t + 1 / CGFloat(tiers)))
            tree.addLines(between: [s.p(x, tierTop), s.p(x + half, tierBottom), s.p(x - half, tierBottom)])
            tree.closeSubpath()
        }
        s.fill(tree, gradient: ["#2C5A3D", "#14301F"], from: s.p(x - width / 2, 0), to: s.p(x + width / 2, 0), subject: true)
    }

    private static func monstera(_ s: ScenePainter) {
        s.fill(CGPath(rect: s.rect(0, 0, 1, 1), transform: nil), gradient: ["#F5AE9F", "#E07A6D"], from: s.p(0.1, 0), to: s.p(0.9, 1))
        s.glow(center: s.p(0.28, 0.22), radius: 0.5, hex: "#FFF1E6", alpha: 0.35)
        for (index, x) in [0.05, 0.22, 0.75, 0.9].enumerated() {
            s.picture.saveGState()
            s.picture.translateBy(x: x * s.side, y: 0.1 * s.side)
            s.picture.rotate(by: .pi / 5 + CGFloat(index) * 0.1)
            s.fill(CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 0.06 * s.side, height: 0.55 * s.side), transform: nil), "#5A1E14", alpha: 0.06)
            s.picture.restoreGState()
        }
        s.fill(CGPath(rect: s.rect(0, 0.82, 1, 1), transform: nil), gradient: ["#C9665A", "#A9503F"], from: s.p(0, 0.82), to: s.p(0, 1))
        s.fill(CGPath(rect: s.rect(0, 0.815, 1, 0.825), transform: nil), "#F6C3B6", alpha: 0.6)

        let leaves: [(CGFloat, CGFloat, CGFloat, CGFloat, String)] = [
            (0.33, 0.43, 0.15, -0.75, "#2F7D4F"), (0.68, 0.41, 0.15, 0.7, "#3D9461"),
            (0.42, 0.58, 0.11, -1.25, "#276B42"), (0.6, 0.57, 0.11, 1.2, "#2F7D4F"),
            (0.51, 0.27, 0.17, 0.05, "#3D9461"), (0.5, 0.46, 0.12, 0.2, "#276B42"),
        ]
        for (x, y, _, _, _) in leaves {
            let stem = CGMutablePath()
            stem.move(to: s.p(0.5, 0.69))
            stem.addQuadCurve(to: s.p(x, y + 0.04), control: s.p((0.5 + x) / 2, 0.62))
            s.stroke(stem, "#2E6B45", width: 0.008, subject: true)
        }
        for (x, y, size, angle, hex) in leaves {
            leaf(s, center: s.p(x, y), size: size * s.side, angle: angle, hex: hex)
        }
        let pot = s.polygon([(0.38, 0.69), (0.62, 0.69), (0.595, 0.93), (0.405, 0.93)])
        s.fill(pot, gradient: ["#D97A52", "#A24C2E"], from: s.p(0.38, 0), to: s.p(0.62, 0), subject: true)
        s.fill(s.roundedRect(0.36, 0.665, 0.64, 0.71, radius: 0.008), gradient: ["#E08A62", "#B5583A"],
               from: s.p(0.36, 0), to: s.p(0.64, 0), subject: true)
    }

    /// A heart-shaped leaf with a notch at the base and a lighter midrib.
    private static func leaf(_ s: ScenePainter, center: CGPoint, size: CGFloat, angle: CGFloat, hex: String) {
        let transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: angle).scaledBy(x: size, y: size)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: -1), transform: transform)
        path.addCurve(to: CGPoint(x: 0.06, y: 0.72), control1: CGPoint(x: 1.05, y: -0.9), control2: CGPoint(x: 1.0, y: 0.75), transform: transform)
        path.addLine(to: CGPoint(x: 0, y: 0.55), transform: transform)
        path.addLine(to: CGPoint(x: -0.06, y: 0.72), transform: transform)
        path.addCurve(to: CGPoint(x: 0, y: -1), control1: CGPoint(x: -1.0, y: 0.75), control2: CGPoint(x: -1.05, y: -0.9), transform: transform)
        s.fill(path, hex, subject: true)
        let rib = CGMutablePath()
        rib.addLines(between: [CGPoint(x: 0, y: -0.85), CGPoint(x: 0, y: 0.5)], transform: transform)
        for side in [-1.0, 1.0] as [CGFloat] {
            for y in [-0.45, -0.05, 0.3] as [CGFloat] {
                rib.addLines(between: [CGPoint(x: 0, y: y), CGPoint(x: side * 0.7, y: y - 0.25)], transform: transform)
            }
        }
        s.stroke(rib, "#B8E2C2", width: 0.0025, alpha: 0.35)
    }

    private static func lighthouse(_ s: ScenePainter) {
        s.sky(["#14244D", "#45457A", "#C76B76", "#F2A65A"], from: 0, to: 0.62)
        for (x, y) in [(0.1, 0.08), (0.24, 0.15), (0.4, 0.05), (0.52, 0.12), (0.86, 0.07), (0.93, 0.18), (0.05, 0.22)] as [(CGFloat, CGFloat)] {
            s.fill(CGPath(ellipseIn: s.rect(x, y, x + 0.004, y + 0.004), transform: nil), "#FFFFFF", alpha: 0.7)
        }
        s.glow(center: s.p(0.28, 0.62), radius: 0.35, hex: "#FFC98A", alpha: 0.55)
        s.fill(CGPath(ellipseIn: s.rect(0.23, 0.57, 0.33, 0.67), transform: nil), "#FFDDAA")
        s.fill(s.polygon([(0.7, 0.62), (0.8, 0.595), (0.92, 0.6), (1, 0.59), (1, 0.62)]), "#2B2F55")
        s.fill(CGPath(rect: s.rect(0, 0.62, 1, 1), transform: nil), gradient: ["#4A5A86", "#1C2647"], from: s.p(0, 0.62), to: s.p(0, 1))
        for (index, y) in stride(from: 0.635, to: 0.98, by: 0.022).enumerated() {
            let half = 0.02 + CGFloat(index) * 0.004
            let line = CGMutablePath()
            line.addLines(between: [s.p(0.28 - half, y), s.p(0.28 + half, y)])
            s.stroke(line, "#FFCF8F", width: 0.004, alpha: max(0.6 - CGFloat(index) * 0.03, 0.15))
        }
        s.fill(s.polygon([(0.67, 0.29), (0, 0.17), (0, 0.38)]), gradient: ["#FFE9A8", "#14244D"], from: s.p(0.67, 0), to: s.p(0.05, 0))

        let rocks = CGMutablePath()
        rocks.move(to: s.p(0.42, 1))
        rocks.addCurve(to: s.p(0.62, 0.8), control1: s.p(0.46, 0.88), control2: s.p(0.54, 0.8))
        rocks.addCurve(to: s.p(1, 0.85), control1: s.p(0.74, 0.79), control2: s.p(0.9, 0.82))
        rocks.addLines(between: [s.p(1, 0.85), s.p(1, 1)])
        rocks.closeSubpath()
        s.fill(rocks, gradient: ["#3A3D52", "#15161F"], from: s.p(0, 0.8), to: s.p(0, 1), subject: true)

        let tower = s.polygon([(0.6, 0.84), (0.74, 0.84), (0.715, 0.36), (0.625, 0.36)])
        s.fill(tower, gradient: ["#FFFFFF", "#E7E1D6", "#B9B3AA"], from: s.p(0.6, 0), to: s.p(0.74, 0), subject: true)
        s.picture.saveGState()
        s.picture.addPath(tower)
        s.picture.clip()
        for (top, bottom) in [(0.42, 0.5), (0.58, 0.66), (0.74, 0.82)] as [(CGFloat, CGFloat)] {
            s.fill(CGPath(rect: s.rect(0.55, top, 0.8, bottom), transform: nil), "#C8443A", alpha: 0.92)
        }
        s.picture.restoreGState()
        s.fill(CGPath(rect: s.rect(0.6, 0.33, 0.74, 0.36), transform: nil), "#2E2E38", subject: true)
        s.glow(center: s.p(0.67, 0.29), radius: 0.12, hex: "#FFE7A3", alpha: 0.7)
        s.fill(CGPath(rect: s.rect(0.625, 0.25, 0.715, 0.33), transform: nil), "#FFE7A3", subject: true)
        s.fill(s.polygon([(0.61, 0.255), (0.67, 0.195), (0.73, 0.255)]), "#2E2E38", subject: true)
    }
}
