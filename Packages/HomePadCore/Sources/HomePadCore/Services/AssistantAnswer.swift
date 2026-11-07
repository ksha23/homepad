import Foundation

public extension AssistantService {
    /// The whole answer to a request as text, for modules that hand the
    /// assistant a text task and read its reply (a recipe or events from
    /// scanned text). Nil on an error, an empty answer or after `timeout`.
    func answerText(to request: AssistantRequest, timeout: Duration) async -> String? {
        let stream = ask(request)
        return await withTaskGroup(of: String?.self) { group in
            group.addTask {
                var text = ""
                do {
                    for try await event in stream {
                        switch event {
                        case .textDelta(let delta): text += delta
                        case .finished(let fullText): return fullText.isEmpty ? text : fullText
                        default: break
                        }
                    }
                } catch {
                    return nil
                }
                return text.isEmpty ? nil : text
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
