import SwiftUI

/// Hats, glasses and other dress-up for Sprig, in the same 200 by 200
/// design space as `SprigView`.
struct CritterAccessoryView: View {
    let accessory: CritterAccessory

    var body: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .nightcap:
            hat(color: Color(hex: "#5B6BD6"), stripe: Color(hex: "#9AA6F2"), pom: .white, tilt: -28)
        case .santaHat:
            ZStack {
                hat(color: Color(hex: "#D7363B"), stripe: Color(hex: "#D7363B"), pom: .white, tilt: -20)
                Capsule().fill(.white).frame(width: 84, height: 16).offset(y: -52)
            }
        case .partyHat:
            hat(color: Color(hex: "#F2B33D"), stripe: Color(hex: "#E8457A"), pom: Color(hex: "#5BC0EB"), tilt: 12)
        case .pumpkinHat:
            ZStack {
                Ellipse().fill(Color(hex: "#F28C28")).frame(width: 76, height: 46)
                Ellipse().stroke(Color(hex: "#C8661A"), lineWidth: 2).frame(width: 34, height: 46)
                Capsule().fill(Color(hex: "#4FAE5C")).frame(width: 7, height: 14).offset(y: -26)
            }
            .offset(y: -62)
        case .heart:
            Image(systemName: "heart.fill")
                .font(.system(size: 34))
                .foregroundStyle(Color(hex: "#E8457A"))
                .offset(x: 70, y: -70)
        case .scarf:
            ZStack {
                Capsule().fill(Color(hex: "#D7363B")).frame(width: 112, height: 16)
                Capsule().fill(Color(hex: "#D7363B")).frame(width: 16, height: 34).rotationEffect(.degrees(12)).offset(x: 30, y: 18)
            }
            .offset(y: 26)
        case .sunglasses:
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 7).fill(Color(hex: "#1D1F24")).frame(width: 30, height: 20)
                RoundedRectangle(cornerRadius: 7).fill(Color(hex: "#1D1F24")).frame(width: 30, height: 20)
            }
            .overlay(Capsule().fill(Color(hex: "#1D1F24")).frame(width: 74, height: 4).offset(y: -6))
            .offset(y: -13)
        }
    }

    /// A floppy cone hat with a stripe and a pom-pom.
    private func hat(color: Color, stripe: Color, pom: Color, tilt: Double) -> some View {
        ZStack {
            Triangle().fill(color).frame(width: 74, height: 64)
            Triangle().fill(stripe.opacity(0.6)).frame(width: 30, height: 26).offset(y: -6)
            Circle().fill(pom).frame(width: 18, height: 18).offset(y: -34)
        }
        .rotationEffect(.degrees(tilt))
        .offset(y: -84)
    }
}

/// An upward-pointing triangle filling its rect.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
