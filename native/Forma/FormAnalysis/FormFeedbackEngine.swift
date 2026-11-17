import Foundation

enum FeedbackStatus: String, Codable, Equatable, Sendable {
    case reliable, limited, unavailable

    var label: String {
        switch self {
        case .reliable: return "Observed"
        case .limited: return "Limited"
        case .unavailable: return "Unavailable"
        }
    }
}

enum ObservationKind: String, Codable, Equatable, Sendable {
    case tracking, rep
}

struct FormObservation: Identifiable, Equatable, Sendable {
    var id: String
    var status: FeedbackStatus
    var text: String
    var joints: [BodyJoint]
    var limitation: String?
    var timestamp: TimeInterval
    var kind: ObservationKind
    var exercise: FormAnalysisExercise?
    var measurements: [String: Double] = [:]

    /// Short, human-readable list of the values this observation was derived
    /// from. Empty when the result is a tracking state with no measurement.
    var measurementSummary: String? {
        guard !measurements.isEmpty else { return nil }
        let ordered = [
            "minimumKneeAngle", "maximumKneeAngle",
            "minimumElbowAngle", "maximumElbowAngle",
            "torsoDelta", "tightestBodyAlignmentAngle",
            "maximumArmRaiseRatio", "maximumLegSeparationRatio",
            "coverage"
        ]
        var parts: [String] = []
        for key in ordered {
            if let value = measurements[key], let part = Self.describe(key: key, value: value) {
                parts.append(part)
            }
        }
        for key in measurements.keys.sorted() where !ordered.contains(key) {
            if let value = measurements[key], let part = Self.describe(key: key, value: value) {
                parts.append(part)
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func describe(key: String, value: Double) -> String? {
        switch key {
        case "minimumKneeAngle":
            return "knee \(Int(value.rounded()))°"
        case "minimumElbowAngle":
            return "elbow \(Int(value.rounded()))°"
        case "minimumTorsoAngle", "maximumTorsoAngle":
            return nil
        case "torsoDelta":
            return "torso change \(Int(value.rounded()))°"
        case "tightestBodyAlignmentAngle":
            return "body line \(Int(value.rounded()))°"
        case "maximumArmRaiseRatio":
            return String(format: "arm rise %.1f× torso", value)
        case "maximumLegSeparationRatio":
            return String(format: "foot spacing %.1f× hips", value)
        case "coverage":
            return "reliable coverage \(Int((value * 100).rounded()))%"
        default:
            return "\(key) \(String(format: "%.2f", value))"
        }
    }
}

struct RepMetricSummary: Equatable, Sendable {
    var minimumKneeAngle: Double?
    var maximumKneeAngle: Double?
    var minimumElbowAngle: Double?
    var maximumElbowAngle: Double?
    var minimumTorsoAngle: Double?
    var maximumTorsoAngle: Double?
    var minimumBodyAlignmentAngle: Double?
    var maximumBodyAlignmentAngle: Double?
    var minimumArmRaiseRatio: Double?
    var maximumArmRaiseRatio: Double?
    var minimumLegSeparationRatio: Double?
    var maximumLegSeparationRatio: Double?

    mutating func record(_ metrics: MovementMetrics) {
        if let value = metrics.kneeAngle {
            minimumKneeAngle = min(minimumKneeAngle ?? value, value)
            maximumKneeAngle = max(maximumKneeAngle ?? value, value)
        }
        if let value = metrics.elbowAngle {
            minimumElbowAngle = min(minimumElbowAngle ?? value, value)
            maximumElbowAngle = max(maximumElbowAngle ?? value, value)
        }
        if let value = metrics.torsoAngle {
            minimumTorsoAngle = min(minimumTorsoAngle ?? value, value)
            maximumTorsoAngle = max(maximumTorsoAngle ?? value, value)
        }
        if let value = metrics.bodyAlignmentAngle {
            minimumBodyAlignmentAngle = min(minimumBodyAlignmentAngle ?? value, value)
            maximumBodyAlignmentAngle = max(maximumBodyAlignmentAngle ?? value, value)
        }
        if let value = metrics.armRaiseRatio {
            minimumArmRaiseRatio = min(minimumArmRaiseRatio ?? value, value)
            maximumArmRaiseRatio = max(maximumArmRaiseRatio ?? value, value)
        }
        if let value = metrics.legSeparationRatio {
            minimumLegSeparationRatio = min(minimumLegSeparationRatio ?? value, value)
            maximumLegSeparationRatio = max(maximumLegSeparationRatio ?? value, value)
        }
    }
}

struct RepObservation: Equatable, Sendable {
    var exercise: FormAnalysisExercise
    var boundary: CompletedRepBoundary
    var metrics: RepMetricSummary
    var averageConfidence: Double
    var totalFrameCount: Int
    var reliableFrameCount: Int
    var measuredJoints: [BodyJoint]
    var hadTrackingLoss: Bool

    var coverage: Double {
        guard totalFrameCount > 0 else { return 0 }
        return Double(reliableFrameCount) / Double(totalFrameCount)
    }
}

enum FormAnalysisText {
    static let repCountingPaused = "Rep counting paused — body movement cannot be tracked reliably."
    static let repCountingUnavailable = "Rep counting unavailable — movement could not be tracked reliably."
}

/// Turns measured pose values into short observations. Every message names the
/// data it came from and carries an explicit limitation; nothing is inferred
/// beyond what the pose frames contained.
final class FormFeedbackEngine {
    private var lastTrackingKey: String?
    private var lastTrackingAt: TimeInterval = -.infinity
    private let trackingRefreshInterval: TimeInterval = 12

    func reset() {
        lastTrackingKey = nil
        lastTrackingAt = -.infinity
    }

    func trackingObservation(for analysis: MovementAnalysis) -> FormObservation? {
        let key: String
        let status: FeedbackStatus
        let text: String
        let joints: [BodyJoint]

        switch analysis.reliability {
        case .reliable:
            key = "reliable-\(analysis.exercise.rawValue)"
            status = .reliable
            text = "Full body visible. \(analysis.exercise.title) movement tracking is active."
            joints = analysis.exercise.requiredJoints
        case .limited:
            key = "limited-\(analysis.missingJoints.map(\.rawValue).joined(separator: "-"))"
            status = .limited
            text = analysis.framingNote ?? "Tracking is limited. Keep your whole body inside the frame."
            joints = analysis.missingJoints
        case .unavailable:
            key = "unavailable-\(analysis.missingJoints.map(\.rawValue).joined(separator: "-"))"
            status = .unavailable
            text = analysis.framingNote ?? "No body detected. Step into the frame and make sure you are alone."
            joints = analysis.missingJoints
        }

        if key == lastTrackingKey, analysis.timestamp - lastTrackingAt < trackingRefreshInterval {
            return nil
        }
        lastTrackingKey = key
        lastTrackingAt = analysis.timestamp

        return FormObservation(
            id: "tracking-\(key)",
            status: status,
            text: text,
            joints: joints,
            limitation: status == .reliable ? nil : "Guidance is based only on joints the camera can currently see.",
            timestamp: analysis.timestamp,
            kind: .tracking,
            exercise: analysis.exercise
        )
    }

    func observations(for rep: RepObservation) -> [FormObservation] {
        var results: [FormObservation] = []
        let index = rep.boundary.index
        let prefix = "Rep \(index):"

        switch rep.exercise {
        case .squat:
            if let bottom = rep.metrics.minimumKneeAngle {
                var text = "\(prefix) your knee angle reached about \(degrees(bottom)) at the lowest point."
                if let low = rep.metrics.minimumTorsoAngle,
                   let high = rep.metrics.maximumTorsoAngle,
                   high - low >= 15 {
                    text += " Your torso angle changed by about \(degrees(high - low)) during the rep."
                }
                var measurements: [String: Double] = ["minimumKneeAngle": bottom]
                if let low = rep.metrics.minimumTorsoAngle,
                   let high = rep.metrics.maximumTorsoAngle,
                   high - low >= 15 {
                    measurements["torsoDelta"] = high - low
                }
                results.append(repObservation(
                    id: "rep-\(index)-squat-angle",
                    exercise: rep.exercise,
                    text: text,
                    joints: [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle,
                             .leftShoulder, .rightShoulder],
                    measurements: measurements,
                    timestamp: rep.boundary.completedAt
                ))
            } else {
                results.append(unavailableRep(index: index, exercise: rep.exercise, timestamp: rep.boundary.completedAt))
            }

        case .pushUp:
            if let bottom = rep.metrics.minimumElbowAngle {
                var text = "\(prefix) your elbow angle reached about \(degrees(bottom)) at the lowest point."
                if let tightest = rep.metrics.minimumBodyAlignmentAngle {
                    text += " The tightest shoulder–hip–ankle line measured was about \(degrees(tightest)); 180° is straight."
                }
                var measurements: [String: Double] = ["minimumElbowAngle": bottom]
                if let tightest = rep.metrics.minimumBodyAlignmentAngle {
                    measurements["tightestBodyAlignmentAngle"] = tightest
                }
                results.append(repObservation(
                    id: "rep-\(index)-pushup-angle",
                    exercise: rep.exercise,
                    text: text,
                    joints: [.leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftAnkle,
                             .rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightAnkle],
                    measurements: measurements,
                    timestamp: rep.boundary.completedAt
                ))
            } else {
                results.append(unavailableRep(index: index, exercise: rep.exercise, timestamp: rep.boundary.completedAt))
            }

        case .lunge:
            if let bottom = rep.metrics.minimumKneeAngle {
                var text = "\(prefix) your front knee angle reached about \(degrees(bottom)) at the lowest point."
                if let low = rep.metrics.minimumTorsoAngle,
                   let high = rep.metrics.maximumTorsoAngle,
                   high - low >= 15 {
                    text += " Your torso angle changed by about \(degrees(high - low)) during the rep."
                }
                var measurements: [String: Double] = ["minimumKneeAngle": bottom]
                if let low = rep.metrics.minimumTorsoAngle,
                   let high = rep.metrics.maximumTorsoAngle,
                   high - low >= 15 {
                    measurements["torsoDelta"] = high - low
                }
                results.append(repObservation(
                    id: "rep-\(index)-lunge-angle",
                    exercise: rep.exercise,
                    text: text,
                    joints: [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle,
                             .leftShoulder, .rightShoulder],
                    measurements: measurements,
                    timestamp: rep.boundary.completedAt
                ))
            } else {
                results.append(unavailableRep(index: index, exercise: rep.exercise, timestamp: rep.boundary.completedAt))
            }

        case .jumpingJack:
            if let arm = rep.metrics.maximumArmRaiseRatio,
               let legs = rep.metrics.maximumLegSeparationRatio {
                let text = "\(prefix) your hands rose about \(decimal(arm)) torso lengths above your shoulders and your feet reached about \(decimal(legs))× hip width."
                results.append(FormObservation(
                    id: "rep-\(index)-jumpingjack-range",
                    status: .reliable,
                    text: text,
                    joints: [.leftShoulder, .rightShoulder, .leftWrist, .rightWrist,
                             .leftHip, .rightHip, .leftAnkle, .rightAnkle],
                    limitation: "Separation is sensitive to camera distance and angle.",
                    timestamp: rep.boundary.completedAt,
                    kind: .rep,
                    exercise: rep.exercise,
                    measurements: [
                        "maximumArmRaiseRatio": arm,
                        "maximumLegSeparationRatio": legs
                    ]
                ))
            } else {
                results.append(unavailableRep(index: index, exercise: rep.exercise, timestamp: rep.boundary.completedAt))
            }
        }

        if rep.hadTrackingLoss || rep.coverage < 0.6 {
            results.append(FormObservation(
                id: "rep-\(index)-coverage",
                status: .limited,
                text: "\(prefix) tracking was interrupted during part of the movement, so the readings above may be incomplete.",
                joints: [],
                limitation: "Only \(Int((rep.coverage * 100).rounded()))% of analysed frames in this rep were reliable.",
                timestamp: rep.boundary.completedAt,
                kind: .rep,
                exercise: rep.exercise,
                measurements: ["coverage": rep.coverage]
            ))
        }

        return results
    }

    // MARK: - Helpers

    private func repObservation(
        id: String,
        exercise: FormAnalysisExercise,
        text: String,
        joints: [BodyJoint],
        measurements: [String: Double],
        timestamp: TimeInterval
    ) -> FormObservation {
        FormObservation(
            id: id,
            status: .reliable,
            text: text,
            joints: joints,
            limitation: "Measured from a single 2D camera view; camera angle affects the projected angle.",
            timestamp: timestamp,
            kind: .rep,
            exercise: exercise,
            measurements: measurements
        )
    }

    private func unavailableRep(index: Int, exercise: FormAnalysisExercise, timestamp: TimeInterval) -> FormObservation {
        FormObservation(
            id: "rep-\(index)-unavailable",
            status: .unavailable,
            text: "Rep \(index): the position needed to describe this rep was not visible long enough to measure.",
            joints: [],
            limitation: "No angle estimate is shown rather than guessing.",
            timestamp: timestamp,
            kind: .rep,
            exercise: exercise
        )
    }

    private func degrees(_ value: Double) -> String {
        "\(Int(value.rounded()))°"
    }

    private func decimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
