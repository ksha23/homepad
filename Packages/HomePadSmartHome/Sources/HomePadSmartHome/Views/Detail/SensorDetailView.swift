import Charts
import HomePadCore
import HomePadUI
import SwiftUI

/// A sensor's reading in big numerals, with the last day as a chart when the
/// backend has history. A sensor without a number ("Clear", "Closed") shows
/// its symbol in a glass circle over its state, like a lock or a switch.
/// Sizes come from `DetailControlMetrics`, as every other detail's do.
struct SensorDetailView: View {
    @Environment(UnifiedSmartHomeService.self) private var service
    @Environment(\.detailControlMetrics) private var metrics
    let accessory: HomeAccessory
    @State private var samples: [SensorSample] = []

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Spacer(minLength: 0)
            if let value = accessory.state.sensorValue {
                Image(systemName: AccessoryPresentation.symbol(for: accessory))
                    .font(.display(metrics.statusSize))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                    Text(value.formatted(.number.precision(.fractionLength(0...1))))
                        .font(.display(metrics.readingSize))
                        .contentTransition(.numericText(value: value))
                    Text(accessory.state.sensorUnit ?? "").font(.display(metrics.statusSize)).foregroundStyle(.secondary)
                }
                if samples.count > 1 {
                    chart.frame(maxWidth: 820, maxHeight: 260)
                }
            } else {
                Image(systemName: AccessoryPresentation.symbol(for: accessory))
                    .font(.system(size: metrics.circle * 0.4, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: metrics.circle, height: metrics.circle)
                    .glassEffect(.regular, in: .circle)
                Text(AccessoryPresentation.status(for: accessory)).font(.display(metrics.statusSize))
            }
            Spacer(minLength: 0)
        }
        .task(id: accessory.id) {
            if accessory.state.sensorValue != nil {
                samples = await service.history(for: accessory.id, hours: 24)
            }
        }
    }

    private var chart: some View {
        let low = samples.map(\.value).min() ?? 0
        let high = samples.map(\.value).max() ?? 1
        let padding = max((high - low) * 0.15, 0.5)
        return GlassPanel {
            Chart(samples, id: \.date) { sample in
                AreaMark(x: .value("Time", sample.date), yStart: .value("Base", low - padding), yEnd: .value("Value", sample.value))
                    .foregroundStyle(LinearGradient(colors: [.orange.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Time", sample.date), y: .value("Value", sample.value))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: (low - padding)...(high + padding))
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
            .chartYAxis { AxisMarks(position: .leading) }
        }
        .accessibilityLabel("Last 24 hours")
    }
}
