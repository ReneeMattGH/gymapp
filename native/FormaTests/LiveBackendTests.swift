import XCTest

/// End-to-end checks against a running Forma backend. The URL comes from
/// FORMA_LIVE_API_URL when the test runner receives it, otherwise from the
/// build's FORMA_API_URL (Debug points at http://localhost:8787). If no server
/// answers, the test is reported as skipped — a skip never counts as a pass.
final class LiveBackendTests: XCTestCase {
    private var baseURL: URL? {
        if let raw = ProcessInfo.processInfo.environment["FORMA_LIVE_API_URL"],
           let url = URL(string: raw) {
            return url
        }
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "FORMA_API_URL") as? String,
              let url = URL(string: raw),
              url.scheme?.hasPrefix("http") == true,
              url.host != nil else { return nil }
        return url
    }

    private struct Response {
        let status: Int
        let data: Data
        var json: [String: Any] { (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:] }
        var text: String { String(data: data, encoding: .utf8) ?? "" }
    }

    private func requireBackend() async throws -> URL {
        guard let baseURL else {
            throw XCTSkip("No FORMA_API_URL is configured in this build; no real backend check was performed.")
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("health"))
        request.timeoutInterval = 3
        let ok: Bool
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            ok = (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            ok = false
        }
        guard ok else {
            throw XCTSkip("No backend answered at \(baseURL.absoluteString); nothing was verified.")
        }
        return baseURL
    }

    private func call(
        _ method: String,
        _ path: String,
        baseURL: URL,
        token: String? = nil,
        body: [String: Any]? = nil
    ) async throws -> Response {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse, "No HTTP response for \(method) \(path).")
        return Response(status: http.statusCode, data: data)
    }

    private func tokens(_ response: Response) throws -> (access: String, refresh: String) {
        let json = try XCTUnwrap(response.json["tokens"] as? [String: Any], "Response had no tokens: \(response.text)")
        let access = try XCTUnwrap(json["accessToken"] as? String)
        let refresh = try XCTUnwrap(json["refreshToken"] as? String)
        return (access, refresh)
    }

    private func rejectIfRateLimited(_ response: Response, _ step: String) throws {
        guard response.status == 429 else { return }
        throw XCTSkip("The backend rate-limited \(step). No verification was performed; run the server with NODE_ENV=test for a full live check.")
    }

    func testAuthLifecycleAgainstRealBackend() async throws {
        let baseURL = try await requireBackend()

        let health = try await call("GET", "health", baseURL: baseURL)
        XCTAssertEqual(health.status, 200, "Health check returned \(health.status): \(health.text)")

        let email = "live-\(UUID().uuidString.lowercased())@example.com"
        let password = "correct-horse-battery-\(UUID().uuidString.prefix(6))"

        let register = try await call(
            "POST",
            "api/v1/auth/register",
            baseURL: baseURL,
            body: ["email": email, "password": password, "displayName": "Live Test"]
        )
        try rejectIfRateLimited(register, "registration")
        XCTAssertEqual(register.status, 201, "Register returned \(register.status): \(register.text)")
        XCTAssertEqual(register.json["emailVerificationSent"] as? Bool, false, "No SMTP is configured, so no email can honestly be reported as sent.")
        let first = try tokens(register)

        let me = try await call("GET", "api/v1/auth/me", baseURL: baseURL, token: first.access)
        XCTAssertEqual(me.status, 200, "Me returned \(me.status): \(me.text)")
        let user = try XCTUnwrap(me.json["user"] as? [String: Any])
        XCTAssertEqual(user["email"] as? String, email)
        XCTAssertEqual(user["emailVerified"] as? Bool, false)

        let refresh = try await call(
            "POST",
            "api/v1/auth/refresh",
            baseURL: baseURL,
            body: ["refreshToken": first.refresh]
        )
        try rejectIfRateLimited(refresh, "token refresh")
        XCTAssertEqual(refresh.status, 200, "Refresh returned \(refresh.status): \(refresh.text)")
        let rotated = try tokens(refresh)
        XCTAssertNotEqual(rotated.refresh, first.refresh, "Refresh must rotate the token.")

        let reuse = try await call(
            "POST",
            "api/v1/auth/refresh",
            baseURL: baseURL,
            body: ["refreshToken": first.refresh]
        )
        try rejectIfRateLimited(reuse, "refresh-token reuse")
        XCTAssertEqual(reuse.status, 401, "Reusing a rotated refresh token must be rejected, got \(reuse.status).")

        let revoked = try await call("GET", "api/v1/auth/me", baseURL: baseURL, token: first.access)
        XCTAssertEqual(revoked.status, 401, "A reused refresh token must revoke the session, got \(revoked.status).")

        let login = try await call(
            "POST",
            "api/v1/auth/login",
            baseURL: baseURL,
            body: ["email": email, "password": password]
        )
        try rejectIfRateLimited(login, "login")
        XCTAssertEqual(login.status, 200, "Login returned \(login.status): \(login.text)")
        let session = try tokens(login)

        let logout = try await call("POST", "api/v1/auth/logout", baseURL: baseURL, token: session.access)
        XCTAssertEqual(logout.status, 204, "Logout returned \(logout.status): \(logout.text)")

        let afterLogout = try await call("GET", "api/v1/auth/me", baseURL: baseURL, token: session.access)
        XCTAssertEqual(afterLogout.status, 401, "Logout must revoke the access token, got \(afterLogout.status).")

        let loginAgain = try await call(
            "POST",
            "api/v1/auth/login",
            baseURL: baseURL,
            body: ["email": email, "password": password]
        )
        try rejectIfRateLimited(loginAgain, "login")
        XCTAssertEqual(loginAgain.status, 200, "Login returned \(loginAgain.status): \(loginAgain.text)")
        let finalSession = try tokens(loginAgain)

        let delete = try await call(
            "DELETE",
            "api/v1/auth/account",
            baseURL: baseURL,
            token: finalSession.access,
            body: ["password": password]
        )
        try rejectIfRateLimited(delete, "account deletion")
        XCTAssertEqual(delete.status, 204, "Account deletion returned \(delete.status): \(delete.text)")

        let afterDelete = try await call(
            "POST",
            "api/v1/auth/login",
            baseURL: baseURL,
            body: ["email": email, "password": password]
        )
        XCTAssertEqual(afterDelete.status, 401, "A deleted account must not be able to log in, got \(afterDelete.status).")
    }

    func testResetWithoutMailerIsReportedNotFaked() async throws {
        let baseURL = try await requireBackend()
        let reset = try await call(
            "POST",
            "api/v1/auth/password-reset",
            baseURL: baseURL,
            body: ["email": "nobody-\(UUID().uuidString.prefix(8))@example.com"]
        )
        try rejectIfRateLimited(reset, "password reset")
        XCTAssertTrue(
            [202, 503].contains(reset.status),
            "Password reset must answer 202 when mail is configured or 503 when it is not, got \(reset.status): \(reset.text)"
        )
    }
}
