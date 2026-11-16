import XCTest
@testable import Forma

final class SafetyValidatorTests: XCTestCase {
    func testEmptyReplyIsBlocked() {
        XCTAssertNotNil(AIResponseValidator.problem(with: "   \n "))
    }

    func testOverlongReplyIsBlocked() {
        let long = String(repeating: "a", count: 12_001)
        XCTAssertNotNil(AIResponseValidator.problem(with: long))
    }

    func testPainInstructionIsBlocked() {
        XCTAssertNotNil(AIResponseValidator.problem(with: "Keep going and push through the pain."))
    }

    func testNegatedInstructionIsAllowed() {
        XCTAssertNil(AIResponseValidator.problem(with: "Do not push through the pain; stop and rest."))
    }

    func testDiagnosisClaimIsBlocked() {
        XCTAssertNotNil(AIResponseValidator.problem(with: "You definitely have a torn meniscus."))
    }

    func testOrdinaryCoachingReplyPasses() {
        let reply = """
        Warm up with five minutes of easy movement.
        Keep the first two sets around RPE 6 and stop if anything pinches.
        """
        XCTAssertNil(AIResponseValidator.problem(with: reply))
    }
}
