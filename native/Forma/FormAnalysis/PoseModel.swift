import CoreGraphics
import Foundation

enum BodySide: String, Codable, Sendable {
    case left, right, center
}

/// Joints that a pose detector can report. `neck` is only present when the
/// underlying model actually recognised it — it is never synthesised.
enum BodyJoint: String, CaseIterable, Codable, Sendable {
    case nose, leftEye, rightEye, leftEar, rightEar
    case neck, root
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle

    var side: BodySide {
        switch self {
        case .leftEye, .leftEar, .leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftKnee, .leftAnkle:
            return .left
        case .rightEye, .rightEar, .rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightKnee, .rightAnkle:
            return .right
        default:
            return .center
        }
    }

    var displayName: String {
        switch self {
        case .nose: return "nose"
        case .leftEye: return "left eye"
        case .rightEye: return "right eye"
        case .leftEar: return "left ear"
        case .rightEar: return "right ear"
        case .neck: return "neck"
        case .root: return "hip centre"
        case .leftShoulder: return "left shoulder"
        case .rightShoulder: return "right shoulder"
        case .leftElbow: return "left elbow"
        case .rightElbow: return "right elbow"
        case .leftWrist: return "left wrist"
        case .rightWrist: return "right wrist"
        case .leftHip: return "left hip"
        case .rightHip: return "right hip"
        case .leftKnee: return "left knee"
        case .rightKnee: return "right knee"
        case .leftAnkle: return "left ankle"
        case .rightAnkle: return "right ankle"
        }
    }

    var isUpperBody: Bool {
        switch self {
        case .nose, .leftEye, .rightEye, .leftEar, .rightEar, .neck,
             .leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist:
            return true
        default:
            return false
        }
    }
}

struct JointSample: Equatable, Sendable {
    /// Vision's normalised coordinate space: origin bottom-left, x to the right,
    /// y upward, both in 0...1 relative to the oriented frame.
    var joint: BodyJoint
    var position: CGPoint
    var confidence: Double
    var timestamp: TimeInterval

    static let defaultMinimumConfidence: Double = 0.3

    func isUsable(minimumConfidence: Double = JointSample.defaultMinimumConfidence) -> Bool {
        confidence >= minimumConfidence
            && position.x.isFinite && position.y.isFinite
            && (0...1).contains(position.x) && (0...1).contains(position.y)
    }
}

struct BodySkeleton {
    /// Pairs that get a line when both endpoints are usable.
    static let connections: [(BodyJoint, BodyJoint)] = [
        (.nose, .leftEye), (.nose, .rightEye), (.leftEye, .leftEar), (.rightEye, .rightEar),
        (.nose, .neck), (.neck, .leftShoulder), (.neck, .rightShoulder),
        (.neck, .root),
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip), (.root, .leftHip), (.root, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle)
    ]
}

/// A single pose observation. Coordinates stay in Vision's normalised space so
/// the overlay and the analysers share one deterministic convention; only the
/// preview layer flips y for display.
struct PoseFrame: Equatable, Sendable {
    var timestamp: TimeInterval
    var joints: [BodyJoint: JointSample]
    var bodyConfidence: Double
    var personCount: Int
    /// Size of the oriented camera frame (portrait, as displayed).
    var videoSize: CGSize

    static let reliableBodyConfidence: Double = 0.4
    static let minimumReliableJointCount = 4

    var imageAspectRatio: CGFloat {
        guard videoSize.height > 0 else { return 1 }
        return videoSize.width / videoSize.height
    }

    var hasAmbiguousPeople: Bool { personCount > 1 }

    var usableJointCount: Int {
        joints.values.filter { $0.isUsable() }.count
    }

    func sample(
        _ joint: BodyJoint,
        minimumConfidence: Double = JointSample.defaultMinimumConfidence
    ) -> JointSample? {
        guard let sample = joints[joint], sample.isUsable(minimumConfidence: minimumConfidence) else {
            return nil
        }
        return sample
    }

    func point(
        _ joint: BodyJoint,
        minimumConfidence: Double = JointSample.defaultMinimumConfidence
    ) -> CGPoint? {
        sample(joint, minimumConfidence: minimumConfidence)?.position
    }

    func midpoint(
        _ first: BodyJoint,
        _ second: BodyJoint,
        minimumConfidence: Double = JointSample.defaultMinimumConfidence
    ) -> CGPoint? {
        guard let a = point(first, minimumConfidence: minimumConfidence),
              let b = point(second, minimumConfidence: minimumConfidence) else {
            return nil
        }
        return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    func confidence(
        of joint: BodyJoint,
        minimumConfidence: Double = JointSample.defaultMinimumConfidence
    ) -> Double {
        sample(joint, minimumConfidence: minimumConfidence)?.confidence ?? 0
    }

    /// Tracking is only considered reliable for a single, confidently visible person.
    var isReliable: Bool {
        !hasAmbiguousPeople
            && bodyConfidence >= Self.reliableBodyConfidence
            && usableJointCount >= Self.minimumReliableJointCount
    }

    static func empty(timestamp: TimeInterval = 0, videoSize: CGSize = .zero) -> PoseFrame {
        PoseFrame(timestamp: timestamp, joints: [:], bodyConfidence: 0, personCount: 0, videoSize: videoSize)
    }
}
