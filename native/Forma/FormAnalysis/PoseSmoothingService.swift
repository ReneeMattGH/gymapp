import CoreGraphics
import Foundation

struct PoseSmoothingConfiguration: Sendable {
    var minimumConfidence: Double = JointSample.defaultMinimumConfidence
    /// Weight applied to small frame-to-frame changes; lower means steadier.
    var stableAlpha: CGFloat = 0.35
    /// Weight applied to clear movement so smoothing never hides a rep.
    var movementAlpha: CGFloat = 0.7
    /// Normalised travel above which a change is treated as real movement.
    var movementThreshold: CGFloat = 0.02
    /// A gap longer than this starts the filter fresh instead of blending stale history.
    var resetInterval: TimeInterval = 0.45
}

/// Adaptive exponential smoothing per joint. Missing or low-confidence joints are
/// dropped rather than carried forward, so downstream logic never measures a joint
/// the camera could not see.
final class PoseSmoothingService {
    private struct State {
        var position: CGPoint
        var timestamp: TimeInterval
    }

    private var configuration: PoseSmoothingConfiguration
    private var history: [BodyJoint: State] = [:]

    init(configuration: PoseSmoothingConfiguration = PoseSmoothingConfiguration()) {
        self.configuration = configuration
    }

    func reset() {
        history.removeAll()
    }

    func smooth(_ frame: PoseFrame) -> PoseFrame {
        var smoothed: [BodyJoint: JointSample] = [:]
        smoothed.reserveCapacity(frame.joints.count)

        for (joint, sample) in frame.joints {
            guard sample.isUsable(minimumConfidence: configuration.minimumConfidence) else {
                history.removeValue(forKey: joint)
                continue
            }

            var output = sample
            if let previous = history[joint],
               sample.timestamp - previous.timestamp <= configuration.resetInterval,
               sample.timestamp >= previous.timestamp {
                let travel = hypot(sample.position.x - previous.position.x, sample.position.y - previous.position.y)
                let alpha = travel >= configuration.movementThreshold
                    ? configuration.movementAlpha
                    : configuration.stableAlpha
                output.position = CGPoint(
                    x: previous.position.x + (sample.position.x - previous.position.x) * alpha,
                    y: previous.position.y + (sample.position.y - previous.position.y) * alpha
                )
            }

            history[joint] = State(position: output.position, timestamp: sample.timestamp)
            smoothed[joint] = output
        }

        // Forget joints that disappeared from this frame.
        let present = Set(frame.joints.keys)
        history = history.filter { present.contains($0.key) }

        return PoseFrame(
            timestamp: frame.timestamp,
            joints: smoothed,
            bodyConfidence: frame.bodyConfidence,
            personCount: frame.personCount,
            videoSize: frame.videoSize
        )
    }
}
