import CoreGraphics
import Foundation

enum AnalysisReliability: String, Equatable, Sendable {
    case reliable, limited, unavailable

    var label: String {
        switch self {
        case .reliable: return "Tracking"
        case .limited: return "Limited tracking"
        case .unavailable: return "Not tracking"
        }
    }
}

/// Exercises this build can actually analyse. Rep thresholds are provisional
/// estimates derived from the 2D signal scale and still need on-device calibration;
/// they are not presented as validated clinical or coaching measurements.
enum FormAnalysisExercise: String, CaseIterable, Identifiable, Codable, Sendable {
    case squat, pushUp, lunge, jumpingJack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .squat: return "Bodyweight squat"
        case .pushUp: return "Push-up"
        case .lunge: return "Lunge"
        case .jumpingJack: return "Jumping jack"
        }
    }

    var shortTitle: String {
        switch self {
        case .squat: return "Squat"
        case .pushUp: return "Push-up"
        case .lunge: return "Lunge"
        case .jumpingJack: return "Jumping jack"
        }
    }

    /// Catalog exercise this analysis maps to, when one exists.
    var catalogID: String? {
        switch self {
        case .squat: return "bodyweight-squat"
        case .pushUp: return "push-up"
        case .lunge: return "walking-lunge"
        case .jumpingJack: return nil
        }
    }

    static func matching(catalogID: String) -> FormAnalysisExercise? {
        FormAnalysisExercise.allCases.first { $0.catalogID == catalogID }
    }

    var icon: String {
        switch self {
        case .squat: return "figure.strengthtraining.functional"
        case .pushUp: return "figure.strengthtraining.traditional"
        case .lunge: return "figure.walk"
        case .jumpingJack: return "figure.jumprope"
        }
    }

    var setupSteps: [String] {
        switch self {
        case .squat:
            return [
                "Place the phone 2–3 m away at hip height, side-on or at about 45°.",
                "Keep your head, hips, knees and feet inside the frame for the whole set.",
                "Face a soft, even light source; avoid standing with a bright window behind you."
            ]
        case .pushUp:
            return [
                "Place the phone on the floor about 1.5–2 m away, side-on to your body.",
                "Raise it slightly so your shoulders, hips and feet all stay visible.",
                "Keep the area around your hands and feet well lit."
            ]
        case .lunge:
            return [
                "Place the phone 2–3 m away at hip height, side-on or at about 45°.",
                "Both legs, including the rear foot, must stay inside the frame.",
                "Use even lighting and avoid loose clothing that hides the knees."
            ]
        case .jumpingJack:
            return [
                "Place the phone 2.5–3.5 m away, straight on, at chest height.",
                "Keep your hands and feet in frame at the widest point of the movement.",
                "Stand alone in the frame against a plain background if possible."
            ]
        }
    }

    var framingHint: String {
        switch self {
        case .squat: return "Side-on is the most reliable angle for squat depth."
        case .pushUp: return "A low side-on angle keeps the elbow and body line visible."
        case .lunge: return "Keep both feet visible so the front and rear legs can be compared."
        case .jumpingJack: return "A straight-on view is required to see both arms and both feet."
        }
    }

    var requiredJoints: [BodyJoint] {
        switch self {
        case .squat:
            return [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle,
                    .leftShoulder, .rightShoulder]
        case .pushUp:
            return [.leftShoulder, .leftElbow, .leftWrist, .leftHip, .leftAnkle,
                    .rightShoulder, .rightElbow, .rightWrist, .rightHip, .rightAnkle]
        case .lunge:
            return [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle,
                    .leftShoulder, .rightShoulder]
        case .jumpingJack:
            return [.leftShoulder, .rightShoulder, .leftWrist, .rightWrist,
                    .leftHip, .rightHip, .leftAnkle, .rightAnkle]
        }
    }

    var repConfiguration: RepCountingConfiguration {
        var config = RepCountingConfiguration()
        switch self {
        case .squat:
            config.startThreshold = 0.18
            config.bottomThreshold = 0.78
            config.bottomExitThreshold = 0.62
            config.returnThreshold = 0.20
            config.minimumRepDuration = 0.8
            config.maximumRepDuration = 8
        case .pushUp:
            config.startThreshold = 0.15
            config.bottomThreshold = 0.78
            config.bottomExitThreshold = 0.60
            config.returnThreshold = 0.20
            config.minimumRepDuration = 0.7
            config.maximumRepDuration = 8
        case .lunge:
            config.startThreshold = 0.18
            config.bottomThreshold = 0.75
            config.bottomExitThreshold = 0.60
            config.returnThreshold = 0.22
            config.minimumRepDuration = 0.9
            config.maximumRepDuration = 10
        case .jumpingJack:
            config.startThreshold = 0.15
            config.bottomThreshold = 0.75
            config.bottomExitThreshold = 0.55
            config.returnThreshold = 0.20
            config.minimumRepDuration = 0.5
            config.maximumRepDuration = 6
            config.minimumBottomHold = 0.04
        }
        return config
    }

    /// Text shown in the UI. Nothing here claims validated accuracy.
    var analysisNote: String {
        switch self {
        case .jumpingJack:
            return "Jumping jack is analyzed as a conditioning drill; it is not a plan-library exercise."
        default:
            return "Measured from a single 2D camera view. Angles are estimates, not clinical measurements."
        }
    }
}

