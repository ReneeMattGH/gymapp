import Foundation

struct AuthTokens: Codable, Equatable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
}

struct APIError: LocalizedError, Equatable, Sendable {
    let status: Int
    let code: String
    let message: String

    var errorDescription: String? { message }
    var isUnauthorized: Bool { status == 401 }
    var isOffline: Bool { status == 0 }

    static let notSignedIn = APIError(
        status: 401,
        code: "not_authenticated",
        message: "Sign in with a Forma account to continue."
    )

    static func offline(_ underlying: Error) -> APIError {
        let config = AppConfig.current
        let message: String
        if config.backendUnreachableOnThisDevice {
            message = "This build points at a loopback address, which on a physical iPhone is the phone itself. Set FORMA_API_URL to your Mac's LAN address, for example http://192.168.1.20:8787."
        } else if let origin = config.apiBaseURL?.absoluteString {
            message = "The Forma backend at \(origin) could not be reached. Check that it is running, that this device is on the same network, and that the firewall allows it."
        } else {
            message = "The Forma backend could not be reached. Check that it is running and that this device can see it."
        }
        return APIError(status: 0, code: "network_unavailable", message: message)
    }
}

private struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let code: String
        let message: String
    }
    let error: Detail
}

/// Tokens live only in the keychain; this caches them for the lifetime of the process.
actor TokenStore {
    private let keychain: KeychainStore
    private let account = "auth-tokens"
    private var cached: AuthTokens?
    private var loaded = false

    init(keychain: KeychainStore = KeychainStore()) {
        self.keychain = keychain
    }

    func tokens() -> AuthTokens? {
        if !loaded {
            cached = loadFromKeychain()
            loaded = true
        }
        return cached
    }

    func save(_ tokens: AuthTokens) {
        cached = tokens
        loaded = true
        if let data = try? JSONEncoder().encode(tokens) {
            try? keychain.save(data, account: account)
        }
    }

    func clear() {
        cached = nil
        loaded = true
        try? keychain.delete(account: account)
    }

    private func loadFromKeychain() -> AuthTokens? {
        guard let data = try? keychain.read(account: account) else { return nil }
        return try? JSONDecoder().decode(AuthTokens.self, from: data)
    }
}

struct APIRequest {
    var method: String
    var path: String
    var body: Data?
    var authenticated: Bool = true
    var query: [URLQueryItem] = []
    var contentType: String?

    static func get(
        _ path: String,
        query: [URLQueryItem] = [],
        authenticated: Bool = true
    ) -> APIRequest {
        APIRequest(method: "GET", path: path, body: nil, authenticated: authenticated, query: query)
    }

    static func post<Body: Encodable>(
        _ path: String,
        body: Body,
        authenticated: Bool = true
    ) throws -> APIRequest {
        APIRequest(
            method: "POST",
            path: path,
            body: try JSONEncoder().encode(body),
            authenticated: authenticated
        )
    }

    static func post(_ path: String, authenticated: Bool = true) -> APIRequest {
        APIRequest(method: "POST", path: path, body: nil, authenticated: authenticated)
    }

    static func patch<Body: Encodable>(
        _ path: String,
        body: Body,
        authenticated: Bool = true
    ) throws -> APIRequest {
        APIRequest(
            method: "PATCH",
            path: path,
            body: try JSONEncoder().encode(body),
            authenticated: authenticated
        )
    }

    static func delete<Body: Encodable>(
        _ path: String,
        body: Body,
        authenticated: Bool = true
    ) throws -> APIRequest {
        APIRequest(
            method: "DELETE",
            path: path,
            body: try JSONEncoder().encode(body),
            authenticated: authenticated
        )
    }

    static func upload(_ path: String, data: Data, contentType: String) -> APIRequest {
        APIRequest(
            method: "POST",
            path: path,
            body: data,
            authenticated: true,
            contentType: contentType
        )
    }
}

