import CoreGraphics
import Foundation
import SwiftUI

/// Pure motion for the Flow face: where the mesh gradient's control points
/// and the time's glass drops are at a moment, and how presence changes them.
enum FlowMotion {

    /// The 3 by 3 mesh control points. Corners stay put, the rest sway slowly.
    static func meshPoints(time: Double) -> [SIMD2<Float>] {
        var points: [SIMD2<Float>] = []
        for row in 0..<3 {
            for column in 0..<3 {
                var x = Double(column) / 2
                var y = Double(row) / 2
                let isEdgeX = column == 0 || column == 2
                let isEdgeY = row == 0 || row == 2
                let phase = Double(row * 3 + column)
                if !isEdgeX { x += 0.18 * sin(time * 0.11 + phase) }
                if !isEdgeY { y += 0.16 * cos(time * 0.09 + phase * 1.3) }
                points.append(SIMD2(Float(x), Float(y)))
            }
        }
        return points
    }

    /// How large the time is for an `intensity` (0...1), as a share of its
    /// full size: it grows as someone comes closer, so it seems to come
    /// toward them, and is full size within arm's reach.
    static func clockScale(intensity: Double) -> CGFloat {
        CGFloat(0.84 + 0.16 * min(max(intensity, 0), 1))
    }

    /// How far a glyph of the time has bobbed from its place at `time`, in
    /// digit widths: a slow drift of a few hundredths, each glyph on its own
    /// phase, so the drops float without the time ever being hard to read.
    static func drift(time: Double, index: Int) -> CGPoint {
        let i = Double(index)
        return CGPoint(x: 0.025 * sin(time * 0.37 + i * 1.9), y: 0.045 * sin(time * 0.5 + i * 1.3))
    }

    /// A change of intensity on its way: from where it was to a new level,
    /// eased on a spring from `start`. Flow redraws its drops from the clock
    /// many times a second, so the intensity is worked out for each frame
    /// rather than animated.
    struct IntensityMove: Equatable {
        var from: Double
        var to: Double
        var start: Date

        /// Resting at `level`.
        init(settledAt level: Double) {
            self.init(from: level, to: level, start: .distantPast)
        }

        init(from: Double, to: Double, start: Date) {
            self.from = from
            self.to = to
            self.start = start
        }

        /// The intensity at `date`.
        func value(at date: Date, spring: Spring) -> Double {
            let elapsed = date.timeIntervalSince(start)
            guard elapsed > 0, from != to else { return elapsed > 0 ? to : from }
            let progress = min(max(spring.value(target: 1.0, time: elapsed), 0), 1)
            return from + (to - from) * progress
        }

        /// A move to `level` starting at `date`, from wherever this one has got to.
        func moving(to level: Double, at date: Date, spring: Spring) -> IntensityMove {
            IntensityMove(from: value(at: date, spring: spring), to: level, start: date)
        }
    }

    /// 0.2 when nobody is around, up to 1 within arm's reach.
    static func intensity(for proximity: Int) -> Double {
        switch proximity {
        case ...0: 0.2
        case 1: 0.5
        case 2: 0.8
        default: 1
        }
    }
}