struct MovementMetrics: Equatable, Sendable {
    var kneeAngle: Double?
    var elbowAngle: Double?
    var torsoAngle: Double?
    var bodyAlignmentAngle: Double?
    /// Wrist height above the shoulder midpoint, in torso lengths. Negative below the shoulders.
    var armRaiseRatio: Double?
    /// Ankle separation divided by hip width.
    var legSeparationRatio: Double?
    var activeSide: BodySide?
}

struct MovementAnalysis: Equatable, Sendable {
    var exercise: FormAnalysisExercise
    var timestamp: TimeInterval
    /// 0 at the extended/top position, 1 at the deepest/closed position.
    var signal: Double?
    var signalConfidence: Double
    var reliability: AnalysisReliability
    var metrics: MovementMetrics
    var missingJoints: [BodyJoint]
    var framingNote: String?

    var canCountReps: Bool {
        reliability != .unavailable && signal != nil && signalConfidence >= 0.5
    }

    static func unavailable(
        exercise: FormAnalysisExercise,
        frame: PoseFrame,
        missing: [BodyJoint],
        note: String?
    ) -> MovementAnalysis {
        MovementAnalysis(
            exercise: exercise,
            timestamp: frame.timestamp,
            signal: nil,
            signalConfidence: MissingJointSummary.confidence(in: frame, joints: missing),
            reliability: .unavailable,
            metrics: MovementMetrics(),
            missingJoints: missing,
            framingNote: note
        )
    }
}

protocol ExerciseMovementAnalyzing: AnyObject {
    var exercise: FormAnalysisExercise { get }
    func analyze(_ frame: PoseFrame) -> MovementAnalysis
}

enum MissingJointSummary {
    static func confidence(in frame: PoseFrame, joints: [BodyJoint]) -> Double {
        let values = joints.compactMap { frame.joints[$0]?.confidence }
        return values.min() ?? 0
    }

    static func note(for missing: [BodyJoint], in frame: PoseFrame) -> String? {
        guard !missing.isEmpty else { return nil }
        let names = missing.map(\.displayName)
        let joined: String
        switch names.count {
        case 1: joined = names[0]
        case 2: joined = "\(names[0]) and \(names[1])"
        default: joined = names.dropLast().joined(separator: ", ") + " and " + (names.last ?? "")
        }
        let unclearCount = missing.filter { frame.joints[$0] != nil }.count
        if unclearCount == missing.count {
            return "Your \(joined) \(missing.count == 1 ? "is" : "are") unclear. Improve the lighting or step back slightly."
        }
        if unclearCount > 0 {
            return "Your \(joined) are partly outside the frame or unclear. Step back so your whole body is visible."
        }
        return "Your \(joined) \(missing.count == 1 ? "is" : "are") outside the camera frame. Step back so your whole body is visible."
    }
}

