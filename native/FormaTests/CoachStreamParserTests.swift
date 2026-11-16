import XCTest
@testable import Forma

final class CoachStreamParserTests: XCTestCase {
    private func event(_ line: String) -> CoachStreamEvent? {
        var parser = CoachStreamParser()
        guard case .event(let event) = parser.consume(line: line) else { return nil }
        return event
    }

    func testMetaParsesSourcesCardsAndIntent() throws {
        let line = #"data: {"type":"meta","intent":"app_data","modelLabel":"fast","unverified":false,"sources":[{"id":"squat","name":"Goblet squat","category":"strength","kind":"exercise"},{"id":"knowledge-1","name":"Progressive overload","category":"knowledge","kind":"knowledge","url":"https://example.org/guide","publishedAt":"2026-01-02"}],"cards":[{"type":"exercise","id":"squat","name":"Goblet squat","category":"strength","primaryMuscles":["quads"],"equipment":["dumbbells"],"difficulty":"beginner"},{"type":"plan","id":"plan-1","name":"Base plan","goal":"strength","daysPerWeek":3,"sessionMinutes":45,"trainingDays":3,"createdAt":"2026-02-01T10:00:00Z"}]}"#
        let parsed = try XCTUnwrap(event(line))
        XCTAssertEqual(parsed.type, "meta")
        XCTAssertEqual(parsed.intent, "app_data")
        XCTAssertEqual(parsed.sources?.count, 2)
        XCTAssertEqual(parsed.sources?.last?.kind, "knowledge")
        XCTAssertEqual(parsed.sources?.last?.publishedAt, "2026-01-02")
        XCTAssertEqual(parsed.cards?.count, 2)
        XCTAssertEqual(parsed.cards?.first?.id, "exercise-squat")
        XCTAssertEqual(parsed.cards?.last?.id, "plan-plan-1")
    }

    func testRevisionCarriesReplacementText() throws {
        let parsed = try XCTUnwrap(event(#"data: {"type":"revision","text":"Corrected answer."}"#))
        XCTAssertEqual(parsed.type, "revision")
        XCTAssertEqual(parsed.text, "Corrected answer.")
    }

    func testDoneCarriesPersistenceAndVerificationFields() throws {
        let parsed = try XCTUnwrap(
            event(#"data: {"type":"done","messageId":"m-1","createdAt":"2026-11-16T10:00:00Z","unverified":true,"intent":"nutrition"}"#)
        )
        XCTAssertEqual(parsed.messageId, "m-1")
        XCTAssertEqual(parsed.unverified, true)
        XCTAssertEqual(parsed.intent, "nutrition")
        XCTAssertNotNil(parsed.createdAt.flatMap(FormaDate.parse))
    }

    func testDoneSentinelAndBlankLinesAreIgnoredSeparately() {
        var parser = CoachStreamParser()
        if case .done = parser.consume(line: "data: [DONE]") {
            // expected
        } else {
            XCTFail("Expected the done sentinel")
        }
        if case .ignore = parser.consume(line: "data:   ") {
            // expected
        } else {
            XCTFail("Expected an empty data line to be ignored")
        }
        if case .ignore = parser.consume(line: "event: message") {
            // expected
        } else {
            XCTFail("Expected a non-data line to be ignored")
        }
    }

    func testUnknownCardTypeDoesNotCrashTheStreamParser() {
        var parser = CoachStreamParser()
        let line = #"data: {"type":"meta","cards":[{"type":"chart","id":"x"}]}"#
        if case .ignore = parser.consume(line: line) {
            // expected: the whole malformed event is skipped
        } else {
            XCTFail("Expected an event with an unknown card type to be ignored")
        }
    }

    func testLegacySourceWithoutKindDefaultsToExercise() throws {
        let parsed = try XCTUnwrap(
            event(#"data: {"type":"meta","sources":[{"id":"push-up","name":"Push-up","category":"strength"}]}"#)
        )
        XCTAssertEqual(parsed.sources?.first?.kind, "exercise")
        XCTAssertNil(parsed.sources?.first?.url)
    }

    func testCardsRoundTripThroughPersistedMetadata() throws {
        let json = #"[{"type":"exercise","id":"row","name":"Row","category":"strength","primaryMuscles":["back"],"equipment":["dumbbells"],"difficulty":"intermediate"},{"type":"plan","id":"p1","name":"Plan","goal":"strength","daysPerWeek":3,"sessionMinutes":45,"trainingDays":3,"createdAt":"2026-01-01T00:00:00Z"}]"#
        let cards = try JSONDecoder().decode([CoachCard].self, from: Data(json.utf8))
        let encoded = try JSONEncoder().encode(cards)
        let decoded = try JSONDecoder().decode([CoachCard].self, from: encoded)
        XCTAssertEqual(cards, decoded)
        guard case .plan(let plan) = decoded[1] else {
            return XCTFail("Expected a plan card")
        }
        XCTAssertEqual(plan.trainingDays, 3)
        XCTAssertEqual(plan.goal, "strength")
    }

    func testCoachSourceDefensiveDecoding() throws {
        let source = try JSONDecoder().decode(
            CoachSource.self,
            from: Data(#"{"id":"w1","name":"Study","category":"web","url":"https://example.org","publishedAt":"2026-03-01"}"#.utf8)
        )
        XCTAssertTrue(source.isWeb)
        XCTAssertEqual(source.publishedAt, "2026-03-01")
        XCTAssertNil(source.publisher)
    }
}