actor APIClient {
    private let baseURL: URL
    private let session: URLSession
    let tokenStore: TokenStore
    private var refreshTask: Task<AuthTokens, Error>?
    private var tokenObserver: (@Sendable (AuthTokens?) -> Void)?

    init(baseURL: URL, session: URLSession = .shared, tokenStore: TokenStore = TokenStore()) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStore = tokenStore
    }

    func setTokenObserver(_ observer: (@Sendable (AuthTokens?) -> Void)?) {
        tokenObserver = observer
    }

    func currentTokens() async -> AuthTokens? {
        await tokenStore.tokens()
    }

    /// An access token that is safe to present now. Refreshes first when the
    /// stored one is about to expire, so a long-lived socket reconnect does not
    /// keep retrying a token the server has already rejected.
    func validAccessToken() async throws -> String {
        guard let tokens = await tokenStore.tokens() else {
            throw APIError.notSignedIn
        }
        if tokens.accessTokenExpiresAt.timeIntervalSinceNow > 30 {
            return tokens.accessToken
        }
        return try await refreshTokens().accessToken
    }

    func store(_ tokens: AuthTokens) async {
        await tokenStore.save(tokens)
        tokenObserver?(tokens)
    }

    func clearTokens() async {
        await tokenStore.clear()
        tokenObserver?(nil)
    }

    func send<T: Decodable & Sendable>(_ request: APIRequest) async throws -> T {
        try await send(request, allowRefresh: true)
    }

    func sendNoContent(_ request: APIRequest) async throws {
        if request.authenticated {
            guard let tokens = await tokenStore.tokens() else {
                throw APIError.notSignedIn
            }
            do {
                _ = try await rawPerform(request, accessToken: tokens.accessToken)
            } catch let error as APIError where error.isUnauthorized {
                let refreshed = try await refreshTokens()
                _ = try await rawPerform(request, accessToken: refreshed.accessToken)
            }
        } else {
            _ = try await rawPerform(request, accessToken: nil)
        }
    }

    private func send<T: Decodable & Sendable>(
        _ request: APIRequest,
        allowRefresh: Bool
    ) async throws -> T {
        if request.authenticated {
            guard let tokens = await tokenStore.tokens() else {
                throw APIError.notSignedIn
            }
            do {
                let (data, _) = try await rawPerform(request, accessToken: tokens.accessToken)
                return try decode(T.self, from: data)
            } catch let error as APIError where error.isUnauthorized && allowRefresh {
                let refreshed = try await refreshTokens()
                let (data, _) = try await rawPerform(request, accessToken: refreshed.accessToken)
                return try decode(T.self, from: data)
            }
        }
        let (data, _) = try await rawPerform(request, accessToken: nil)
        return try decode(T.self, from: data)
    }

    /// Rotates the refresh token. Concurrent callers share one in-flight refresh.
    func refreshTokens() async throws -> AuthTokens {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let stored = await tokenStore.tokens() else {
            throw APIError.notSignedIn
        }
        let task = Task<AuthTokens, Error> { [baseURL, session] in
            let body = try JSONEncoder().encode(["refreshToken": stored.refreshToken])
            var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/v1/auth/refresh"))
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = body
            do {
                let (data, response) = try await session.data(for: urlRequest)
                guard let http = response as? HTTPURLResponse else {
                    throw APIError(status: 0, code: "invalid_response", message: "The server returned an unreadable response.")
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw Self.decodeError(status: http.statusCode, data: data)
                }
                return try Self.decodeRefreshResponse(data)
            } catch let error as APIError {
                throw error
            } catch {
                throw APIError.offline(error)
            }
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let tokens = try await task.value
            await store(tokens)
            return tokens
        } catch {
            await clearTokens()
            throw error
        }
    }

    /// The refresh route answers `{ tokens }` with ISO-8601 dates. Decoding it
    /// with a plain `JSONDecoder` fails, clears the keychain and signs the user
    /// out on the first refresh, so the strategy here is load-bearing.
    static func decodeRefreshResponse(_ data: Data) throws -> AuthTokens {
        struct Envelope: Decodable { let tokens: AuthTokens }
        return try JSONDecoder.forma.decode(Envelope.self, from: data).tokens
    }

    private func rawPerform(
        _ request: APIRequest,
        accessToken: String?
    ) async throws -> (Data, HTTPURLResponse) {
        var urlRequest = URLRequest(url: url(for: request))
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = 20
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = request.body {
            urlRequest.setValue(request.contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.httpBody = body
        }
        if let accessToken {
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.offline(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError(status: 0, code: "invalid_response", message: "The server returned an unreadable response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw Self.decodeError(status: http.statusCode, data: data)
        }
        return (data, http)
    }

    private func url(for request: APIRequest) -> URL {
        let url = baseURL.appendingPathComponent(request.path)
        guard !request.query.isEmpty else { return url }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = request.query
        return components?.url ?? url
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.forma.decode(type, from: data)
        } catch {
            throw APIError(status: 200, code: "invalid_response", message: "The server response could not be read.")
        }
    }

    private static func decodeError(status: Int, data: Data) -> APIError {
        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            return APIError(status: status, code: envelope.error.code, message: envelope.error.message)
        }
        return APIError(status: status, code: "http_\(status)", message: "The server returned status \(status).")
    }
}
