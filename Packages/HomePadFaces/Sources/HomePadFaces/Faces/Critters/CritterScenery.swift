import SwiftUI

/// Things around Sprig: floating Zs while asleep, rain or snow, confetti
/// after a timer, stars at night, and Bit the firefly, Sprig's friend.
struct CritterScenery: View {
    let look: CritterLook
    let sky: SkyCondition?
    let isNight: Bool
    let isAnimated: Bool
    let ink: Color

    @State private var drift = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                if isNight { stars(size) }
                if look.pose == .sleeping { sleepyZs(size) }
                if look.pose == .celebrating || look.accessory == .partyHat { confetti(size) }
                if sky == .snow { flakes(size) }
                if sky == .rain || sky == .thunder { drops(size) }
                firefly(size)
            }
            .frame(width: size.width, height: size.height)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard isAnimated else { return }
            withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) { drift = true }
        }
    }

    private func stars(_ size: CGSize) -> some View {
        ForEach(0..<14, id: \.self) { index in
            Image(systemName: "star.fill")
                .font(.system(size: size.height * (index % 3 == 0 ? 0.028 : 0.018)))
                .foregroundStyle(ink.opacity(index % 2 == 0 ? 0.55 : 0.3))
                .position(x: size.width * (0.06 + 0.067 * CGFloat(index)), y: size.height * (0.07 + 0.09 * CGFloat((index * 7) % 4)))
        }
    }

    private func sleepyZs(_ size: CGSize) -> some View {
        ForEach(0..<3, id: \.self) { index in
            Text("z")
                .font(.display(size.height * (0.035 + 0.012 * CGFloat(index)), weight: .heavy))
                .foregroundStyle(ink.opacity(0.7))
                .position(x: size.width * (0.8 + 0.04 * CGFloat(index)), y: size.height * (0.58 - 0.07 * CGFloat(index)))
                .offset(y: drift ? -size.height * 0.02 : 0)
                .opacity(drift ? 0.5 : 1)
        }
    }

    private func confetti(_ size: CGSize) -> some View {
        let colors: [Color] = [Color(hex: "#E8457A"), Color(hex: "#F2B33D"), Color(hex: "#5BC0EB"), Color(hex: "#4FAE5C")]
        return ForEach(0..<24, id: \.self) { index in
            RoundedRectangle(cornerRadius: 2)
                .fill(colors[index % colors.count])
                .frame(width: size.height * 0.012, height: size.height * 0.024)
                .rotationEffect(.degrees(Double(index) * 37 + (drift ? 40 : 0)))
                .position(x: size.width * (0.05 + 0.04 * CGFloat(index)), y: size.height * (0.12 + 0.05 * CGFloat((index * 5) % 7)))
                .offset(y: drift ? size.height * 0.03 : 0)
        }
    }

    private func flakes(_ size: CGSize) -> some View {
        ForEach(0..<16, id: \.self) { index in
            Image(systemName: "snowflake")
                .font(.system(size: size.height * 0.025))
                .foregroundStyle(ink.opacity(0.35))
                .position(x: size.width * (0.04 + 0.06 * CGFloat(index)), y: size.height * (0.1 + 0.08 * CGFloat((index * 3) % 6)))
                .offset(y: drift ? size.height * 0.04 : 0)
        }
    }

    private func drops(_ size: CGSize) -> some View {
        ForEach(0..<22, id: \.self) { index in
            Capsule()
                .fill(Color(hex: "#3D7BE0").opacity(0.45))
                .frame(width: 3, height: size.height * 0.03)
                .position(x: size.width * (0.03 + 0.045 * CGFloat(index)), y: size.height * (0.08 + 0.07 * CGFloat((index * 5) % 6)))
                .offset(y: drift ? size.height * 0.05 : 0)
        }
    }

    /// Bit the firefly: a warm dot with wings that glows at night.
    private func firefly(_ size: CGSize) -> some View {
        ZStack {
            Circle().fill(Color(hex: "#FFE27A").opacity(isNight ? 0.45 : 0.2)).frame(width: 34, height: 34).blur(radius: 8)
            HStack(spacing: 2) {
                Ellipse().fill(.white.opacity(0.7)).frame(width: 9, height: 6).rotationEffect(.degrees(-25))
                Ellipse().fill(.white.opacity(0.7)).frame(width: 9, height: 6).rotationEffect(.degrees(25))
            }
            .offset(y: -6)
            Circle().fill(Color(hex: "#FFD23F")).frame(width: 11, height: 11)
        }
        .position(x: size.width * (drift ? 0.74 : 0.66), y: size.height * (drift ? 0.5 : 0.56))
    }
}
