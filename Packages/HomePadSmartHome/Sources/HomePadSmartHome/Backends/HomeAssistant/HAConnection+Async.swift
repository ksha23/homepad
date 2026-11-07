import Foundation
import HAKit
import HomePadCore
import os

extension HAConnection {
    /// Sends a request and waits for its result, giving up (and cancelling it) after `timeout`.
    /// Runs on the main actor, so parallel requests reach HAKit one at a time.
    /// The timeout stops as soon as the answer arrives, so a request leaves nothing behind.
    @MainActor
    func send(_ request: HARequest, timeout: Duration = .seconds(15)) async throws -> HAData {
        let resumed = OSAllocatedUnfairLock(initialState: false)
        let timer = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)
        return try await withCheckedThrowingContinuation { continuation in
            func finish(_ result: Result<HAData, Error>) -> Bool {
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(with: result) }
                return first
            }
            let token = send(request) { result in
                if finish(result.mapError { $0 as Error }) {
                    timer.withLock { $0?.cancel() }
                }
            }
            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                if finish(.failure(SmartHomeError.backend("Home Assistant did not answer in time."))) {
                    token.cancel()
                }
            }
            timer.withLock { $0 = timeoutTask }
            // The answer can arrive before the timer exists.
            if resumed.withLock({ $0 }) { timeoutTask.cancel() }
        }
    }
}
