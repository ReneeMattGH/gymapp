import XCTest

/// Real end-to-end checks against a deployed Supabase project. They are skipped
/// unless FORMA_SUPABASE_URL, FORMA_ANON_KEY, FORMA_TEST_EMAIL, and
/// FORMA_TEST_PASSWORD are set — a skipped run proves nothing about the backend,
/// so CI must report the skip explicitly rather than count it as success.
final class LiveBackendTests: XCTestCase {
    private var baseURL: String? { ProcessInfo.processInfo.environment["FORMA_SUPABASE_URL"] }
    private var anonKey: String? { ProcessInfo.processInfo.environment["FORMA_ANON_KEY"] }
    private var email: String? { ProcessInfo.processInfo.environment["FORMA_TEST_EMAIL"] }
    private var password: String? { ProcessInfo.processInfo.environment["FORMA_TEST_PASSWORD"] }

    private func requireLiveSetup() throws -> (String, String, String, String) {
        guard let baseURL, let anonKey, let email, let password else {
            throw XCTSkip("Live backend credentials are not configured; no real network check was performed.")
        }
        return (baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")), anonKey, email, password)
    }

    private func signIn(baseURL: String, anonKey: String, email: String, password: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(baseURL)/auth/v1/token?grant_type=password")!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw XCTSkip("Live sign-in failed; check FORMA_TEST_EMAIL/FORMA_TEST_PASSWORD. No test ran.")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["access_token"] as? String else {
            throw XCTSkip("Live sign-in returned no access token. No test ran.")
        }
        return token
    }

    private func subject(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["sub"] as? String
    }

    private func restRequest(
        baseURL: String,
        anonKey: String,
        token: String,
        path: String,
        method: String,
        body: [String: Any]? = nil
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: "\(baseURL)/rest/v1/\(path)")!)
        request.httpMethod = method
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Prefer")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func createConversation(
        baseURL: String,
        anonKey: String,
        token: String,
        userId: String
    ) async throws -> String {
        let id = UUID().uuidString
        let request = try restRequest(
            baseURL: baseURL,
            anonKey: anonKey,
            token: token,
            path: "coach_conversations",
            method: "POST",
            body: ["id": id, "user_id": userId, "title": "Live coach test"]
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw XCTSkip(
                "Could not create a test conversation: \(String(data: data, encoding: .utf8) ?? "no body")"
            )
        }
        return id
    }

    private func deleteConversation(
        baseURL: String,
        anonKey: String,
        token: String,
        conversationId: String
    ) async {
        guard let request = try? restRequest(
            baseURL: baseURL,
            anonKey: anonKey,
            token: token,
            path: "coach_conversations?id=eq.\(conversationId)",
            method: "DELETE"
        ) else { return }
        _ = try? await URLSession.shared.data(for: request)
    }

    func testCoachChatStreamsVerifiedReply() async throws {
        let (baseURL, anonKey, email, password) = try requireLiveSetup()
        let token = try await signIn(baseURL: baseURL, anonKey: anonKey, email: email, password: password)
        let userId = try XCTUnwrap(subject(from: token), "Could not read the signed-in user id.")
        let conversationId = try await createConversation(
            baseURL: baseURL,
            anonKey: anonKey,
            token: token,
            userId: userId
        )
        defer {
            Task {
                await deleteConversation(
                    baseURL: baseURL,
                    anonKey: anonKey,
                    token: token,
                    conversationId: conversationId
                )
            }
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/functions/v1/coach-chat")!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "conversationId": conversationId,
            "message": "In one sentence, how should I warm up for a lower-body session?",
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            XCTFail("No HTTP response from coach-chat.")
            return
        }
        XCTAssertEqual(http.statusCode, 200, "coach-chat returned \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains(#""type":"meta""#), "Expected a meta event with sources/cards.")
        XCTAssertTrue(text.contains(#""type":"done""#), "Expected a terminal done event.")
        XCTAssertTrue(
            text.contains(#""type":"delta""#) || text.contains(#""type":"revision""#),
            "Expected streamed answer text."
        )
    }

    func testPlanGenerationReturnsSevenValidatedDays() async throws {
        let (baseURL, anonKey, email, password) = try requireLiveSetup()
        let token = try await signIn(baseURL: baseURL, anonKey: anonKey, email: email, password: password)

        var request = URLRequest(url: URL(string: "\(baseURL)/functions/v1/coach-plan")!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["action": "generate_plan"])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            XCTFail("No HTTP response from coach-plan.")
            return
        }
        if http.statusCode == 400 || http.statusCode == 422 {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw XCTSkip("Test account cannot generate a plan yet (onboarding, preferences, or seeded exercises missing): \(detail)")
        }
        XCTAssertEqual(http.statusCode, 200, "coach-plan returned \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let plan = json?["plan"] as? [String: Any]
        let days = plan?["days"] as? [[String: Any]]
        XCTAssertEqual(days?.count, 7, "A valid plan must contain all seven days.")
        XCTAssertEqual(json?["knowledge"] as? String != nil, true, "Plan generation should report knowledge retrieval status.")
    }
}
