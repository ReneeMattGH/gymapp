import Foundation

struct AppConfig: Sendable {
    let supabaseURL: URL?
    let supabaseAnonKey: String
    let buildChannel: String

    static let current: AppConfig = {
        let info = Bundle.main.infoDictionary ?? [:]
        let urlString = (info["SUPABASE_URL"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (info["SUPABASE_ANON_KEY"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let channel = (info["FormaBuildChannel"] as? String ?? "production").trimmingCharacters(in: .whitespacesAndNewlines)
        return AppConfig(
            supabaseURL: URL(string: urlString),
            supabaseAnonKey: key,
            buildChannel: channel
        )
    }()

    var isBackendConfigured: Bool {
        guard let supabaseURL, supabaseURL.scheme?.hasPrefix("http") == true else { return false }
        return !supabaseAnonKey.isEmpty
    }

    var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Demo data is only ever available in a debug build and only when the user
    /// explicitly chooses it on the setup screen.
    var allowsPreviewData: Bool { isDebugBuild }
}
