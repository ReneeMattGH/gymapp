import CoreGraphics
import XCTest
@testable import Forma

final class FormAnalysisPoseTests: XCTestCase {
    // MARK: - Fixtures

    private func makeFrame(
        _ joints: [BodyJoint: (CGPoint, Double)],
        at timestamp: TimeInterval = 0,
        personCount: Int = 1,
        videoSize: CGSize = CGSize(width: 720, height: 1280)
    ) -> PoseFrame {
        var samples: [BodyJoint: JointSample] = [:]
        for (joint, value) in joints {
            samples[joint] = JointSample(
                joint: joint,
                position: value.0,
                confidence: value.1,
                timestamp: timestamp
            )
        }
        let average = samples.values.map(\.confidence).reduce(0, +) / Double(max(1, samples.count))
        return PoseFrame(
            timestamp: timestamp,
            joints: samples,
            bodyConfidence: average,
            personCount: personCount,
            videoSize: videoSize
        )
    }

    // MARK: - Joint validity

    func testLowConfidenceAndOutOfBoundsJointsAreNotUsable() {
        let low = JointSample(joint: .leftKnee, position: CGPoint(x: 0.5, y: 0.5), confidence: 0.2, timestamp: 0)
        let outside = JointSample(joint: .rightKnee, position: CGPoint(x: 1.2, y: 0.5), confidence: 0.9, timestamp: 0)
        let good = JointSample(joint: .leftHip, position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9, timestamp: 0)

        XCTAssertFalse(low.isUsable())
        XCTAssertFalse(outside.isUsable())
        XCTAssertTrue(good.isUsable())
    }

    func testPoseFrameExposesOnlyUsableJoints() {
        let frame = makeFrame([
            .leftShoulder: (CGPoint(x: 0.4, y: 0.7), 0.9),
            .rightShoulder: (CGPoint(x: 0.6, y: 0.7), 0.2),
            .leftHip: (CGPoint(x: 0.42, y: 0.45), 0.8)
        ])

        XCTAssertEqual(frame.usableJointCount, 2)
        XCTAssertNil(frame.point(.rightShoulder))
        XCTAssertEqual(frame.midpoint(.leftShoulder, .rightShoulder)?.y, nil)
        XCTAssertEqual(frame.point(.leftHip)?.x, 0.42)
    }

    func testPoseFrameFlagsAmbiguousPeopleAndWeakConfidence() {
        let reliable = makeFrame([.leftShoulder: (CGPoint(x: 0.4, y: 0.7), 0.9), .leftHip: (CGPoint(x: 0.4, y: 0.4), 0.9),
                                  .leftKnee: (CGPoint(x: 0.4, y: 0.2), 0.9), .leftAnkle: (CGPoint(x: 0.4, y: 0.05), 0.9)], personCount: 1)
        XCTAssertTrue(reliable.isReliable)

        let crowded = makeFrame([.leftShoulder: (CGPoint(x: 0.4, y: 0.7), 0.9), .leftHip: (CGPoint(x: 0.4, y: 0.4), 0.9)],
                                personCount: 2)
        XCTAssertTrue(crowded.hasAmbiguousPeople)
        XCTAssertFalse(crowded.isReliable)
    }

    // MARK: - Geometry

    func testAngleIsAspectCorrected() {
        let squareAngle = PoseGeometry.angle(
            a: CGPoint(x: 0, y: 1),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 1, y: 1),
            aspectRatio: 1
        )
        XCTAssertEqual(squareAngle ?? 0, 45, accuracy: 0.001)

        let wideAngle = PoseGeometry.angle(
            a: CGPoint(x: 0, y: 1),
            b: CGPoint(x: 0, y: 0),
            c: CGPoint(x: 1, y: 1),
            aspectRatio: 2
        )
        XCTAssertEqual(wideAngle ?? 0, 63.4349, accuracy: 0.001)
    }

    func testAngleRejectsDegenerateTriangle() {
        XCTAssertNil(PoseGeometry.angle(
            a: CGPoint(x: 0.5, y: 0.5),
            b: CGPoint(x: 0.5, y: 0.5),
            c: CGPoint(x: 0.8, y: 0.5),
            aspectRatio: 0.5625
        ))
    }

    func testVerticalAngleMeasuresLeanFromUpright() {
        let upright = PoseGeometry.verticalAngle(
            from: CGPoint(x: 0.5, y: 0.4),
            to: CGPoint(x: 0.5, y: 0.8),
            aspectRatio: 0.5625
        )
        XCTAssertEqual(upright ?? 99, 0, accuracy: 0.001)

        let leaning = PoseGeometry.verticalAngle(
            from: CGPoint(x: 0.5, y: 0.4),
            to: CGPoint(x: 0.7, y: 0.8),
            aspectRatio: 1
        )
        XCTAssertEqual(leaning ?? 0, 26.565, accuracy: 0.001)
    }

    func testProgressHandlesDescendingRangeAndClamps() {
        XCTAssertEqual(PoseGeometry.progress(value: 160, start: 160, end: 95), 0)
        XCTAssertEqual(PoseGeometry.progress(value: 95, start: 160, end: 95), 1)
        XCTAssertEqual(PoseGeometry.progress(value: 127.5, start: 160, end: 95), 0.5, accuracy: 0.001)
        XCTAssertEqual(PoseGeometry.progress(value: 200, start: 160, end: 95), 0)
        XCTAssertEqual(PoseGeometry.progress(value: 40, start: 160, end: 95), 1)
    }

    // MARK: - Smoothing

    func testSmoothingSteadiesSmallJitterButFollowsMovement() {
        let smoother = PoseSmoothingService()

        let first = smoother.smooth(makeFrame([.leftKnee: (CGPoint(x: 0.5, y: 0.5), 0.9)], at: 0))
        XCTAssertEqual(first.point(.leftKnee)?.x ?? 0, 0.5, accuracy: 0.0001)

        let jitter = smoother.smooth(makeFrame([.leftKnee: (CGPoint(x: 0.503, y: 0.5), 0.9)], at: 0.1))
        let jitterX = jitter.point(.leftKnee)?.x ?? 0
        XCTAssertGreaterThan(jitterX, 0.5)
        XCTAssertLessThan(jitterX, 0.503)

        // A clear movement uses the higher weight so the rep is not flattened.
        let move = smoother.smooth(makeFrame([.leftKnee: (CGPoint(x: 0.6, y: 0.5), 0.9)], at: 0.2))
        XCTAssertEqual(move.point(.leftKnee)?.x ?? 0, 0.5702, accuracy: 0.001)
    }

    func testSmoothingResetsAfterGapAndDropsUnreliableJoints() {
        let smoother = PoseSmoothingService()
        _ = smoother.smooth(makeFrame([.leftHip: (CGPoint(x: 0.4, y: 0.5), 0.9)], at: 0))
        let afterGap = smoother.smooth(makeFrame([.leftHip: (CGPoint(x: 0.8, y: 0.5), 0.9)], at: 1.0))
        XCTAssertEqual(afterGap.point(.leftHip)?.x ?? 0, 0.8, accuracy: 0.0001)

        let unreliable = smoother.smooth(makeFrame([
            .leftHip: (CGPoint(x: 0.8, y: 0.5), 0.1),
            .leftKnee: (CGPoint(x: 0.8, y: 0.3), 0.9)
        ], at: 1.1))
        XCTAssertNil(unreliable.point(.leftHip))
        XCTAssertNotNil(unreliable.point(.leftKnee))
    }
}
