import Foundation

struct AppConfig: Sendable {
    /// The Forma backend origin. Empty in builds that were not pointed at a server.
    let apiBaseURL: URL?
    let buildChannel: String
    /// False inside the Simulator, where loopback reaches the Mac that hosts it.
    let isPhysicalDevice: Bool

    init(apiBaseURL: URL?, buildChannel: String, isPhysicalDevice: Bool) {
        self.apiBaseURL = apiBaseURL
        self.buildChannel = buildChannel
        self.isPhysicalDevice = isPhysicalDevice
    }

    static let current: AppConfig = {
        let info = Bundle.main.infoDictionary ?? [:]
        // The launch environment wins so a device build can be pointed at a
        // LAN address from the Xcode scheme without rebuilding the target.
        let override = ProcessInfo.processInfo.environment["FORMA_API_URL"]
        let raw = (override ?? info["FORMA_API_URL"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let channel = (info["FormaBuildChannel"] as? String ?? "production")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let url = raw.isEmpty ? nil : URL(string: raw).flatMap {
            $0.scheme?.hasPrefix("http") == true ? $0 : nil
        }
        #if targetEnvironment(simulator)
        let physicalDevice = false
        #else
        let physicalDevice = true
        #endif
        return AppConfig(apiBaseURL: url, buildChannel: channel, isPhysicalDevice: physicalDevice)
    }()

    var isBackendConfigured: Bool { apiBaseURL != nil }

    var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    var usesLoopbackHost: Bool {
        guard let host = apiBaseURL?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    /// A loopback address points at the phone itself on a real device, so no
    /// request can ever leave it. This is the most common reason a device build
    /// reports that registration cannot reach the backend.
    var backendUnreachableOnThisDevice: Bool {
        isBackendConfigured && isPhysicalDevice && usesLoopbackHost
    }

    /// Copy an in-app screen can show when the build configuration, not the
    /// network, is the problem.
    var configurationHint: String? {
        guard backendUnreachableOnThisDevice else { return nil }
        let origin = apiBaseURL?.absoluteString ?? "localhost"
        return "This build points at \(origin), which on a physical iPhone means the phone itself, so sign-in and registration can never reach a server. Point FORMA_API_URL at a reachable backend: your Mac's LAN address while developing (for example http://192.168.1.20:8787), or your deployed HTTPS API in production."
    }
}
