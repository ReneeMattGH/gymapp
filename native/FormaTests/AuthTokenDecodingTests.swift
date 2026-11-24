import XCTest
@testable import Forma

final class AuthTokenDecodingTests: XCTestCase {
    /// Shape and date format produced by the backend's refresh route.
    private let payload = """
    {"tokens":{"accessToken":"a1b2c3","accessTokenExpiresAt":"2026-11-24T08:30:00.000Z",
    "refreshToken":"d4e5f6","refreshTokenExpiresAt":"2026-12-24T08:00:00.000Z"}}
    """

    func testRefreshEnvelopeDecodesISO8601Dates() throws {
        let tokens = try APIClient.decodeRefreshResponse(Data(payload.utf8))
        XCTAssertEqual(tokens.accessToken, "a1b2c3")
        XCTAssertEqual(tokens.refreshToken, "d4e5f6")

        let expected = ISO8601DateFormatter()
        expected.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        XCTAssertEqual(tokens.accessTokenExpiresAt, expected.date(from: "2026-11-24T08:30:00.000Z"))
        XCTAssertEqual(tokens.refreshTokenExpiresAt, expected.date(from: "2026-12-24T08:00:00.000Z"))
        XCTAssertGreaterThan(tokens.refreshTokenExpiresAt, tokens.accessTokenExpiresAt)
    }

    func testRefreshEnvelopeRejectsAnUnreadableBody() {
        XCTAssertThrowsError(try APIClient.decodeRefreshResponse(Data("{}".utf8)))
    }
}
