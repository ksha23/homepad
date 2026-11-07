import SwiftUI

/// Sprig, the Critters face character: a round little sprout creature with a
/// two-leaf tuft, drawn only with SwiftUI shapes. All coordinates are in a
/// 200 by 200 design space scaled to the view.
struct SprigView: View {
    let look: CritterLook
    let isBlinking: Bool
    let isAnimated: Bool

    /// One slow breath drives every motion: the body, the sprout and a waving arm.
    @State private var breathe = false

    private let body1 = Color(hex: "#BFE7B0")
    private let belly = Color(hex: "#E9F7DF")
    private let leaf = Color(hex: "#4FAE5C")
    private let ink = Color(hex: "#23302A")

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width, proxy.size.height) / 200
            ZStack {
                sprout.offset(y: -78)
                arms
                Ellipse().fill(body1).frame(width: 128, height: 116)
                Ellipse().fill(belly).frame(width: 78, height: 60).offset(y: 22)
                feet
                face.offset(y: -12)
                if look.pose == .reading { book.offset(y: 30) }
                if look.pose == .umbrella { umbrella.offset(x: 38, y: -60) }
                accessory
            }
            .frame(width: 200, height: 200)
            .scaleEffect(breathe ? 1.03 : 1, anchor: .bottom)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear {
            guard isAnimated else { return }
            withAnimation(.easeInOut(duration: look.pose == .sleeping ? 3.2 : 2.2).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityLabel("Sprig, \(look.pose.rawValue)")
    }

    // MARK: Parts

    private var sprout: some View {
        ZStack {
            Capsule().fill(leaf).frame(width: 5, height: 24).offset(y: 6)
            Ellipse().fill(leaf).frame(width: 30, height: 15).rotationEffect(.degrees(-30)).offset(x: -13, y: -6)
            Ellipse().fill(leaf.opacity(0.85)).frame(width: 26, height: 13).rotationEffect(.degrees(35)).offset(x: 12, y: -9)
        }
        .rotationEffect(.degrees(breathe ? 4 : -4), anchor: .bottom)
    }

    private var face: some View {
        let sleepy = look.pose == .sleeping
        return ZStack {
            HStack(spacing: 30) { eye(closed: sleepy || isBlinking); eye(closed: sleepy || isBlinking) }
            HStack(spacing: 58) {
                Ellipse().fill(Color(hex: "#FF9FA8").opacity(0.6)).frame(width: 18, height: 10)
                Ellipse().fill(Color(hex: "#FF9FA8").opacity(0.6)).frame(width: 18, height: 10)
            }
            .offset(y: 14)
            mouth.offset(y: 16)
        }
    }

    @ViewBuilder
    private func eye(closed: Bool) -> some View {
        if closed {
            SmileArc().stroke(ink, style: StrokeStyle(lineWidth: 3, lineCap: .round)).frame(width: 14, height: 6)
        } else {
            ZStack {
                Ellipse().fill(ink).frame(width: 12, height: 17)
                Circle().fill(.white).frame(width: 4.5, height: 4.5).offset(x: 2, y: -4)
            }
        }
    }

    @ViewBuilder
    private var mouth: some View {
        switch look.pose {
        case .celebrating, .waving:
            HalfDisc().fill(Color(hex: "#C2475A")).frame(width: 18, height: 10).rotationEffect(.degrees(180))
        case .sleeping:
            Circle().fill(ink.opacity(0.7)).frame(width: 5, height: 5)
        default:
            SmileArc().stroke(ink, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).frame(width: 14, height: 6)
        }
    }

    private var feet: some View {
        HStack(spacing: 34) {
            Ellipse().fill(Color(hex: "#9CCF8E")).frame(width: 30, height: 15)
            Ellipse().fill(Color(hex: "#9CCF8E")).frame(width: 30, height: 15)
        }
        .offset(y: 56)
    }

    private var arms: some View {
        let (left, right) = armAngles
        return ZStack {
            arm.rotationEffect(.degrees(left), anchor: .top).offset(x: -50, y: -2)
            arm.rotationEffect(.degrees(right), anchor: .top).offset(x: 50, y: -2)
        }
    }

    private var arm: some View {
        Capsule().fill(Color(hex: "#A9DD99")).frame(width: 16, height: 38).offset(y: 12)
    }

    /// Arm rotations in degrees (0 hangs down, 180 points up).
    private var armAngles: (Double, Double) {
        switch look.pose {
        case .waving: (20, breathe ? -150 : -120)
        case .stretching: (160, -160)
        case .celebrating: (breathe ? 150 : 135, breathe ? -135 : -150)
        case .reading: (-40, 40)
        case .umbrella: (20, -150)
        case .sleeping: (15, -15)
        }
    }

    private var book: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: "#E2574C")).frame(width: 58, height: 40)
            Rectangle().fill(.white.opacity(0.85)).frame(width: 2, height: 36)
        }
        .rotation3DEffect(.degrees(18), axis: (x: 1, y: 0, z: 0))
    }

    private var umbrella: some View {
        ZStack {
            Capsule().fill(ink).frame(width: 3, height: 70).offset(y: 30)
            HalfDisc().fill(Color(hex: "#3D7BE0")).frame(width: 110, height: 52).offset(y: -12)
            HalfDisc().fill(Color(hex: "#FFFFFF").opacity(0.25)).frame(width: 40, height: 52).offset(y: -12)
        }
    }

    @ViewBuilder
    private var accessory: some View {
        CritterAccessoryView(accessory: look.accessory)
    }
}

/// A shallow upward arc, used for closed eyes and smiles.
struct SmileArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.6))
        return path
    }
}

/// The top half of an ellipse filling the rect, flat side down.
struct HalfDisc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height))
        path.closeSubpath()
        return path
    }
}
