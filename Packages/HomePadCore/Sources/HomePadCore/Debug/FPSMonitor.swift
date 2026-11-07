#if os(iOS)
import Foundation
import os
import QuartzCore

/// An instrument for measuring animation frame rate (FPS), frame intervals and hitches.
///
/// Uses `CADisplayLink` on `.common` RunLoop mode to measure actual presentation
/// cadence at up to 120Hz (ProMotion on M4 iPad).
///
/// Recordings are named and may overlap: an app zoom and the screen it opens
/// each record their own. One display link serves them all and runs only while
/// one of them records. A recording runs for a set time (`start(name:duration:)`)
/// or until it is ended (`begin(name:)` and `end(name:)`), for something with
/// no set length, such as a scroll.
@MainActor
public final class FPSMonitor: ObservableObject {
    public static let shared = FPSMonitor()

    public struct Report: Sendable, CustomStringConvertible, Equatable {
        public let name: String
        public let targetFPS: Double
        public let averageFPS: Double
        public let minFPS: Double
        public let totalFrames: Int
        public let hitchedFrames: Int
        public let maxHitchMs: Double
        public let duration: TimeInterval

        public var description: String {
            String(
                format: "[FPS] %@: avg %.1f FPS (nominal %.0f), min %.1f FPS, %d hitches (max %.1fms) across %d frames (%.2fs)",
                name, averageFPS, targetFPS, minFPS, hitchedFrames, maxHitchMs, totalFrames, duration
            )
        }
    }

    @Published public private(set) var lastReport: Report?
    @Published public private(set) var isRecording = false

    /// One named recording: the time between frames since it began.
    private struct Session {
        var intervals: [CFTimeInterval] = []
        var lastTimestamp: CFTimeInterval = 0
        var stopTask: Task<Void, Never>?
    }

    private var sessions: [String: Session] = [:]
    private var displayLink: CADisplayLink?
    private var nominalInterval: CFTimeInterval = 1.0 / 120.0
    private let logger = Logger(subsystem: "com.ksha23.homepad", category: "Performance")
    private let trace = DebugTrace(file: "fps-trace.txt", argument: "HomePadAudioTrace")

    private init() {}

    /// Records frames for `name` for `duration` seconds, then reports them.
    /// Starting a name that is recording starts it over.
    public func start(name: String, duration: TimeInterval = 1.5) {
        begin(name: name)
        sessions[name]?.stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.end(name: name)
        }
    }

    /// Records frames for `name` until `end(name:)`. Beginning a name that is
    /// recording starts it over.
    public func begin(name: String) {
        sessions[name]?.stopTask?.cancel()
        sessions[name] = Session()
        isRecording = true
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Ends the recording for `name` and reports it. Does nothing when `name` is not recording.
    public func end(name: String) {
        guard let session = sessions.removeValue(forKey: name) else { return }
        session.stopTask?.cancel()
        stopLinkIfIdle()
        report(name: name, intervals: session.intervals)
    }

    /// Stops every recording without reporting.
    public func stop() {
        for session in sessions.values { session.stopTask?.cancel() }
        sessions.removeAll()
        stopLinkIfIdle()
    }

    private func stopLinkIfIdle() {
        guard sessions.isEmpty else { return }
        displayLink?.invalidate()
        displayLink = nil
        isRecording = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        let current = link.timestamp
        if nominalInterval == 0 || link.targetTimestamp > link.timestamp {
            let interval = link.targetTimestamp - link.timestamp
            if interval > 0 {
                nominalInterval = interval
            }
        }
        // Changed in place, so a long recording's intervals are not copied on every frame.
        for name in Array(sessions.keys) {
            if let last = sessions[name]?.lastTimestamp, last > 0 {
                sessions[name]?.intervals.append(current - last)
            }
            sessions[name]?.lastTimestamp = current
        }
    }

    private func report(name: String, intervals: [CFTimeInterval]) {
        guard !intervals.isEmpty else { return }

        let nominalFPS = nominalInterval > 0 ? (1.0 / nominalInterval).rounded() : 120.0
        let totalTime = intervals.reduce(0, +)
        let avgFPS = totalTime > 0 ? Double(intervals.count) / totalTime : 0.0

        var minInstantFPS = nominalFPS
        var hitchedFrames = 0
        var maxHitchMs: Double = 0

        // A hitch is any frame interval exceeding 1.25x the nominal interval
        let hitchThreshold = nominalInterval * 1.25

        for delta in intervals {
            let fps = delta > 0 ? (1.0 / delta) : nominalFPS
            if fps < minInstantFPS { minInstantFPS = fps }
            if delta > hitchThreshold {
                hitchedFrames += 1
                let hitchMs = (delta - nominalInterval) * 1000.0
                if hitchMs > maxHitchMs { maxHitchMs = hitchMs }
            }
        }

        let report = Report(
            name: name,
            targetFPS: nominalFPS,
            averageFPS: avgFPS,
            minFPS: minInstantFPS,
            totalFrames: intervals.count,
            hitchedFrames: hitchedFrames,
            maxHitchMs: maxHitchMs,
            duration: totalTime
        )

        lastReport = report
        let desc = report.description
        print(desc)
        logger.notice("\(desc, privacy: .public)")
        trace.log(desc)
        writeToTraceFile(desc)
    }

    private func writeToTraceFile(_ text: String) {
        guard let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = folder.appendingPathComponent("fps-trace.txt")
        let line = String(format: "%8.3f ", Date().timeIntervalSinceReferenceDate) + text + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
#else
import Foundation

@MainActor
public final class FPSMonitor {
    public static let shared = FPSMonitor()
    public struct Report: Sendable, CustomStringConvertible, Equatable {
        public let name: String
        public let targetFPS: Double = 120
        public let averageFPS: Double = 120
        public let minFPS: Double = 120
        public let totalFrames: Int = 0
        public let hitchedFrames: Int = 0
        public let maxHitchMs: Double = 0
        public let duration: TimeInterval = 0
        public var description: String { "[FPS] \(name): stub" }
    }
    public private(set) var lastReport: Report?
    public func start(name: String, duration: TimeInterval = 1.5) {}
    public func begin(name: String) {}
    public func end(name: String) {}
    public func stop() {}
}
#endif
