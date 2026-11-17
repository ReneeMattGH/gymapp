import XCTest
@testable import Forma

final class RepCountingEngineTests: XCTestCase {
    private let step: TimeInterval = 0.1

    @discardableResult
    private func feed(
        _ engine: RepCountingEngine,
        _ signals: [Double],
        confidence: Double = 0.9,
        startingAt start: TimeInterval = 0
    ) -> RepUpdate {
        var last = RepUpdate(phase: .ready, count: 0, completed: nil, rejectedIncompleteRep: false, suspended: false)
        for (index, value) in signals.enumerated() {
            last = engine.update(signal: value, confidence: confidence, timestamp: start + Double(index) * step)
        }
        return last
    }

    private func ramp(from: Double, to: Double, steps: Int) -> [Double] {
        guard steps > 0 else { return [] }
        return (0...steps).map { from + (to - from) * Double($0) / Double(steps) }
    }

    private func completeRepSignals() -> [Double] {
        Array(repeating: 0.05, count: 6)
            + ramp(from: 0.05, to: 0.9, steps: 8)
            + Array(repeating: 0.9, count: 4)
            + ramp(from: 0.9, to: 0.05, steps: 8)
            + Array(repeating: 0.05, count: 5)
    }

    // MARK: - Complete and incomplete cycles

    func testCountsOneCompleteCycle() {
        let engine = RepCountingEngine()
        var boundary: CompletedRepBoundary?
        var rejected = false
        for (index, signal) in completeRepSignals().enumerated() {
            let update = engine.update(signal: signal, confidence: 0.9, timestamp: Double(index) * step)
            if let completed = update.completed { boundary = completed }
            rejected = rejected || update.rejectedIncompleteRep
        }

        XCTAssertEqual(engine.count, 1)
        XCTAssertFalse(rejected)
        guard let completed = boundary else {
            XCTFail("Expected one completed rep boundary")
            return
        }
        XCTAssertEqual(completed.index, 1)
        XCTAssertGreaterThanOrEqual(completed.completedAt - completed.startedAt, 0.9)
        XCTAssertEqual(completed.maximumSignal, 0.9, accuracy: 0.0001)
    }

    func testCountsTwoFullCycles() {
        let engine = RepCountingEngine()
        feed(engine, completeRepSignals() + completeRepSignals())
        XCTAssertEqual(engine.count, 2)
    }

    func testPartialMovementIsRejectedAndNotCounted() {
        let engine = RepCountingEngine()
        let signals = Array(repeating: 0.05, count: 6)
            + ramp(from: 0.05, to: 0.5, steps: 5)
            + ramp(from: 0.5, to: 0.05, steps: 5)
            + Array(repeating: 0.05, count: 3)

        var rejected = false
        var last = RepUpdate(phase: .ready, count: 0, completed: nil, rejectedIncompleteRep: false, suspended: false)
        for (index, signal) in signals.enumerated() {
            last = engine.update(signal: signal, confidence: 0.9, timestamp: Double(index) * step)
            rejected = rejected || last.rejectedIncompleteRep
        }

        XCTAssertTrue(rejected)
        XCTAssertEqual(engine.count, 0)
        XCTAssertEqual(engine.phase, .ready)
    }

    func testMovementThatReturnsTooQuicklyIsRejected() {
        let engine = RepCountingEngine()
        let signals = Array(repeating: 0.05, count: 6)
            + [0.95, 0.95, 0.5, 0.05, 0.05]

        var rejected = false
        for (index, signal) in signals.enumerated() {
            let update = engine.update(signal: signal, confidence: 0.9, timestamp: Double(index) * step)
            rejected = rejected || update.rejectedIncompleteRep
        }

        XCTAssertTrue(rejected)
        XCTAssertEqual(engine.count, 0)
    }

    func testMovementThatNeverReachesBottomIsRejected() {
        let engine = RepCountingEngine()
        let signals = Array(repeating: 0.05, count: 6)
            + ramp(from: 0.05, to: 0.6, steps: 6)
            + ramp(from: 0.6, to: 0.05, steps: 6)

        var rejected = false
        for (index, signal) in signals.enumerated() {
            let update = engine.update(signal: signal, confidence: 0.9, timestamp: Double(index) * step)
            rejected = rejected || update.rejectedIncompleteRep
        }

        XCTAssertTrue(rejected)
        XCTAssertEqual(engine.count, 0)
    }

