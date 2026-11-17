import XCTest
@testable import Forma

final class FormFeedbackEngineTests: XCTestCase {
    private func analysis(
        exercise: FormAnalysisExercise = .squat,
        reliability: AnalysisReliability = .reliable,
        missing: [BodyJoint] = [],
        note: String? = nil,
        timestamp: TimeInterval = 0
    ) -> MovementAnalysis {
        MovementAnalysis(
            exercise: exercise,
            timestamp: timestamp,
            signal: 0.4,
            signalConfidence: 0.8,
            reliability: reliability,
            metrics: MovementMetrics(),
            missingJoints: missing,
            framingNote: note
        )
    }

    private func rep(
        exercise: FormAnalysisExercise,
        metrics: RepMetricSummary,
        coverage: Double = 1,
        hadTrackingLoss: Bool = false
    ) -> RepObservation {
        RepObservation(
            exercise: exercise,
            boundary: CompletedRepBoundary(
                index: 1,
                startedAt: 0,
                bottomedAt: 1,
                completedAt: 2,
                minimumSignal: 0.05,
                maximumSignal: 0.9
            ),
            metrics: metrics,
            averageConfidence: 0.8,
            totalFrameCount: 20,
            reliableFrameCount: Int(20 * coverage),
            measuredJoints: [],
            hadTrackingLoss: hadTrackingLoss
        )
    }

    // MARK: - Tracking

    func testReliableTrackingIsAnnouncedOncePerStateChange() {
        let engine = FormFeedbackEngine()
        let first = engine.trackingObservation(for: analysis(timestamp: 0))
        XCTAssertEqual(first?.status, .reliable)
        XCTAssertTrue(first?.text.contains("Full body visible") == true)

        XCTAssertNil(engine.trackingObservation(for: analysis(timestamp: 1)))

        let limited = engine.trackingObservation(for: analysis(reliability: .limited, missing: [.leftKnee], note: "Your left knee is outside the frame.", timestamp: 2))
        XCTAssertEqual(limited?.status, .limited)
        XCTAssertEqual(limited?.text, "Your left knee is outside the frame.")

        let recovered = engine.trackingObservation(for: analysis(timestamp: 3))
        XCTAssertEqual(recovered?.status, .reliable)
    }

    func testUnavailableTrackingExplainsWhy() {
        let engine = FormFeedbackEngine()
        let ambiguous = engine.trackingObservation(
            for: analysis(reliability: .unavailable, note: "More than one person is visible. Make sure you are alone in the frame.")
        )
        XCTAssertEqual(ambiguous?.status, .unavailable)
        XCTAssertTrue(ambiguous?.text.contains("alone") == true)
        XCTAssertEqual(ambiguous?.kind, .tracking)
    }

    func testMissingJointMessageFallsBackWhenNoNoteProvided() {
        let engine = FormFeedbackEngine()
        let observation = engine.trackingObservation(
            for: analysis(reliability: .limited, missing: [.leftAnkle])
        )
        XCTAssertEqual(observation?.status, .limited)
        XCTAssertNotNil(observation?.text)
        XCTAssertTrue(observation?.text.lowercased().contains("body") == true)
    }

    // MARK: - Rep observations

    func testSquatRepReportsMeasuredAngleAndTorsoChange() {
        let engine = FormFeedbackEngine()
        var metrics = RepMetricSummary()
        metrics.minimumKneeAngle = 101
        metrics.minimumTorsoAngle = 8
        metrics.maximumTorsoAngle = 31

        let observations = engine.observations(for: rep(exercise: .squat, metrics: metrics))
        XCTAssertEqual(observations.count, 1)
        let observation = observations[0]
        XCTAssertEqual(observation.status, .reliable)
        XCTAssertTrue(observation.text.contains("Rep 1"))
        XCTAssertTrue(observation.text.contains("101°"))
        XCTAssertTrue(observation.text.contains("23°"))
        XCTAssertNotNil(observation.limitation)
        XCTAssertTrue(observation.joints.contains(.leftKnee))
    }

    func testSmallTorsoChangeIsNotReportedAsMeaningful() {
        let engine = FormFeedbackEngine()
        var metrics = RepMetricSummary()
        metrics.minimumKneeAngle = 110
        metrics.minimumTorsoAngle = 5
        metrics.maximumTorsoAngle = 12

        let observations = engine.observations(for: rep(exercise: .squat, metrics: metrics))
        XCTAssertEqual(observations.count, 1)
        XCTAssertFalse(observations[0].text.contains("torso angle changed"))
    }

