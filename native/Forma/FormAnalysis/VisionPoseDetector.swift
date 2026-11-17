import AVFoundation
import CoreGraphics
import ImageIO
import Vision

enum PoseDetectionError: LocalizedError {
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .requestFailed(let message): return "Pose detection failed: \(message)"
        }
    }
}

protocol PoseDetecting: AnyObject {
    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        videoSize: CGSize,
        timestamp: TimeInterval
    ) throws -> PoseFrame
}

/// Wraps Apple's 2D body-pose request. This is Apple's general body detector,
/// not an exercise classifier or a form-correction model.
final class VisionPoseDetector: PoseDetecting {
    private let request = VNDetectHumanBodyPoseRequest()
    private let mapping: [(VNHumanBodyPoseObservation.JointName, BodyJoint)] = [
        (.nose, .nose),
        (.leftEye, .leftEye), (.rightEye, .rightEye),
        (.leftEar, .leftEar), (.rightEar, .rightEar),
        (.neck, .neck), (.root, .root),
        (.leftShoulder, .leftShoulder), (.rightShoulder, .rightShoulder),
        (.leftElbow, .leftElbow), (.rightElbow, .rightElbow),
        (.leftWrist, .leftWrist), (.rightWrist, .rightWrist),
        (.leftHip, .leftHip), (.rightHip, .rightHip),
        (.leftKnee, .leftKnee), (.rightKnee, .rightKnee),
        (.leftAnkle, .leftAnkle), (.rightAnkle, .rightAnkle)
    ]

    func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation,
        videoSize: CGSize,
        timestamp: TimeInterval
    ) throws -> PoseFrame {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw PoseDetectionError.requestFailed(error.localizedDescription)
        }

        let observations = (request.results ?? []) as [VNHumanBodyPoseObservation]
        guard !observations.isEmpty else {
            return .empty(timestamp: timestamp, videoSize: videoSize)
        }

        let primary = observations.max { $0.confidence < $1.confidence } ?? observations[0]
        let points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]
        do {
            points = try primary.recognizedPoints(.all)
        } catch {
            throw PoseDetectionError.requestFailed(error.localizedDescription)
        }

        var samples: [BodyJoint: JointSample] = [:]
        samples.reserveCapacity(mapping.count)
        for (visionName, joint) in mapping {
            guard let point = points[visionName] else { continue }
            samples[joint] = JointSample(
                joint: joint,
                position: point.location,
                confidence: Double(point.confidence),
                timestamp: timestamp
            )
        }

        let confidences = samples.values.map(\.confidence)
        let bodyConfidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)

        return PoseFrame(
            timestamp: timestamp,
            joints: samples,
            bodyConfidence: bodyConfidence,
            personCount: observations.count,
            videoSize: videoSize
        )
    }
}