// MARK: - Shared geometry

struct LegChain {
    var side: BodySide
    var hip: CGPoint
    var knee: CGPoint
    var ankle: CGPoint
    var confidence: Double
}

enum AnalyzerSupport {
    static let reliableJointConfidence: Double = 0.5
    static let minimumBodyConfidence: Double = PoseFrame.reliableBodyConfidence

    static func legChain(in frame: PoseFrame, side: BodySide) -> LegChain? {
        let joints: (BodyJoint, BodyJoint, BodyJoint) = side == .left
            ? (.leftHip, .leftKnee, .leftAnkle)
            : (.rightHip, .rightKnee, .rightAnkle)
        guard let hip = frame.sample(joints.0),
              let knee = frame.sample(joints.1),
              let ankle = frame.sample(joints.2) else {
            return nil
        }
        return LegChain(
            side: side,
            hip: hip.position,
            knee: knee.position,
            ankle: ankle.position,
            confidence: min(hip.confidence, min(knee.confidence, ankle.confidence))
        )
    }

    static func legJoints(for side: BodySide) -> [BodyJoint] {
        side == .left ? [.leftHip, .leftKnee, .leftAnkle] : [.rightHip, .rightKnee, .rightAnkle]
    }

    /// Prefers the shoulder/hip midpoints, falls back to a single visible side.
    static func torsoAngle(in frame: PoseFrame, preferredSide: BodySide?) -> Double? {
        let aspect = frame.imageAspectRatio
        if let shoulders = frame.midpoint(.leftShoulder, .rightShoulder),
           let hips = frame.midpoint(.leftHip, .rightHip) {
            return PoseGeometry.verticalAngle(from: hips, to: shoulders, aspectRatio: aspect)
        }
        let sides: [BodySide] = preferredSide.map { [$0] } ?? [.left, .right]
        for side in sides {
            let shoulder: BodyJoint = side == .left ? .leftShoulder : .rightShoulder
            let hip: BodyJoint = side == .left ? .leftHip : .rightHip
            if let shoulderPoint = frame.point(shoulder), let hipPoint = frame.point(hip) {
                return PoseGeometry.verticalAngle(from: hipPoint, to: shoulderPoint, aspectRatio: aspect)
            }
        }
        return nil
    }

    static func missingLegJoints(in frame: PoseFrame) -> [BodyJoint] {
        let leftMissing = legJoints(for: .left).filter { frame.sample($0) == nil }
        let rightMissing = legJoints(for: .right).filter { frame.sample($0) == nil }
        return leftMissing.count <= rightMissing.count ? leftMissing : rightMissing
    }

    static func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    static func totalConfidence(_ confidences: [Double]) -> Double {
        confidences.min() ?? 0
    }
}

// MARK: - Squat

final class SquatMovementAnalyzer: ExerciseMovementAnalyzing {
    let exercise = FormAnalysisExercise.squat

    private let topAngle: Double = 165
    private let bottomAngle: Double = 95