    func testPushUpRepReportsElbowAndAlignment() {
        let engine = FormFeedbackEngine()
        var metrics = RepMetricSummary()
        metrics.minimumElbowAngle = 88
        metrics.minimumBodyAlignmentAngle = 162
        metrics.maximumBodyAlignmentAngle = 178

        let observations = engine.observations(for: rep(exercise: .pushUp, metrics: metrics))
        XCTAssertEqual(observations.count, 1)
        XCTAssertTrue(observations[0].text.contains("88°"))
        XCTAssertTrue(observations[0].text.contains("162°"))
    }

    func testLungeRepReportsFrontKnee() {
        let engine = FormFeedbackEngine()
        var metrics = RepMetricSummary()
        metrics.minimumKneeAngle = 96
        let observations = engine.observations(for: rep(exercise: .lunge, metrics: metrics))
        XCTAssertEqual(observations[0].status, .reliable)
        XCTAssertTrue(observations[0].text.contains("96°"))
    }

    func testJumpingJackRepReportsArmAndLegRange() {
        let engine = FormFeedbackEngine()
        var metrics = RepMetricSummary()
        metrics.maximumArmRaiseRatio = 0.6
        metrics.maximumLegSeparationRatio = 1.9

        let observations = engine.observations(for: rep(exercise: .jumpingJack, metrics: metrics))
        XCTAssertEqual(observations[0].status, .reliable)
        XCTAssertTrue(observations[0].text.contains("0.6"))
        XCTAssertTrue(observations[0].text.contains("1.9"))
        XCTAssertTrue(observations[0].limitation?.lowercased().contains("camera distance and angle") == true)
        XCTAssertEqual(observations[0].measurements["maximumArmRaiseRatio"], 0.6)
        XCTAssertEqual(observations[0].measurements["maximumLegSeparationRatio"], 1.9)
        XCTAssertTrue(observations[0].measurementSummary?.contains("arm rise") == true)
    }

    func testRepWithoutMeasurementsIsMarkedUnavailable() {
        let engine = FormFeedbackEngine()
        let observations = engine.observations(for: rep(exercise: .squat, metrics: RepMetricSummary()))
        XCTAssertEqual(observations.count, 1)
        XCTAssertEqual(observations[0].status, .unavailable)
        XCTAssertTrue(observations[0].text.contains("not visible"))
        XCTAssertFalse(observations[0].text.contains("°"))
    }

    func testInterruptedTrackingProducesLimitedCoverageNote() {
        let engine = FormFeedbackEngine()
        var metrics = RepMetricSummary()
        metrics.minimumKneeAngle = 100
        let observations = engine.observations(for: rep(exercise: .squat, metrics: metrics, coverage: 0.4, hadTrackingLoss: true))

        XCTAssertEqual(observations.count, 2)
        XCTAssertTrue(observations.contains { $0.status == .limited && $0.text.contains("interrupted") })
        XCTAssertTrue(observations.contains { $0.limitation?.contains("40%") == true })
    }

    func testObservationsUseMeasuredLanguageOnly() {
        let engine = FormFeedbackEngine()
        var metrics = RepMetricSummary()
        metrics.minimumKneeAngle = 100
        metrics.maximumTorsoAngle = 40
        metrics.minimumTorsoAngle = 10

        let texts = FormAnalysisExercise.allCases
            .flatMap { engine.observations(for: rep(exercise: $0, metrics: metrics, coverage: 0.3)) }
            .map { $0.text.lowercased() + " " + ($0.limitation ?? "").lowercased() }
            + [engine.trackingObservation(for: analysis())!.text.lowercased()]

        for text in texts {
            for banned in ["dangerous", "injury", "injured", "diagnos", "score", "out of 100", "perfect form", "guarantee"] {
                XCTAssertFalse(text.contains(banned), "Unexpected claim: \(text)")
            }
        }
    }

    func testUnavailableMessageIsExact() {
        XCTAssertEqual(
            FormAnalysisText.repCountingUnavailable,
            "Rep counting unavailable — movement could not be tracked reliably."
        )
    }

    func testPausedMessageIsExact() {
        XCTAssertEqual(
            FormAnalysisText.repCountingPaused,
            "Rep counting paused — body movement cannot be tracked reliably."
        )
    }
}
