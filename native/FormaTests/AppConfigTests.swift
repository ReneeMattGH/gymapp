import XCTest
@testable import Forma

final class AppConfigTests: XCTestCase {
    private func config(_ raw: String, physicalDevice: Bool) -> AppConfig {
        AppConfig(
            apiBaseURL: URL(string: raw).flatMap { $0.scheme?.hasPrefix("http") == true ? $0 : nil },
            buildChannel: "test",
            isPhysicalDevice: physicalDevice
        )
    }

    func testLoopbackOriginIsFlaggedOnPhysicalDevice() {
        for origin in ["http://localhost:8787", "http://127.0.0.1:8787", "http://[::1]:8787"] {
            let device = config(origin, physicalDevice: true)
            XCTAssertTrue(device.usesLoopbackHost, "\(origin) should be loopback")
            XCTAssertTrue(device.backendUnreachableOnThisDevice, "\(origin) cannot reach the Mac from a phone")
            XCTAssertNotNil(device.configurationHint, "\(origin) should explain the misconfiguration")
        }
    }

    func testLoopbackIsValidInSimulator() {
        let simulator = config("http://localhost:8787", physicalDevice: false)
        XCTAssertFalse(simulator.backendUnreachableOnThisDevice)
        XCTAssertNil(simulator.configurationHint)
    }

    func testLANOriginNeedsNoHint() {
        let device = config("http://192.168.1.20:8787", physicalDevice: true)
        XCTAssertFalse(device.usesLoopbackHost)
        XCTAssertFalse(device.backendUnreachableOnThisDevice)
        XCTAssertNil(device.configurationHint)
    }

    func testBuildWithoutBackendHasNoHint() {
        let empty = AppConfig(apiBaseURL: nil, buildChannel: "production", isPhysicalDevice: true)
        XCTAssertFalse(empty.isBackendConfigured)
        XCTAssertNil(empty.configurationHint)
    }
}
