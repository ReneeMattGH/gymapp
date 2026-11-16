import Foundation

/// One server-sent event from the coach-chat Edge Function.
struct CoachStreamEvent: Decodable {
    var type: String
    var text: String?
    var message: String?
    var messageId: String?
    var createdAt: String?
    var sources: [CoachSource]?
    var cards: [CoachCard]?
    var unverified: Bool?
    var intent: String?
    var modelLabel: String?
}

/// Pure line parser for the streaming protocol. Keeping it separate from the
/// networking layer makes the wire format testable without a live backend.
struct CoachStreamParser {
    enum Output {
        case event(CoachStreamEvent)
        case done
        case ignore
    }

    mutating func consume(line rawLine: String) -> Output {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("data:") else { return .ignore }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload.isEmpty { return .ignore }
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let event = try? JSONDecoder().decode(CoachStreamEvent.self, from: data) else {
            return .ignore
        }
        return .event(event)
    }
}
