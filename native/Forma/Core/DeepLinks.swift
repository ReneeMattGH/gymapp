import Foundation

enum AppDeepLink: Equatable {
    case today
    case startWorkout
    case workouts
    case progress
    case community
    case connectionRequests
    case messages

    /// Auth callbacks are handled before this parser runs, so only navigation
    /// links are accepted here.
    static func parse(_ url: URL) -> AppDeepLink? {
        guard url.scheme?.lowercased() == "forma" else { return nil }
        let host = (url.host ?? "").lowercased()
        let path = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }

        switch (host, path) {
        case ("today", []):
            return .today
        case ("start-workout", []):
            return .startWorkout
        case ("workouts", []), ("plan", []):
            return .workouts
        case ("progress", []):
            return .progress
        case ("community", []):
            return .community
        case ("community", ["requests"]):
            return .connectionRequests
        case ("community", ["messages"]):
            return .messages
        default:
            return nil
        }
    }
}

/// Links delivered by the Forma backend's emails. They carry a one-time token,
/// so they are handled before navigation parsing.
enum AuthDeepLink: Equatable {
    case verifyEmail(token: String)
    case resetPassword(token: String)

    static func parse(_ url: URL) -> AuthDeepLink? {
        guard url.scheme?.lowercased() == "forma" else { return nil }
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
        guard let token = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "token" })?
            .value,
            !token.isEmpty else { return nil }

        switch (host, path) {
        case ("auth", ["verify-email"]):
            return .verifyEmail(token: token)
        case ("auth", ["reset-password"]):
            return .resetPassword(token: token)
        default:
            return nil
        }
    }
}
