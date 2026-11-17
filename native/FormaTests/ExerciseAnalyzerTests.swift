import CoreGraphics
import XCTest
@testable import Forma

final class ExerciseAnalyzerTests: XCTestCase {
    private let videoSize = CGSize(width: 720, height: 1280)

    private func frame(
        _ joints: [BodyJoint: CGPoint],
        confidence: Double = 0.9,
        confidences: [BodyJoint: Double] = [:],
        at timestamp: TimeInterval = 0,
        personCount: Int = 1
    ) -> PoseFrame {
        var samples: [BodyJoint: JointSample] = [:]
        for (joint, point) in joints {
            samples[joint] = JointSample(
                joint: joint,
                position: point,
                confidence: confidences[joint] ?? confidence,
                timestamp: timestamp
            )
        }
        return PoseFrame(
            timestamp: timestamp,
            joints: samples,
            bodyConfidence: confidence,
            personCount: personCount,
            videoSize: videoSize
        )
    }

    // MARK: - Squat

    private var standingSquatPose: [BodyJoint: CGPoint] {
        [
            .leftShoulder: CGPoint(x: 0.5, y: 0.8),
            .rightShoulder: CGPoint(x: 0.52, y: 0.8),
            .leftHip: CGPoint(x: 0.5, y: 0.55),
            .rightHip: CGPoint(x: 0.52, y: 0.55),
            .leftKnee: CGPoint(x: 0.5, y: 0.36),
            .leftAnkle: CGPoint(x: 0.5, y: 0.12)
        ]
    }

    private var bottomSquatPose: [BodyJoint: CGPoint] {
        [
            .leftShoulder: CGPoint(x: 0.7, y: 0.72),
            .rightShoulder: CGPoint(x: 0.72, y: 0.72),
            .leftHip: CGPoint(x: 0.5, y: 0.42),
            .rightHip: CGPoint(x: 0.52, y: 0.42),
            .leftKnee: CGPoint(x: 0.70, y: 0.35),
            .leftAnkle: CGPoint(x: 0.5, y: 0.12)
        ]
    }

    func testSquatSignalRisesWithKneeFlexion() {
        let analyzer = SquatMovementAnalyzer()
        let standing = analyzer.analyze(frame(standingSquatPose))
        let bottom = analyzer.analyze(frame(bottomSquatPose))

        XCTAssertEqual(standing.reliability, .reliable)
        XCTAssertEqual(bottom.reliability, .reliable)
        XCTAssertNotNil(standing.metrics.kneeAngle)
        XCTAssertNotNil(bottom.metrics.kneeAngle)
        XCTAssertLessThan(standing.signal ?? 1, 0.25)
        XCTAssertGreaterThan(bottom.signal ?? 0, 0.8)
        XCTAssertGreaterThan(standing.metrics.torsoAngle ?? 0, -1)
        XCTAssertGreaterThan(bottom.metrics.torsoAngle ?? 0, 10)
        XCTAssertTrue(bottom.canCountReps)
    }

    func testSquatNeedsHipKneeAndAnkle() {
        var pose = standingSquatPose
        pose.removeValue(forKey: .leftAnkle)
        let analysis = SquatMovementAnalyzer().analyze(frame(pose))

        XCTAssertEqual(analysis.reliability, .unavailable)
        XCTAssertNil(analysis.signal)
        XCTAssertFalse(analysis.canCountReps)
        XCTAssertTrue(analysis.missingJoints.contains(.leftAnkle))
        XCTAssertTrue(analysis.framingNote?.contains("ankle") == true)
    }

    func testSquatLowConfidenceIsLimitedAndDoesNotCount() {
        let analysis = SquatMovementAnalyzer().analyze(frame(standingSquatPose, confidence: 0.4))
        XCTAssertEqual(analysis.reliability, .limited)
        XCTAssertNotNil(analysis.signal)
        XCTAssertFalse(analysis.canCountReps)
    }

    func testSquatMultiplePeopleIsUnavailable() {
        let analysis = SquatMovementAnalyzer().analyze(frame(standingSquatPose, personCount: 2))
        XCTAssertEqual(analysis.reliability, .unavailable)
        XCTAssertNil(analysis.signal)
        XCTAssertTrue(analysis.framingNote?.contains("alone") == true)
    }

    func testEmptyFrameIsUnavailable() {
        let analysis = SquatMovementAnalyzer().analyze(frame([:]))
        XCTAssertEqual(analysis.reliability, .unavailable)
        XCTAssertNotNil(analysis.framingNote)
    }

    // MARK: - Push-up

    private var topPushUpPose: [BodyJoint: CGPoint] {
        [
            .leftShoulder: CGPoint(x: 0.3, y: 0.5),
            .leftElbow: CGPoint(x: 0.5, y: 0.45),
            .leftWrist: CGPoint(x: 0.7, y: 0.4),
            .leftHip: CGPoint(x: 0.5, y: 0.45),
            .leftAnkle: CGPoint(x: 0.8, y: 0.35)
        ]
    }

    private var bottomPushUpPose: [BodyJoint: CGPoint] {
        [
            .leftShoulder: CGPoint(x: 0.3, y: 0.5),
            .leftElbow: CGPoint(x: 0.55, y: 0.35),
            .leftWrist: CGPoint(x: 0.75, y: 0.5),
            .leftHip: CGPoint(x: 0.5, y: 0.45),
            .leftAnkle: CGPoint(x: 0.8, y: 0.35)
        ]
    }

