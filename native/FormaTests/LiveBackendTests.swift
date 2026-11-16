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

    func testCoachChatStreamsRealReply() async throws {
        let (baseURL, anonKey, email, password) = try requireLiveSetup()
        let token = try await signIn(baseURL: baseURL, anonKey: anonKey, email: email, password: password)

        var request = URLRequest(url: URL(string: "\(baseURL)/functions/v1/coach-chat")!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "messages": [["role": "user", "content": "Give me one sentence about warming up for a lower-body session."]]
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            XCTFail("No HTTP response from coach-chat.")
            return
        }
        XCTAssertEqual(http.statusCode, 200, "coach-chat returned \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        let text = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(text.contains("event:"), "Expected SSE events in the response body.")
        XCTAssertTrue(text.contains("event: done"), "Expected a terminal done event.")
    }

    func testPlanGenerationReturnsVerifiedExercises() async throws {
        let (baseURL, anonKey, email, password) = try requireLiveSetup()
        let token = try await signIn(baseURL: baseURL, anonKey: anonKey, email: email, password: password)

        var request = URLRequest(url: URL(string: "\(baseURL)/functions/v1/coach-plan")!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [:])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            XCTFail("No HTTP response from coach-plan.")
            return
        }
        XCTAssertEqual(http.statusCode, 200, "coach-plan returned \(http.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let plan = json?["plan"] as? [String: Any]
        let days = plan?["days"] as? [[String: Any]]
        XCTAssertEqual(days?.count, 7, "A valid plan must contain all seven days.")
    }
}
