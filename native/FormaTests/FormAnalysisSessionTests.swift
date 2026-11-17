import CoreGraphics
import XCTest
@testable import Forma

final class FormAnalysisSessionTests: XCTestCase {
    // MARK: - Fixtures

    private func analysis(
        reliability: AnalysisReliability = .reliable,
        signal: Double = 0.5,
        timestamp: TimeInterval = 0
    ) -> MovementAnalysis {
        MovementAnalysis(
            exercise: .squat,
            timestamp: timestamp,
            signal: signal,
            signalConfidence: 0.8,
            reliability: reliability,
            metrics: MovementMetrics(),
            missingJoints: [],
            framingNote: nil
        )
    }

    private func observation(
        status: FeedbackStatus = .reliable,
        text: String,
        kind: ObservationKind = .tracking,
        timestamp: TimeInterval = 0
    ) -> FormObservation {
        FormObservation(
            id: "obs-\(text)-\(timestamp)",
            status: status,
            text: text,
            joints: [.leftKnee, .leftHip, .leftAnkle],
            limitation: "Single 2D view.",
            timestamp: timestamp,
            kind: kind
        )
    }

    private func summary(repCount: Int?, observations: [FormObservation] = []) -> FormAnalysisSessionSummary {
        FormAnalysisSessionSummary(
            exercise: .pushUp,
            startedAt: Date(timeIntervalSince1970: 1000),
            endedAt: Date(timeIntervalSince1970: 1065),
            duration: 65,
            repCount: repCount,
            repCountingReliable: repCount != nil,
            coverage: 0.75,
            observations: observations,
            limitations: ["Single 2D camera view.", "Not a medical assessment."],
            cameraPosition: .front
        )
    }

    // MARK: - Recorder summary

    func testSummaryWithoutReliableFramesOmitsCount() {
        let recorder = FormAnalysisSessionRecorder(exercise: .squat, cameraPosition: .front)
        for index in 0..<6 {
            recorder.record(frame: analysis(reliability: .limited, timestamp: Double(index)))
        }
        let result = recorder.summary(repCount: 0)

        XCTAssertNil(result.repCount)
        XCTAssertFalse(result.repCountingReliable)
        XCTAssertEqual(result.coverage ?? -1, 0, accuracy: 0.0001)
        XCTAssertTrue(result.limitations.contains { $0.contains("may be incomplete") })
        XCTAssertFalse(result.limitations.contains("No complete repetitions were counted in this session."))
    }

    func testSummaryWithZeroAnalyzedFramesHasNoCoverage() {
        let recorder = FormAnalysisSessionRecorder(exercise: .pushUp, cameraPosition: .back)
        let result = recorder.summary(repCount: 0)

        XCTAssertNil(result.coverage)
        XCTAssertNil(result.repCount)
        XCTAssertFalse(result.repCountingReliable)
        XCTAssertTrue(result.limitations.contains { $0.contains("not been validated on a physical device") })
    }

    func testSummaryKeepsCountButFlagsLowCoverage() {
        let recorder = FormAnalysisSessionRecorder(exercise: .squat, cameraPosition: .front)
        recorder.record(frame: analysis(reliability: .reliable))
        for index in 0..<9 {
            recorder.record(frame: analysis(reliability: .limited, timestamp: Double(index + 1)))
        }
        let result = recorder.summary(repCount: 3)

        XCTAssertEqual(result.repCount, 3)
        XCTAssertFalse(result.repCountingReliable)
        XCTAssertEqual(result.coverage ?? -1, 0.1, accuracy: 0.0001)
        XCTAssertTrue(result.limitations.first?.contains("10%") == true)
    }

    func testSummaryWithZeroCountNotesNoCompleteRepetitions() {
        let recorder = FormAnalysisSessionRecorder(exercise: .lunge, cameraPosition: .front)
        for index in 0..<4 {
            recorder.record(frame: analysis(reliability: .reliable, timestamp: Double(index)))
        }
        let result = recorder.summary(repCount: 0)

        XCTAssertEqual(result.repCount, 0)
        XCTAssertTrue(result.repCountingReliable)
        XCTAssertTrue(result.limitations.contains("No complete repetitions were counted in this session."))
    }