    func testPushUpSignalRisesAsElbowBends() {
        let analyzer = PushUpMovementAnalyzer()
        let top = analyzer.analyze(frame(topPushUpPose))
        let bottom = analyzer.analyze(frame(bottomPushUpPose))

        XCTAssertEqual(top.reliability, .reliable)
        XCTAssertEqual(bottom.reliability, .reliable)
        XCTAssertLessThan(top.signal ?? 1, 0.25)
        XCTAssertGreaterThan(bottom.signal ?? 0, 0.8)
        XCTAssertGreaterThan(top.metrics.bodyAlignmentAngle ?? 0, 150)
        XCTAssertEqual(bottom.metrics.activeSide, .left)
    }

    func testPushUpWithoutArmJointsIsUnavailable() {
        var pose = topPushUpPose
        pose.removeValue(forKey: .leftWrist)
        let analysis = PushUpMovementAnalyzer().analyze(frame(pose))
        XCTAssertEqual(analysis.reliability, .unavailable)
        XCTAssertNil(analysis.signal)
    }

    // MARK: - Lunge

    private var lungePose: [BodyJoint: CGPoint] {
        [
            .leftShoulder: CGPoint(x: 0.5, y: 0.78),
            .rightShoulder: CGPoint(x: 0.52, y: 0.78),
            .leftHip: CGPoint(x: 0.45, y: 0.5),
            .rightHip: CGPoint(x: 0.5, y: 0.5),
            .leftKnee: CGPoint(x: 0.68, y: 0.32),
            .leftAnkle: CGPoint(x: 0.45, y: 0.15),
            .rightKnee: CGPoint(x: 0.55, y: 0.3),
            .rightAnkle: CGPoint(x: 0.62, y: 0.12)
        ]
    }

    func testLungeUsesTheMoreBentFrontKnee() {
        let analysis = LungeMovementAnalyzer().analyze(frame(lungePose))
        XCTAssertEqual(analysis.reliability, .reliable)
        XCTAssertEqual(analysis.metrics.activeSide, .left)
        XCTAssertGreaterThan(analysis.signal ?? 0, 0.5)
        XCTAssertNotNil(analysis.metrics.kneeAngle)
    }

    func testLungeWithoutBothLegsIsUnavailable() {
        var pose = lungePose
        pose.removeValue(forKey: .rightAnkle)
        let analysis = LungeMovementAnalyzer().analyze(frame(pose))
        XCTAssertEqual(analysis.reliability, .unavailable)
        XCTAssertNil(analysis.signal)
        XCTAssertTrue(analysis.framingNote?.lowercased().contains("both legs") == true)
    }

    // MARK: - Jumping jack

    private var closedJumpingJackPose: [BodyJoint: CGPoint] {
        [
            .leftShoulder: CGPoint(x: 0.4, y: 0.7),
            .rightShoulder: CGPoint(x: 0.6, y: 0.7),
            .leftWrist: CGPoint(x: 0.35, y: 0.45),
            .rightWrist: CGPoint(x: 0.65, y: 0.45),
            .leftHip: CGPoint(x: 0.45, y: 0.45),
            .rightHip: CGPoint(x: 0.55, y: 0.45),
            .leftAnkle: CGPoint(x: 0.47, y: 0.15),
            .rightAnkle: CGPoint(x: 0.53, y: 0.15)
        ]
    }

    private var openJumpingJackPose: [BodyJoint: CGPoint] {
        [
            .leftShoulder: CGPoint(x: 0.4, y: 0.7),
            .rightShoulder: CGPoint(x: 0.6, y: 0.7),
            .leftWrist: CGPoint(x: 0.35, y: 0.95),
            .rightWrist: CGPoint(x: 0.65, y: 0.95),
            .leftHip: CGPoint(x: 0.45, y: 0.45),
            .rightHip: CGPoint(x: 0.55, y: 0.45),
            .leftAnkle: CGPoint(x: 0.2, y: 0.15),
            .rightAnkle: CGPoint(x: 0.8, y: 0.15)
        ]
    }

    func testJumpingJackSignalRequiresBothArmsAndLegs() {
        let analyzer = JumpingJackMovementAnalyzer()
        let closed = analyzer.analyze(frame(closedJumpingJackPose))
        let open = analyzer.analyze(frame(openJumpingJackPose))

        XCTAssertEqual(closed.reliability, .reliable)
        XCTAssertEqual(open.reliability, .reliable)
        XCTAssertLessThan(closed.signal ?? 1, 0.1)
        XCTAssertGreaterThan(open.signal ?? 0, 0.9)
        XCTAssertGreaterThan(open.metrics.armRaiseRatio ?? 0, 0.5)
        XCTAssertGreaterThan(open.metrics.legSeparationRatio ?? 0, 1.5)
    }

    func testJumpingJackWithMissingWristIsUnavailable() {
        var pose = openJumpingJackPose
        pose.removeValue(forKey: .rightWrist)
        let analysis = JumpingJackMovementAnalyzer().analyze(frame(pose))
        XCTAssertEqual(analysis.reliability, .unavailable)
        XCTAssertTrue(analysis.missingJoints.contains(.rightWrist))
        XCTAssertTrue(analysis.framingNote?.lowercased().contains("wrist") == true)
    }

    // MARK: - Factory

    func testFactoryCoversEveryExercise() {
        for exercise in FormAnalysisExercise.allCases {
            XCTAssertEqual(ExerciseAnalyzerFactory.make(for: exercise).exercise, exercise)
        }
    }
}