    func analyze(_ frame: PoseFrame) -> MovementAnalysis {
        if frame.hasAmbiguousPeople {
            return .unavailable(
                exercise: exercise,
                frame: frame,
                missing: [],
                note: "More than one person is visible. Make sure you are alone in the frame."
            )
        }

        if frame.usableJointCount == 0 {
            return .unavailable(
                exercise: exercise,
                frame: frame,
                missing: [],
                note: "No body detected. Step into the frame so your head and feet are visible."
            )
        }

        let chains = [BodySide.left, BodySide.right]
            .compactMap { AnalyzerSupport.legChain(in: frame, side: $0) }

        guard !chains.isEmpty else {
            let missing = AnalyzerSupport.missingLegJoints(in: frame)
            return .unavailable(
                exercise: exercise,
                frame: frame,
                missing: missing,
                note: MissingJointSummary.note(for: missing, in: frame)
            )
        }

        let aspect = frame.imageAspectRatio
        let angles = chains.compactMap {
            PoseGeometry.angle(a: $0.hip, b: $0.knee, c: $0.ankle, aspectRatio: aspect)
        }
        guard let kneeAngle = AnalyzerSupport.average(angles) else {
            return .unavailable(exercise: exercise, frame: frame, missing: [], note: "Knee position could not be measured from this angle.")
        }

        let signal = PoseGeometry.progress(value: kneeAngle, start: topAngle, end: bottomAngle)
        let confidence = AnalyzerSupport.totalConfidence(chains.map(\.confidence))
        let torso = AnalyzerSupport.torsoAngle(in: frame, preferredSide: chains.first?.side)

        let reliable = confidence >= AnalyzerSupport.reliableJointConfidence
            && frame.bodyConfidence >= AnalyzerSupport.minimumBodyConfidence
        let reliability: AnalysisReliability = reliable && torso != nil ? .reliable : .limited
        let note: String? = torso == nil && reliable
            ? "Your shoulders or hips are partly out of frame, so torso angle cannot be measured. Squat reps can still count."
            : nil

        return MovementAnalysis(
            exercise: exercise,
            timestamp: frame.timestamp,
            signal: signal,
            signalConfidence: confidence,
            reliability: reliability,
            metrics: MovementMetrics(
                kneeAngle: kneeAngle,
                torsoAngle: torso,
                activeSide: chains.first?.side
            ),
            missingJoints: [],
            framingNote: note
        )
    }
}

// MARK: - Push-up

final class PushUpMovementAnalyzer: ExerciseMovementAnalyzing {
    let exercise = FormAnalysisExercise.pushUp

    private let topAngle: Double = 165
    private let bottomAngle: Double = 80

    func analyze(_ frame: PoseFrame) -> MovementAnalysis {
        if frame.hasAmbiguousPeople {
            return .unavailable(
                exercise: exercise,
                frame: frame,
                missing: [],
                note: "More than one person is visible. Make sure you are alone in the frame."
            )
        }
        if frame.usableJointCount == 0 {
            return .unavailable(
                exercise: exercise,
                frame: frame,
                missing: [],
                note: "No body detected. Position the phone low and side-on to your body."
            )
        }

        let aspect = frame.imageAspectRatio
        var branches: [(side: BodySide, elbowAngle: Double, alignment: Double?, confidence: Double, missing: [BodyJoint])] = []

        for side in [BodySide.left, .right] {
            let arm = side == .left
                ? [BodyJoint.leftShoulder, .leftElbow, .leftWrist]
                : [.rightShoulder, .rightElbow, .rightWrist]
            let body = side == .left
                ? [BodyJoint.leftShoulder, .leftHip, .leftAnkle]
                : [.rightShoulder, .rightHip, .rightAnkle]

            guard let shoulder = frame.sample(arm[0]),
                  let elbow = frame.sample(arm[1]),
                  let wrist = frame.sample(arm[2]),
                  let angle = PoseGeometry.angle(a: shoulder.position, b: elbow.position, c: wrist.position, aspectRatio: aspect) else {
                let missing = arm.filter { frame.sample($0) == nil }
                branches.append((side, 0, nil, 0, missing))
                continue
            }

            let alignment: Double? = {
                guard let s = frame.point(body[0]), let h = frame.point(body[1]), let a = frame.point(body[2]) else { return nil }
                return PoseGeometry.angle(a: s, b: h, c: a, aspectRatio: aspect)
            }()
            let confidence = min(shoulder.confidence, min(elbow.confidence, wrist.confidence))
            branches.append((side, angle, alignment, confidence, []))
        }

        guard let best = branches.max(by: { $0.confidence < $1.confidence }), best.confidence > 0 else {
            let missing = AnalyzerSupport.legJoints(for: .left).filter { frame.sample($0) == nil }
            return .unavailable(
                exercise: exercise,
                frame: frame,
                missing: missing,
                note: "Your arm and body line are not visible. Reposition the phone side-on at floor level."
            )
        }

        let signal = PoseGeometry.progress(value: best.elbowAngle, start: topAngle, end: bottomAngle)
        let reliable = best.confidence >= AnalyzerSupport.reliableJointConfidence
            && frame.bodyConfidence >= AnalyzerSupport.minimumBodyConfidence
        let reliability: AnalysisReliability = reliable && best.alignment != nil ? .reliable : .limited
        let note: String? = best.alignment == nil
            ? "Your hips or feet are partly out of frame, so body alignment cannot be measured. Reps can still count."
            : nil

        return MovementAnalysis(
            exercise: exercise,
            timestamp: frame.timestamp,
            signal: signal,
            signalConfidence: best.confidence,
            reliability: reliability,
            metrics: MovementMetrics(
                elbowAngle: best.elbowAngle,
                bodyAlignmentAngle: best.alignment,
                activeSide: best.side
            ),
            missingJoints: [],
            framingNote: note
        )
    }
}

