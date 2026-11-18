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
