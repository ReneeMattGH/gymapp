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

    private struct RPCResult {
        let status: Int
        let data: Data
        var text: String { String(data: data, encoding: .utf8) ?? "" }
    }

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

    private func rpc(
        baseURL: String,
        anonKey: String,
        token: String,
        name: String,
        body: [String: Any] = [:]
    ) async throws -> RPCResult {
        var request = URLRequest(url: URL(string: "\(baseURL)/rest/v1/rpc/\(name)")!)
        request.httpMethod = "POST"
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            XCTFail("No HTTP response from \(name).")
            return RPCResult(status: -1, data: data)
        }
        return RPCResult(status: http.statusCode, data: data)
    }

    // MARK: - Bootstrap

    func testCommunityBootstrapReturnsSignedInState() async throws {
        let (baseURL, anonKey, email, password) = try requireLiveSetup()
        let token = try await signIn(baseURL: baseURL, anonKey: anonKey, email: email, password: password)
        let result = try await rpc(baseURL: baseURL, anonKey: anonKey, token: token, name: "community_bootstrap")
        XCTAssertEqual(result.status, 200, "community_bootstrap returned \(result.status): \(result.text)")

        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: result.data) as? [String: Any],
            "community_bootstrap did not return a JSON object."
        )
        for key in [
            "profile", "preferences", "membership", "is_admin", "suspended",
            "members_at_gym", "nearby_members", "incoming_request_count",
            "unread_notifications", "unread_messages", "suggestions", "nearby",
            "incoming_requests", "connections", "feed", "areas",
        ] {
            XCTAssertNotNil(json[key], "community_bootstrap is missing \(key).")
        }
        XCTAssertTrue(json["suggestions"] is [Any], "Suggestions must be an array, even when empty.")
        XCTAssertTrue(json["areas"] is [Any], "Areas must be an array, even when empty.")
    }

    // MARK: - Discovery privacy

    func testCommunityDiscoveryExposesNoPrivateContactOrLocation() async throws {
        let (baseURL, anonKey, email, password) = try requireLiveSetup()
        let token = try await signIn(baseURL: baseURL, anonKey: anonKey, email: email, password: password)
        let result = try await rpc(
            baseURL: baseURL,
            anonKey: anonKey,
            token: token,
            name: "community_discover",
            body: ["p_scope": "all", "p_query": "", "p_interest": "", "p_limit": 5, "p_offset": 0]
        )
        XCTAssertEqual(result.status, 200, "community_discover returned \(result.status): \(result.text)")

        let rows = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: result.data) as? [[String: Any]],
            "community_discover did not return an array."
        )
        XCTAssertLessThanOrEqual(rows.count, 5, "Discovery ignored the requested page size.")

        let allowed: Set<String> = [
            "user_id", "username", "display_name", "avatar_url", "bio",
            "interests", "workout_categories", "gym_name", "area", "city",
            "connection_status",
        ]
        let forbidden = ["email", "phone", "address", "latitude", "longitude", "gps", "presence", "last_seen", "distance"]
        let statuses: Set<String> = ["none", "pending_sent", "pending_received", "accepted", "blocked"]

        for row in rows {
            for key in row.keys {
                XCTAssertTrue(allowed.contains(key), "Discovery leaked unexpected field \(key).")
            }
            for key in row.keys {
                XCTAssertFalse(
                    forbidden.contains(where: { key.lowercased().contains($0) }),
                    "Discovery exposed private field \(key)."
                )
            }
            let status = try XCTUnwrap(row["connection_status"] as? String, "Each member needs a connection_status.")
            XCTAssertTrue(statuses.contains(status), "Unexpected connection_status \(status).")
        }
    }

    // MARK: - Messaging enforcement

    func testCommunityMessagingRequiresAConnection() async throws {
        let (baseURL, anonKey, email, password) = try requireLiveSetup()
        let token = try await signIn(baseURL: baseURL, anonKey: anonKey, email: email, password: password)
        let result = try await rpc(
            baseURL: baseURL,
            anonKey: anonKey,
            token: token,
            name: "community_messages_list",
            body: [
                "p_conversation_id": UUID().uuidString,
                "p_limit": 10,
            ]
        )
        XCTAssertFalse(
            (200..<300).contains(result.status),
            "Reading an unrelated conversation must fail. Got \(result.status): \(result.text)"
        )
        XCTAssertTrue(
            result.text.lowercased().contains("not available"),
            "Expected the server to explain that the conversation is not available. Got: \(result.text)"
        )
    }

    // MARK: - Admin enforcement

    func testCommunityAdminReportsRequireAdministratorRole() async throws {
        let (baseURL, anonKey, email, password) = try requireLiveSetup()
        let token = try await signIn(baseURL: baseURL, anonKey: anonKey, email: email, password: password)
        let result = try await rpc(baseURL: baseURL, anonKey: anonKey, token: token, name: "community_admin_reports")

        if (200..<300).contains(result.status) {
            throw XCTSkip("The test account has the administrator role, so the non-admin rejection cannot be exercised.")
        }
        XCTAssertTrue(
            result.text.lowercased().contains("administrator access required"),
            "Expected the server to reject a non-admin call. Got \(result.status): \(result.text)"
        )
    }
}
