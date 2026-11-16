import Foundation

private struct PlanResponse: Decodable {
    var plan: AIPlanPayload?
    var error: String?
}

private struct InsightResponse: Decodable {
    var insight: String?
    var error: String?
}

private struct ErrorResponse: Decodable {
    var error: String?
    var message: String?
}

/// A completed coach reply. `messageId` is present only when the backend saved
/// the reply, which lets the client avoid persisting it twice.
struct CoachReply: Sendable {
    var text: String
    var messageId: String?
    var createdAt: Date
    var sources: [CoachSource]
    var cards: [CoachCard]
    var unverified: Bool
    var intent: String?

    init(
        text: String,
        messageId: String?,
        createdAt: Date,
        sources: [CoachSource],
        cards: [CoachCard] = [],
        unverified: Bool = false,
        intent: String? = nil
    ) {
        self.text = text
        self.messageId = messageId
        self.createdAt = createdAt
        self.sources = sources
        self.cards = cards
        self.unverified = unverified
        self.intent = intent
    }
}

enum CoachStreamFailure: LocalizedError {
    case blocked(String)
    case rateLimited(String)
    case timedOut
    case unreachable
    case message(String)

    var errorDescription: String? {
        switch self {
        case .blocked(let text): text
        case .rateLimited(let text): text
        case .timedOut: "The coach took too long to respond. Please try again."
        case .unreachable: "The coach could not be reached. Check your connection and try again."
        case .message(let text): text
        }
    }

    var isRetryable: Bool {
        switch self {
        case .rateLimited, .unreachable, .timedOut: true
        case .blocked, .message: false
        }
    }

    var retryDelay: Duration {
        if case .rateLimited = self { return .milliseconds(2200) }
        return .milliseconds(1200)
    }
}

private final class DeltaFlag {
    var value = false
}

/// Talks to the Forma Edge Functions. The OpenAI key lives only on the server;
/// this client sends the user's Supabase access token and nothing else.
@MainActor
final class AICoachService {
    private let tokens: AITokenProviding
    private let session: URLSession

    init(tokens: AITokenProviding) {
        self.tokens = tokens
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    private func request(path: String, body: [String: Any]) async throws -> (Data, HTTPURLResponse) {
        guard let base = tokens.functionsURL else { throw FormaError.notConfigured }
        let token = try await tokens.accessToken()
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(tokens.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoachStreamFailure.unreachable
        }
        return (data, http)
    }

    private static func errorMessage(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            if let error = decoded.error, !error.isEmpty { return error }
            if let message = decoded.message, !message.isEmpty { return message }
        }
        return nil
    }

    private static func failure(data: Data, status: Int) -> CoachStreamFailure {
        let detail = errorMessage(from: data)
        switch status {
        case 401, 403:
            return .message(FormaError.notAuthenticated.localizedDescription)
        case 408, 504:
            return .timedOut
        case 429:
            return .rateLimited(detail ?? "The coach is busy right now. Wait a few seconds and try again.")
        case 500...599:
            return .unreachable
        default:
            return .message(detail ?? "The coach ran into a problem (status \(status)). Please try again.")
        }
    }

