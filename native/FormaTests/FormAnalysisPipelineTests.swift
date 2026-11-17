import CoreGraphics
import CoreVideo
import XCTest
@testable import Forma

final class FormAnalysisPipelineTests: XCTestCase {
    private let videoSize = CGSize(width: 720, height: 1280)

    // MARK: - Fixtures

    private func pose(
        _ joints: [BodyJoint: CGPoint],
        confidence: Double = 0.9,
        at timestamp: TimeInterval,
        personCount: Int = 1
    ) -> PoseFrame {
        var samples: [BodyJoint: JointSample] = [:]
        for (joint, point) in joints {
            samples[joint] = JointSample(
                joint: joint,
                position: point,
                confidence: confidence,
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

    private var standingSquat: [BodyJoint: CGPoint] {
        [
            .leftShoulder: CGPoint(x: 0.5, y: 0.8),
            .rightShoulder: CGPoint(x: 0.52, y: 0.8),
            .leftHip: CGPoint(x: 0.5, y: 0.55),
            .rightHip: CGPoint(x: 0.52, y: 0.55),
            .leftKnee: CGPoint(x: 0.5, y: 0.36),
            .leftAnkle: CGPoint(x: 0.5, y: 0.12)
        ]
    }

    private var bottomSquat: [BodyJoint: CGPoint] {
        [
            .leftShoulder: CGPoint(x: 0.7, y: 0.72),
            .rightShoulder: CGPoint(x: 0.72, y: 0.72),
            .leftHip: CGPoint(x: 0.5, y: 0.42),
            .rightHip: CGPoint(x: 0.52, y: 0.42),
            .leftKnee: CGPoint(x: 0.70, y: 0.35),
            .leftAnkle: CGPoint(x: 0.5, y: 0.12)
        ]
    }

    private func pixelBuffer() -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            16,
            16,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return buffer!
    }

    private func cameraFrame(timestamp: TimeInterval) -> CameraVideoFrame {
        CameraVideoFrame(
            pixelBuffer: pixelBuffer(),
            timestamp: timestamp,
            orientation: .right,
            videoSize: videoSize
        )
    }

    private func squatRepSequence(confidence: Double = 0.9, personCount: Int = 1) -> [PoseFrame] {
        var frames: [PoseFrame] = []
        var timestamp: TimeInterval = 0
        func add(_ joints: [BodyJoint: CGPoint], count: Int = 1) {
            for _ in 0..<count {
                frames.append(pose(joints, confidence: confidence, at: timestamp, personCount: personCount))
                timestamp += 0.1
            }
        }
        add(standingSquat, count: 7)
        add(bottomSquat, count: 9)
        add(standingSquat, count: 6)
        return frames
    }

    // MARK: - Fake detector

    private final class ScriptedDetector: PoseDetecting, @unchecked Sendable {
        var poses: [TimeInterval: PoseFrame] = [:]
        var failedTimestamps: Set<TimeInterval> = []
        private(set) var detectedFrames = 0

        func detect(
            pixelBuffer: CVPixelBuffer,
            orientation: CGImagePropertyOrientation,
            videoSize: CGSize,
            timestamp: TimeInterval
        ) throws -> PoseFrame {
            detectedFrames += 1
            if failedTimestamps.contains(timestamp) {
                throw PoseDetectionError.requestFailed("synthetic failure")
            }
            guard let pose = poses[timestamp] else {
                throw PoseDetectionError.requestFailed("missing synthetic pose")
            }
            return pose
        }
    }

    private func makePipeline(
        frames: [PoseFrame],
        exercise: FormAnalysisExercise = .squat
    ) -> (FormAnalysisPipeline, ScriptedDetector, () -> [FormAnalysisUpdate]) {
        let detector = ScriptedDetector()
        for frame in frames {
            detector.poses[frame.timestamp] = frame
        }
        let pipeline = FormAnalysisPipeline(
            exercise: exercise,
            cameraPosition: .front,
            detector: detector
        )
        var updates: [FormAnalysisUpdate] = []
        pipeline.onUpdate = { updates.append($0) }
        return (pipeline, detector, { updates })
    }

    // MARK: - Tests

    func testReliableSquatSequenceCountsOneRep() {
        let frames = squatRepSequence()
        let (pipeline, _, updates) = makePipeline(frames: frames)

        for frame in frames {
            pipeline.process(cameraFrame(timestamp: frame.timestamp))
        }
        let finished = pipeline.finish()

        let snapshot = updates()
        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertTrue(snapshot.contains { $0.tracking == .tracking })
        XCTAssertTrue(snapshot.contains { $0.canCountReps })
        XCTAssertEqual(snapshot.last?.repCount, 1)
        XCTAssertEqual(finished.repCount, 1)
        XCTAssertTrue(finished.repCountingReliable)
        XCTAssertGreaterThan(finished.coverage ?? 0, 0.9)
    }

    func testLowConfidenceSequenceNeverCounts() {
        let frames = squatRepSequence(confidence: 0.4)
        let (pipeline, _, updates) = makePipeline(frames: frames)

        for frame in frames {
            pipeline.process(cameraFrame(timestamp: frame.timestamp))
        }
        let finished = pipeline.finish()

        let snapshot = updates()
        XCTAssertFalse(snapshot.isEmpty)
        XCTAssertFalse(snapshot.contains { $0.canCountReps })
        XCTAssertTrue(snapshot.allSatisfy { $0.repCount == 0 })
        XCTAssertNil(finished.repCount)
        XCTAssertFalse(finished.repCountingReliable)
    }

    func testTwoPeopleNeverCountsAndHidesSkeleton() {
        let frames = squatRepSequence(personCount: 2)
        let (pipeline, _, updates) = makePipeline(frames: frames)

        for frame in frames {
            pipeline.process(cameraFrame(timestamp: frame.timestamp))
        }
        let snapshot = updates()

        XCTAssertTrue(snapshot.contains { $0.tracking == .multiplePeople })
        XCTAssertTrue(snapshot.allSatisfy { $0.poseFrame == nil })
        XCTAssertTrue(snapshot.allSatisfy { !$0.canCountReps })
        XCTAssertTrue(snapshot.allSatisfy { $0.repCount == 0 })
    }

    func testEmptyFramesReportNoBodyWithoutSkeleton() {
        let empty = (0...4).map { pose([:], confidence: 0, at: Double($0) * 0.1, personCount: 0) }
        let (pipeline, _, updates) = makePipeline(frames: empty)

        for frame in empty {
            pipeline.process(cameraFrame(timestamp: frame.timestamp))
        }
        let snapshot = updates()

        XCTAssertTrue(snapshot.contains { $0.tracking == .noBody })
        XCTAssertTrue(snapshot.allSatisfy { $0.poseFrame == nil })
        XCTAssertFalse(snapshot.contains { $0.canCountReps })
    }

    func testDetectionErrorsAreReportedAndRecover() {
        let frames = squatRepSequence()
        let detectorFailures: Set<TimeInterval> = [0, 0.1, 0.2]
        let (pipeline, detector, updates) = makePipeline(frames: frames)
        detector.failedTimestamps = detectorFailures

        for frame in frames {
            pipeline.process(cameraFrame(timestamp: frame.timestamp))
        }
        let snapshot = updates()

        XCTAssertTrue(snapshot.contains { $0.message != nil })
        XCTAssertTrue(snapshot.contains { $0.tracking == .limited })
        XCTAssertTrue(updates().contains { $0.tracking == .tracking })
    }

    func testPausedPipelineDropsFramesThenResumes() {
        let frames = squatRepSequence()
        let (pipeline, detector, updates) = makePipeline(frames: frames)
        detector.poses[10] = pose(standingSquat, at: 10)

        pipeline.process(cameraFrame(timestamp: 0))
        let afterFirst = updates().count
        XCTAssertGreaterThan(afterFirst, 0)

        pipeline.setPaused(true)
        for frame in frames where frame.timestamp > 0 {
            pipeline.process(cameraFrame(timestamp: frame.timestamp))
        }
        XCTAssertEqual(updates().count, afterFirst)

        pipeline.setPaused(false)
        pipeline.process(cameraFrame(timestamp: 10))
        XCTAssertEqual(updates().count, afterFirst + 1)
    }

    func testUnavailableRepTextIsExactWhenNothingIsReliable() {
        let frames = squatRepSequence(confidence: 0.2)
        let (pipeline, _, _) = makePipeline(frames: frames)
        for frame in frames {
            pipeline.process(cameraFrame(timestamp: frame.timestamp))
        }
        let finished = pipeline.finish()
        XCTAssertNil(finished.repCount)
        XCTAssertEqual(FormAnalysisText.repCountingUnavailable,
                       "Rep counting unavailable — movement could not be tracked reliably.")
    }
}