    func testSummaryKeepsLastSixUsableObservations() {
        let recorder = FormAnalysisSessionRecorder(exercise: .squat, cameraPosition: .front)
        for index in 0..<8 {
            recorder.record(observations: [
                observation(
                    status: index == 3 ? .unavailable : .reliable,
                    text: "Observation \(index)",
                    timestamp: Double(index)
                )
            ])
        }
        let result = recorder.summary(repCount: 1)

        XCTAssertEqual(result.observations.count, 6)
        XCTAssertFalse(result.observations.contains { $0.status == .unavailable })
        XCTAssertEqual(result.observations.first?.text, "Observation 1")
        XCTAssertEqual(result.observations.last?.text, "Observation 7")
    }

    // MARK: - Coach message

    func testCoachMessageUsesMeasuredTextOnly() {
        let measured = observation(text: "Knee angle reached about 94° at the deepest point.")
        let text = FormAnalysisCoachMessage.make(from: summary(repCount: 8, observations: [measured]))

        XCTAssertTrue(text.contains("Repetitions counted: 8"))
        XCTAssertTrue(text.contains("Knee angle reached about 94° at the deepest point."))
        XCTAssertTrue(text.contains("Limitations:"))
        XCTAssertTrue(text.contains("no images or video were sent"))
        XCTAssertTrue(text.contains("You cannot see the user"))
        XCTAssertFalse(text.contains("base64"))
        XCTAssertFalse(text.lowercased().contains("jpeg"))
        XCTAssertFalse(text.lowercased().contains("keypoints"))
    }

    func testCoachMessageNeverInvitesAnInventedCount() {
        let text = FormAnalysisCoachMessage.make(from: summary(repCount: nil))

        XCTAssertTrue(text.contains("Repetitions counted: unavailable"))
        XCTAssertTrue(text.contains("Measured observations: none reliable enough to report."))
        XCTAssertTrue(text.contains("Do not invent measurements"))
        XCTAssertFalse(text.contains("Repetitions counted: 0"))
    }

    func testCoachMessageExcludesLimitedObservations() {
        let limited = observation(status: .limited, text: "Knee angle could only be measured intermittently.")
        let text = FormAnalysisCoachMessage.make(from: summary(repCount: 2, observations: [limited]))

        XCTAssertFalse(text.contains("intermittently"))
        XCTAssertTrue(text.contains("none reliable enough to report"))
    }

    // MARK: - Preview mapping

    func testPreviewMapperAspectFillsPortraitVideo() {
        let mapper = PosePreviewMapper(
            videoSize: CGSize(width: 720, height: 1280),
            viewSize: CGSize(width: 390, height: 844)
        )

        XCTAssertEqual(mapper.scale, 844.0 / 1280.0, accuracy: 0.0001)
        XCTAssertEqual(mapper.scaledSize.width, 474.75, accuracy: 0.01)
        XCTAssertEqual(mapper.scaledSize.height, 844, accuracy: 0.01)
        XCTAssertEqual(mapper.origin.x, -42.375, accuracy: 0.01)
        XCTAssertEqual(mapper.origin.y, 0, accuracy: 0.01)

        let center = mapper.point(CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(center.x, 195, accuracy: 0.01)
        XCTAssertEqual(center.y, 422, accuracy: 0.01)

        // Vision's origin is bottom-left; the overlay's origin is top-left.
        let bottomLeft = mapper.point(CGPoint(x: 0, y: 0))
        XCTAssertEqual(bottomLeft.x, -42.375, accuracy: 0.01)
        XCTAssertEqual(bottomLeft.y, 844, accuracy: 0.01)

        let topRight = mapper.point(CGPoint(x: 1, y: 1))
        XCTAssertEqual(topRight.x, 432.375, accuracy: 0.01)
        XCTAssertEqual(topRight.y, 0, accuracy: 0.01)
    }

    func testPreviewMapperHandlesDegenerateSizes() {
        let mapper = PosePreviewMapper(videoSize: .zero, viewSize: CGSize(width: 390, height: 844))
        XCTAssertEqual(mapper.scale, 1)
        XCTAssertEqual(mapper.origin.x, 390 / 2 - 0, accuracy: 0.01)
    }
}