    /// Streams a reply. Retries once, with backoff, only when nothing has been
    /// shown yet and the failure is transient. Cancellation always propagates.
    func streamReply(
        conversationId: String,
        message: String,
        onDelta: @escaping (String) -> Void,
        onRevision: ((String) -> Void)? = nil
    ) async throws -> CoachReply {
        let received = DeltaFlag()
        var attempt = 0
        while true {
            do {
                return try await performStream(
                    conversationId: conversationId,
                    message: message,
                    onDelta: { text in
                        received.value = true
                        onDelta(text)
                    },
                    onRevision: onRevision
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let failure as CoachStreamFailure where failure.isRetryable {
                guard attempt == 0, !received.value else { throw failure }
                attempt += 1
                try await Task.sleep(for: failure.retryDelay)
                continue
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch let error as URLError {
                guard attempt == 0, !received.value else {
                    throw error.code == .timedOut ? CoachStreamFailure.timedOut : CoachStreamFailure.unreachable
                }
                attempt += 1
                try await Task.sleep(for: .milliseconds(1200))
                continue
            } catch {
                throw error
            }
        }
    }

    private func performStream(
        conversationId: String,
        message: String,
        onDelta: @escaping (String) -> Void,
        onRevision: ((String) -> Void)?
    ) async throws -> CoachReply {
        guard let base = tokens.functionsURL else { throw FormaError.notConfigured }
        let token = try await tokens.accessToken()
        var request = URLRequest(url: base.appendingPathComponent("coach-chat"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(tokens.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "conversationId": conversationId,
            "message": message,
        ])

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CoachStreamFailure.unreachable
        }

        if !(200..<300).contains(http.statusCode) {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            throw Self.failure(data: body, status: http.statusCode)
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if contentType.contains("application/json") {
            var body = Data()
            for try await byte in bytes { body.append(byte) }
            struct Reply: Decodable { var reply: String?; var error: String? }
            let decoded = try? JSONDecoder().decode(Reply.self, from: body)
            if let error = decoded?.error, !error.isEmpty {
                throw CoachStreamFailure.message(error)
            }
            let reply = (decoded?.reply ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else {
                throw CoachStreamFailure.message("The coach returned an empty reply. Please try again.")
            }
            onDelta(reply)
            return CoachReply(
                text: reply,
                messageId: nil,
                createdAt: Date(),
                sources: [],
                cards: [],
                unverified: false,
                intent: nil
            )
        }

        var full = ""
        var finished = false
        var sources: [CoachSource] = []
        var cards: [CoachCard] = []
        var unverified = false
        var intent: String?
        var messageId: String?
        var createdAt: Date?
        var parser = CoachStreamParser()

        for try await rawLine in bytes.lines {
            if Task.isCancelled { throw CancellationError() }
            switch parser.consume(line: rawLine) {
            case .ignore:
                continue
            case .done:
                finished = true
            case .event(let event):
                switch event.type {
                case "meta":
                    sources = event.sources ?? sources
                    cards = event.cards ?? cards
                    unverified = event.unverified ?? false
                    intent = event.intent
                case "revision":
                    if let text = event.text, !text.isEmpty {
                        full = text
                        onRevision?(text)
                    }
                case "delta":
                    if let text = event.text, !text.isEmpty {
                        full += text
                        onDelta(text)
                    }
                case "blocked":
                    throw CoachStreamFailure.blocked(
                        event.message ?? "That draft response did not meet Forma's safety standards."
                    )
                case "error":
                    throw CoachStreamFailure.message(event.message ?? "The coach ran into a problem.")
                case "done":
                    messageId = event.messageId
                    createdAt = event.createdAt.flatMap(FormaDate.parse)
                    if let eventSources = event.sources { sources = eventSources }
                    if let eventCards = event.cards { cards = eventCards }
                    unverified = event.unverified ?? unverified
                    intent = event.intent ?? intent
                    finished = true
                default:
                    break
                }
            }
            if finished { break }
        }

        let text = full.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw CoachStreamFailure.message("The coach returned an empty reply. Please try again.")
        }
        return CoachReply(
            text: text,
            messageId: messageId,
            createdAt: createdAt ?? Date(),
            sources: sources,
            cards: cards,
            unverified: unverified,
            intent: intent
        )
    }

    func requestPlan() async throws -> AIPlanPayload {
        let (data, http) = try await request(path: "coach-plan", body: ["action": "generate_plan"])
        guard (200..<300).contains(http.statusCode) else {
            throw Self.failure(data: data, status: http.statusCode)
        }
        let decoded = try? JSONDecoder().decode(PlanResponse.self, from: data)
        if let error = decoded?.error, !error.isEmpty { throw CoachStreamFailure.message(error) }
        guard let plan = decoded?.plan else {
            throw CoachStreamFailure.message("The AI coach did not return a plan. Please try again.")
        }
        return plan
    }

    func dailyInsight() async throws -> String {
        let (data, http) = try await request(path: "coach-plan", body: ["action": "daily_insight"])
        guard (200..<300).contains(http.statusCode) else {
            throw Self.failure(data: data, status: http.statusCode)
        }
        let decoded = try? JSONDecoder().decode(InsightResponse.self, from: data)
        if let error = decoded?.error, !error.isEmpty { throw CoachStreamFailure.message(error) }
        guard let insight = decoded?.insight, !insight.isEmpty else {
            throw CoachStreamFailure.message("The AI coach did not return a note. Please try again.")
        }
        return insight
    }
}
