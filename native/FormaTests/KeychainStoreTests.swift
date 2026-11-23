import XCTest
@testable import Forma

final class KeychainStoreTests: XCTestCase {
    private let store = KeychainStore(service: "coach.forma.tests")

    func testRoundTripUpdateAndDelete() throws {
        let account = "tokens-\(UUID().uuidString)"
        defer { try? store.delete(account: account) }

        XCTAssertNil(try store.read(account: account), "A fresh account must not hold anything")

        try store.save(Data("first".utf8), account: account)
        XCTAssertEqual(try store.read(account: account), Data("first".utf8))

        // A second save must update in place rather than fail with a duplicate item.
        try store.save(Data("second".utf8), account: account)
        XCTAssertEqual(try store.read(account: account), Data("second".utf8))

        try store.delete(account: account)
        XCTAssertNil(try store.read(account: account))
    }
}
