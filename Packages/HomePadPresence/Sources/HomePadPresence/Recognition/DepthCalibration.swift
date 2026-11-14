import Foundation

/// How far one member's own depth faces vary, from their templates, and the
/// match limit depth identity uses for them.
///
/// A person's depth face is never measured the same twice: the dot projector
/// lands differently, the head turns a little, the face is a few centimeters
/// nearer. Each template is compared with the member's templates from other
/// visits, and the limit is `DepthTemplatePolicy.thresholdFactor` times the
/// 95th percentile of those distances. Comparing within one visit would
/// make the faces look steadier than they are.
struct DepthCalibration: Equatable, Sendable {
    var templates: Int
    var visits: Int
    /// The match limit in millimeters. Nil until there are enough templates
    /// from enough visits (`DepthTemplatePolicy`).
    var threshold: Double?

    static func calibrate(_ templates: [DepthTemplate], policy: DepthTemplatePolicy) -> DepthCalibration {
        let sorted = templates.sorted { $0.learnedAt < $1.learnedAt }
        var visit = 0
        var visits: [Int] = []
        for (index, template) in sorted.enumerated() {
            if index > 0, template.learnedAt.timeIntervalSince(sorted[index - 1].learnedAt) > policy.visitGap { visit += 1 }
            visits.append(visit)
        }
        let visitCount = sorted.isEmpty ? 0 : visit + 1
        var calibration = DepthCalibration(templates: sorted.count, visits: visitCount, threshold: nil)
        guard sorted.count >= policy.minimumTemplates, visitCount >= policy.minimumVisits else { return calibration }
        var distances: [Double] = []
        for (index, template) in sorted.enumerated() {
            let others = sorted.indices.filter { visits[$0] != visits[index] }
            if let nearest = others.compactMap({ template.signature.distance(to: sorted[$0].signature) }).min() {
                distances.append(nearest)
            }
        }
        guard distances.count >= policy.minimumTemplates else { return calibration }
        distances.sort()
        let percentile = distances[Int((Double(distances.count - 1) * 0.95).rounded())]
        calibration.threshold = percentile * policy.thresholdFactor
        return calibration
    }

    /// "12 templates from 4 visits, match under 1.40 mm", or what is missing.
    func describe(policy: DepthTemplatePolicy) -> String {
        let counts = "\(templates) template\(templates == 1 ? "" : "s") from \(visits) visit\(visits == 1 ? "" : "s")"
        if let threshold { return counts + ", match under " + String(format: "%.2f mm", threshold) }
        return counts + ", needs \(policy.minimumTemplates) from \(policy.minimumVisits) visits in light"
    }
}