// MARK: - Lunge

final class LungeMovementAnalyzer: ExerciseMovementAnalyzing {
    let exercise = FormAnalysisExercise.lunge

    private let topAngle: Double = 165
    private let bottomAngle: Double = 90

    func analyze(_ frame: PoseFrame) -> MovementAnalysis {
        if frame.hasAmbiguousPeople {
            return .unavailable(
                exercise: exercise,
                frame: frame,
                missing: [],
                note: "More than one person is visible. Make sure you are alone in the frame."
            )
        }
        if frame.usableJointCount == 0 {
            return .unavailable(
                exercise: exercise,
                frame: frame,
                missing: [],
                note: "No body detected. Step back so both legs and your hips are visible."
            )
        }

        guard let left = AnalyzerSupport.legChain(in: frame, side: .left),
              let right = AnalyzerSupport.legChain(in: frame, side: .right) else {
            let side: BodySide = AnalyzerSupport.legChain(in: frame, side: .left) == nil ? .left : .right
            let missing = AnalyzerSupport.legJoints(for: side).filter { frame.sample($0) == nil }
            return .unavailable(
                exercise: exercise,
                frame: frame,
                missing: missing,
                note: "Lunge analysis needs both legs visible. \(MissingJointSummary.note(for: missing, in: frame) ?? "Reposition the camera side-on.")"
            )
        }

        let aspect = frame.imageAspectRatio
        guard let leftAngle = PoseGeometry.angle(a: left.hip, b: left.knee, c: left.ankle, aspectRatio: aspect),
              let rightAngle = PoseGeometry.angle(a: right.hip, b: right.knee, c: right.ankle, aspectRatio: aspect) else {
            return .unavailable(exercise: exercise, frame: frame, missing: [], note: "Knee positions could not be measured from this angle.")
        }

        let front = leftAngle <= rightAngle
            ? (side: BodySide.left, angle: leftAngle)
            : (side: BodySide.right, angle: rightAngle)
        let signal = PoseGeometry.progress(value: front.angle, start: topAngle, end: bottomAngle)
        let confidence = min(left.confidence, right.confidence)
        let torso = AnalyzerSupport.torsoAngle(in: frame, preferredSide: front.side)

        let reliable = confidence >= AnalyzerSupport.reliableJointConfidence
            && frame.bodyConfidence >= AnalyzerSupport.minimumBodyConfidence
        let reliability: AnalysisReliability = reliable && torso != nil ? .reliable : .limited

        return MovementAnalysis(
            exercise: exercise,
            timestamp: frame.timestamp,
            signal: signal,
            signalConfidence: confidence,
            reliability: reliability,
            metrics: MovementMetrics(
                kneeAngle: front.angle,
                torsoAngle: torso,
                activeSide: front.side
            ),
            missingJoints: [],
            framingNote: torso == nil && reliable
                ? "Your shoulders are partly out of frame, so torso angle cannot be measured."
                : nil
        )
    }
}

// MARK: - Jumping jack

final class JumpingJackMovementAnalyzer: ExerciseMovementAnalyzing {
    let exercise = FormAnalysisExercise.jumpingJack

