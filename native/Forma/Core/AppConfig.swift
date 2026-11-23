import Foundation

struct AppConfig: Sendable {
    /// The Forma backend origin. Empty in builds that were not pointed at a server.
    let apiBaseURL: URL?
    let buildChannel: String

    static let current: AppConfig = {
        let info = Bundle.main.infoDictionary ?? [:]
        let raw = (info["FORMA_API_URL"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let channel = (info["FormaBuildChannel"] as? String ?? "production")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = URL(string: raw).flatMap { $0.scheme?.hasPrefix("http") == true ? $0 : nil }
        return AppConfig(apiBaseURL: url, buildChannel: channel)
    }()

    var isBackendConfigured: Bool { apiBaseURL != nil }

    var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
