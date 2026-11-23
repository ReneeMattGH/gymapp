import Foundation

struct AccountUser: Codable, Equatable, Sendable {
    let id: String
    let email: String
    let displayName: String?
    let emailVerified: Bool
}

struct AccountRegistration: Sendable {
    let user: AccountUser
    /// Whether the backend actually handed the confirmation email to its mail
    /// service, so the UI can say "check your inbox" without guessing.
    let verificationEmailSent: Bool
}

private struct AuthEnvelope: Decodable {
    let user: AccountUser
    let tokens: AuthTokens
    let emailVerificationSent: Bool?
}

private struct UserEnvelope: Decodable {
    let user: AccountUser
}

private struct SentEnvelope: Decodable {
    let sent: Bool
}

/// The remote account on the Forma backend. It is deliberately separate from the
/// on-device training profile: signing in never moves or rewrites local data.
actor AccountService: AuthProviding {
    private let client: APIClient
    private var cachedUser: AccountUser?
    private var subscribers: [UUID: AsyncStream<AppUser?>.Continuation] = [:]

    init(client: APIClient) {
        self.client = client
        Task { [weak self] in await self?.installTokenObserver() }
    }

    // MARK: - AuthProviding

    func currentUser() async -> AppUser? {
        await currentAccount().map(appUser)
    }

    func currentAccount() async -> AccountUser? {
        guard await client.currentTokens() != nil else {
            cachedUser = nil
            return nil
        }
        if let cachedUser {
            return cachedUser
        }
        do {
            let response: UserEnvelope = try await client.send(.get("api/v1/auth/me"))
            cachedUser = response.user
            return response.user
        } catch let error as APIError where error.isUnauthorized {
            await client.clearTokens()
            cachedUser = nil
            return nil
        } catch {
            return nil
        }
    }

    nonisolated func authChanges() -> AsyncStream<AppUser?> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addSubscriber(id: id, continuation: continuation) }
        }
    }

    func signIn(email: String, password: String) async throws {
        let request = try APIRequest.post(
            "api/v1/auth/login",
            body: ["email": email, "password": password],
            authenticated: false
        )
        let response: AuthEnvelope = try await client.send(request)
        await adopt(response)
    }

    func signUp(name: String, email: String, password: String) async throws {
        _ = try await register(name: name, email: email, password: password)
    }

    func register(name: String, email: String, password: String) async throws -> AccountRegistration {
        let request = try APIRequest.post(
            "api/v1/auth/register",
            body: ["email": email, "password": password, "displayName": name],
            authenticated: false
        )
        let response: AuthEnvelope = try await client.send(request)
        await adopt(response)
        return AccountRegistration(
            user: response.user,
            verificationEmailSent: response.emailVerificationSent ?? false
        )
    }

    func signOut() async throws {
        try? await client.sendNoContent(.post("api/v1/auth/logout"))
        await client.clearTokens()
        cachedUser = nil
        broadcast(nil)
    }

    func resetPassword(email: String) async throws {
        let request = try APIRequest.post(
            "api/v1/auth/password-reset",
            body: ["email": email],
            authenticated: false
        )
        try await client.sendNoContent(request)
    }

    func changePassword(current: String, new: String) async throws {
        let request = try APIRequest.post(
            "api/v1/auth/change-password",
            body: ["currentPassword": current, "newPassword": new]
        )
        try await client.sendNoContent(request)
    }

    func deleteAccount(password: String) async throws {
        let request = try APIRequest.delete(
            "api/v1/auth/account",
            body: ["password": password]
        )
        try await client.sendNoContent(request)
        await client.clearTokens()
        cachedUser = nil
        broadcast(nil)
    }

    // MARK: - Email confirmation

    func verifyEmail(token: String) async throws {
        let request = try APIRequest.post(
            "api/v1/auth/verify-email",
            body: ["token": token],
            authenticated: false
        )
        try await client.sendNoContent(request)
        if let user = cachedUser {
            let updated = AccountUser(
                id: user.id,
                email: user.email,
                displayName: user.displayName,
                emailVerified: true
            )
            cachedUser = updated
            broadcast(appUser(updated))
        }
    }

    func resendVerification() async throws -> Bool {
        let response: SentEnvelope = try await client.send(.post("api/v1/auth/resend-verification"))
        return response.sent
    }

    // MARK: - Password reset completion

    func confirmPasswordReset(token: String, password: String) async throws {
        let request = try APIRequest.post(
            "api/v1/auth/password-reset/confirm",
            body: ["token": token, "password": password],
            authenticated: false
        )
        try await client.sendNoContent(request)
        await client.clearTokens()
        cachedUser = nil
        broadcast(nil)
    }

    // MARK: - Helpers

    private func adopt(_ response: AuthEnvelope) async {
        await client.store(response.tokens)
        cachedUser = response.user
        broadcast(appUser(response.user))
    }

    private func installTokenObserver() async {
        await client.setTokenObserver { [weak self] tokens in
            guard tokens == nil else { return }
            Task { await self?.signedOutRemotely() }
        }
    }

    private func signedOutRemotely() async {
        cachedUser = nil
        broadcast(nil)
    }

    private func addSubscriber(id: UUID, continuation: AsyncStream<AppUser?>.Continuation) {
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        if let cachedUser {
            continuation.yield(appUser(cachedUser))
        }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func broadcast(_ user: AppUser?) {
        for continuation in subscribers.values {
            continuation.yield(user)
        }
    }

    private func appUser(_ account: AccountUser) -> AppUser {
        AppUser(id: account.id, email: account.email, emailVerified: account.emailVerified)
    }
}