    private let armTop: Double = 0.55
    private let armBottom: Double = -0.10
    private let legClosed: Double = 1.0
    private let legOpen: Double = 1.8

    func analyze(_ frame: PoseFrame) -> MovementAnalysis {
        if frame.hasAmbiguousPeople {
            return .unavailable(
                exercise: exercise,
                frame: frame,
                missing: [],
                note: "More than one person is visible. Make sure you are alone in the frame."
            )
        }
        if frame.usableJointCount == 0 {
            return .unavailable(
                exercise: exercise,
                frame: frame,
                missing: [],
                note: "No body detected. Stand further back so your hands and feet stay in frame."
            )
        }

        let needed: [BodyJoint] = [.leftShoulder, .rightShoulder, .leftWrist, .rightWrist,
                                   .leftHip, .rightHip, .leftAnkle, .rightAnkle]
        let missing = needed.filter { frame.sample($0) == nil }
        guard missing.isEmpty,
              let leftShoulder = frame.point(.leftShoulder),
              let rightShoulder = frame.point(.rightShoulder),
              let leftWrist = frame.point(.leftWrist),
              let rightWrist = frame.point(.rightWrist),
              let leftHip = frame.point(.leftHip),
              let rightHip = frame.point(.rightHip),
              let leftAnkle = frame.point(.leftAnkle),
              let rightAnkle = frame.point(.rightAnkle) else {
            return .unavailable(
                exercise: exercise,
                frame: frame,
                missing: missing,
                note: MissingJointSummary.note(for: missing, in: frame)
            )
        }

        let aspect = frame.imageAspectRatio
        let shoulderMid = PoseGeometry.midpoint(leftShoulder, rightShoulder)
        let hipMid = PoseGeometry.midpoint(leftHip, rightHip)
        let torso = PoseGeometry.distance(shoulderMid, hipMid, aspectRatio: aspect)
        let hipWidth = PoseGeometry.distance(leftHip, rightHip, aspectRatio: aspect)
        guard torso > 0.01, hipWidth > 0.01 else {
            return .unavailable(exercise: exercise, frame: frame, missing: [], note: "Body proportions could not be measured from this angle.")
        }

        let wristMid = PoseGeometry.midpoint(leftWrist, rightWrist)
        let armRaise = (wristMid.y - shoulderMid.y) / torso
        let legSpread = PoseGeometry.ratio(
            PoseGeometry.distance(leftAnkle, rightAnkle, aspectRatio: aspect),
            to: hipWidth
        )

        let armProgress = PoseGeometry.progress(value: armRaise, start: armBottom, end: armTop)
        let legProgress = PoseGeometry.progress(value: legSpread, start: legClosed, end: legOpen)
        let signal = min(armProgress, legProgress)

        let confidences = needed.compactMap { frame.joints[$0]?.confidence }
        let confidence = AnalyzerSupport.totalConfidence(confidences)
        let reliable = confidence >= AnalyzerSupport.reliableJointConfidence
            && frame.bodyConfidence >= AnalyzerSupport.minimumBodyConfidence
        let reliability: AnalysisReliability = reliable ? .reliable : .limited

        return MovementAnalysis(
            exercise: exercise,
            timestamp: frame.timestamp,
            signal: signal,
            signalConfidence: confidence,
            reliability: reliability,
            metrics: MovementMetrics(
                armRaiseRatio: armRaise,
                legSeparationRatio: legSpread
            ),
            missingJoints: [],
            framingNote: reliable ? nil : "Some joints are low confidence. Improve the lighting and keep your whole body in frame."
        )
    }
}

enum ExerciseAnalyzerFactory {
    static func make(for exercise: FormAnalysisExercise) -> ExerciseMovementAnalyzing {
        switch exercise {
        case .squat: return SquatMovementAnalyzer()
        case .pushUp: return PushUpMovementAnalyzer()
        case .lunge: return LungeMovementAnalyzer()
        case .jumpingJack: return JumpingJackMovementAnalyzer()
        }
    }
}
