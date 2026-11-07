import HomePadUI
import SwiftUI

/// Maps plan meters to view points, keeping the aspect ratio and centering.
struct PlanMapper {
    let bounds: PlanRect
    let scale: CGFloat
    let origin: CGPoint

    init(bounds: PlanRect, size: CGSize, padding: CGFloat) {
        self.bounds = bounds
        let width = max(bounds.width, 0.5), height = max(bounds.height, 0.5)
        scale = max(1, min((size.width - padding * 2) / width, (size.height - padding * 2) / height))
        origin = CGPoint(x: (size.width - width * scale) / 2, y: (size.height - height * scale) / 2)
    }

    func point(_ planPoint: PlanPoint) -> CGPoint {
        CGPoint(x: origin.x + (planPoint.x - bounds.minX) * scale, y: origin.y + (planPoint.y - bounds.minY) * scale)
    }

    func planPoint(_ viewPoint: CGPoint) -> PlanPoint {
        PlanPoint(x: bounds.minX + (viewPoint.x - origin.x) / scale, y: bounds.minY + (viewPoint.y - origin.y) / scale)
    }
}

/// Draws walls, doors, windows and furniture with Canvas, in the page's ink:
/// white lines on the dark page, black ones on the white page.
struct FloorPlanDrawing: View {
    let plan: FloorPlan
    let mapper: PlanMapper
    @Environment(\.colorScheme) private var colorScheme

    /// The lines. Canvas takes plain colors here, so it picks one for the page.
    private var ink: Color { colorScheme == .dark ? .white : .black }
    /// The page, for cutting openings out of the walls.
    private var paper: Color { colorScheme == .dark ? .black : .white }

    var body: some View {
        Canvas { context, _ in
            for item in plan.furniture { draw(item, in: &context) }
            let wallWidth = max(5, 0.12 * mapper.scale)
            for wall in plan.walls {
                context.stroke(line(wall.start, wall.end), with: .color(ink.opacity(0.9)),
                               style: StrokeStyle(lineWidth: wallWidth, lineCap: .round))
            }
            for opening in plan.openings { draw(opening, wallWidth: wallWidth, in: &context) }
        }
    }

    private func line(_ start: PlanPoint, _ end: PlanPoint) -> Path {
        var path = Path()
        path.move(to: mapper.point(start))
        path.addLine(to: mapper.point(end))
        return path
    }

    private func draw(_ opening: FloorPlan.Opening, wallWidth: CGFloat, in context: inout GraphicsContext) {
        // Cut the opening out of the wall first.
        context.stroke(line(opening.start, opening.end), with: .color(paper), style: StrokeStyle(lineWidth: wallWidth + 2, lineCap: .butt))
        switch opening.kind {
        case .window:
            context.stroke(line(opening.start, opening.end), with: .color(.cyan.opacity(0.8)), style: StrokeStyle(lineWidth: max(2, wallWidth * 0.35)))
        case .door:
            let hinge = mapper.point(opening.start), end = mapper.point(opening.end)
            let radius = hypot(end.x - hinge.x, end.y - hinge.y)
            let angle = atan2(end.y - hinge.y, end.x - hinge.x)
            var swing = Path()
            swing.move(to: hinge)
            swing.addArc(center: hinge, radius: radius, startAngle: .radians(angle), endAngle: .radians(angle + .pi / 2), clockwise: false)
            swing.closeSubpath()
            context.fill(swing, with: .color(ink.opacity(0.06)))
            context.stroke(swing, with: .color(ink.opacity(0.35)), lineWidth: 1.5)
        case .opening:
            break
        }
    }

    private func draw(_ item: FloorPlan.Furniture, in context: inout GraphicsContext) {
        var path = Path()
        let corners = item.corners.map(mapper.point)
        path.addLines(corners)
        path.closeSubpath()
        context.fill(path, with: .color(ink.opacity(0.07)))
        context.stroke(path, with: .color(ink.opacity(0.25)), lineWidth: 1.5)
        let center = mapper.point(item.center)
        if min(item.width, item.depth) * mapper.scale > 34 {
            context.draw(Text(Image(systemName: FurnitureStyle.symbol(for: item.category))).font(.title3).foregroundStyle(ink.opacity(0.35)), at: center)
        }
    }
}

/// SF Symbols and names for RoomPlan's object categories.
enum FurnitureStyle {
    static func symbol(for category: String) -> String {
        switch category {
        case "sofa": "sofa.fill"
        case "bed": "bed.double.fill"
        case "table": "table.furniture.fill"
        case "chair": "chair.fill"
        case "television": "tv.fill"
        case "refrigerator": "refrigerator.fill"
        case "stove", "oven": "stove.fill"
        case "sink": "sink.fill"
        case "dishwasher": "dishwasher.fill"
        case "washerDryer": "washer.fill"
        case "toilet": "toilet.fill"
        case "bathtub": "bathtub.fill"
        case "fireplace": "fireplace.fill"
        case "stairs": "stairs"
        default: "cabinet.fill"
        }
    }
}