    func testRepThatDoesNotHoldBottomLongEnoughIsRejected() {
        var configuration = RepCountingConfiguration()
        configuration.minimumBottomHold = 0.3
        let engine = RepCountingEngine(configuration: configuration)
        let signals = Array(repeating: 0.05, count: 6)
            + ramp(from: 0.05, to: 0.8, steps: 8)
            + [0.5]
            + ramp(from: 0.5, to: 0.05, steps: 5)
            + Array(repeating: 0.05, count: 3)

        for (index, signal) in signals.enumerated() {
            _ = engine.update(signal: signal, confidence: 0.9, timestamp: Double(index) * step)
        }
        XCTAssertEqual(engine.count, 0)
    }

    // MARK: - Duplicate prevention and cooldown

    func testSmallTopOfRangeNoiseDoesNotCreateExtraReps() {
        let engine = RepCountingEngine()
        feed(engine, completeRepSignals())
        XCTAssertEqual(engine.count, 1)

        let noise = Array(repeating: 0.05, count: 4)
            + [0.24, 0.05, 0.22, 0.05, 0.25, 0.05]
            + Array(repeating: 0.05, count: 4)
        feed(engine, noise, startingAt: 4)
        XCTAssertEqual(engine.count, 1)
    }

    func testSecondRepDuringCooldownIsIgnored() {
        var configuration = RepCountingConfiguration()
        configuration.minimumTimeBetweenReps = 2.5
        let engine = RepCountingEngine(configuration: configuration)

        feed(engine, completeRepSignals())
        XCTAssertEqual(engine.count, 1)

        // The next cycle begins while the engine is still cooling down.
        feed(engine, completeRepSignals(), startingAt: 3.3)
        XCTAssertEqual(engine.count, 1)
    }

    func testUnsettledStartDoesNotCount() {
        let engine = RepCountingEngine()
        // Starts already mid-movement without a settled top position.
        let signals = [0.5, 0.7, 0.9, 0.9, 0.9, 0.7, 0.4, 0.1, 0.05, 0.05]
        feed(engine, signals)
        XCTAssertEqual(engine.count, 0)
    }

    // MARK: - Reliability

    func testLowConfidenceSuspendsAnInFlightRep() {
        let engine = RepCountingEngine()
        let signals = Array(repeating: 0.05, count: 6) + ramp(from: 0.05, to: 0.9, steps: 8)

        for (index, signal) in signals.enumerated() {
            _ = engine.update(signal: signal, confidence: 0.9, timestamp: Double(index) * step)
        }
        XCTAssertEqual(engine.phase, .bottom)

        let update = engine.update(signal: 0.9, confidence: 0.2, timestamp: 2)
        XCTAssertTrue(update.suspended)
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertEqual(engine.count, 0)

        // Once confidence returns, movement must settle again before counting resumes.
        _ = engine.update(signal: 0.05, confidence: 0.9, timestamp: 2.1)
        XCTAssertEqual(engine.phase, .ready)
        XCTAssertEqual(engine.count, 0)
    }

    func testNilSignalSuspendsWithoutChangingCount() {
        let engine = RepCountingEngine()
        let update = engine.update(signal: nil, confidence: 0.9, timestamp: 0)
        XCTAssertTrue(update.suspended)
        XCTAssertEqual(engine.count, 0)
    }

    func testOutOfOrderTimestampsAreIgnored() {
        let engine = RepCountingEngine()
        _ = engine.update(signal: 0.05, confidence: 0.9, timestamp: 1)
        let update = engine.update(signal: 0.05, confidence: 0.9, timestamp: 0.5)
        XCTAssertEqual(update.count, 0)
        XCTAssertFalse(update.suspended)
    }

    func testResetCanClearCount() {
        let engine = RepCountingEngine()
        feed(engine, completeRepSignals())
        XCTAssertEqual(engine.count, 1)

        engine.reset(keepingCount: true)
        XCTAssertEqual(engine.count, 1)

        engine.reset(keepingCount: false)
        XCTAssertEqual(engine.count, 0)
        XCTAssertNil(engine.lastCompletedRep)
        XCTAssertEqual(engine.phase, .ready)
    }
}
