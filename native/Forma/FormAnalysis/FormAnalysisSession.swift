import Foundation

enum FormAnalysisAvailability: String, Codable, Equatable, Sendable {
    case reliable, limited, unavailable

    var label: String {
        switch self {
        case .reliable: return "Reliable"
        case .limited: return "Limited"
        case .unavailable: return "Unavailable"
        }
    }
}

/// How a finished session was persisted. `queued` means the record is on this
/// device and will be retried when the backend can be reached.
enum FormSessionSaveState: Equatable, Sendable {
    case idle, saving, saved, queued, failed(String)
}

struct FormAnalysisSessionSummary: Identifiable, Equatable, Sendable {
    var id = UUID()
    var exercise: FormAnalysisExercise
    var startedAt: Date
    var endedAt: Date
    var duration: TimeInterval
    /// nil when no reliable tracking was available, so no count is presented.
    var repCount: Int?
    var repCountingReliable: Bool
    /// Share of analysed frames where tracking was reliable, 0...1.
    var coverage: Double?
    var observations: [FormObservation]
    var limitations: [String]
    var cameraPosition: FormCameraPosition
    var trackingInterruptions: Int = 0

    var availability: FormAnalysisAvailability {
        if repCountingReliable { return .reliable }
        guard let coverage, coverage > 0 else { return .unavailable }
        return .limited
    }
}

/// The persisted form of a measured observation. Keys are stable because they
/// are written to the `observations` jsonb column.
struct StoredFormObservation: Codable, Equatable, Sendable {
    var id: String
    var status: FeedbackStatus
    var text: String
    var joints: [BodyJoint]
    var limitation: String?
    var timestamp: TimeInterval
    var kind: ObservationKind
    var exercise: FormAnalysisExercise?
    var measurements: [String: Double]

    init(_ observation: FormObservation) {
        id = observation.id
        status = observation.status
        text = observation.text
        joints = observation.joints
        limitation = observation.limitation
        timestamp = observation.timestamp
        kind = observation.kind
        exercise = observation.exercise
        measurements = observation.measurements
    }

    var formObservation: FormObservation {
        FormObservation(
            id: id,
            status: status,
            text: text,
            joints: joints,
            limitation: limitation,
            timestamp: timestamp,
            kind: kind,
            exercise: exercise,
            measurements: measurements
        )
    }
}

/// The minimal structured record sent to (or stored with) the workout session.
/// It contains no images, frames or keypoint histories.
struct FormAnalysisRecord: Codable, Equatable, Sendable {
    var sessionID: String
    var exercise: FormAnalysisExercise
    var exerciseID: String?
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: Int
    var repCount: Int?
    var availability: FormAnalysisAvailability
    var coverage: Double?
    var trackingInterruptions: Int
    var observations: [StoredFormObservation]
    var limitations: [String]
    var cameraPosition: FormCameraPosition

    init(
        sessionID: String,
        exercise: FormAnalysisExercise,
        exerciseID: String?,
        startedAt: Date,
        endedAt: Date,
        durationSeconds: Int,
        repCount: Int?,
        availability: FormAnalysisAvailability,
        coverage: Double?,
        trackingInterruptions: Int,
        observations: [StoredFormObservation],
        limitations: [String],
        cameraPosition: FormCameraPosition
    ) {
        self.sessionID = sessionID
        self.exercise = exercise
        self.exerciseID = exerciseID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSeconds = durationSeconds
        self.repCount = repCount
        self.availability = availability
        self.coverage = coverage
        self.trackingInterruptions = trackingInterruptions
        self.observations = observations
        self.limitations = limitations
        self.cameraPosition = cameraPosition
    }

    init(summary: FormAnalysisSessionSummary, sessionID: String) {
        self.sessionID = sessionID
        self.exercise = summary.exercise
        self.exerciseID = summary.exercise.catalogID
        self.startedAt = summary.startedAt
        self.endedAt = summary.endedAt
        self.durationSeconds = max(0, Int(summary.duration.rounded()))
        self.repCount = summary.repCount
        self.availability = summary.availability
        self.coverage = summary.coverage
        self.trackingInterruptions = max(0, summary.trackingInterruptions)
        self.observations = summary.observations.map(StoredFormObservation.init)
        self.limitations = summary.limitations
        self.cameraPosition = summary.cameraPosition
    }
}

enum FormAnalysisSavedSession {
    static func record(for summary: FormAnalysisSessionSummary, sessionID: String) -> FormAnalysisRecord {
        FormAnalysisRecord(summary: summary, sessionID: sessionID)
    }

    static func workoutSession(
        for summary: FormAnalysisSessionSummary,
        sessionID: String,
        userId: String
    ) -> WorkoutSession {
        WorkoutSession(
            id: sessionID,
            userId: userId,
            planDayId: nil,
            title: "\(summary.exercise.shortTitle) · form check",
            focus: [],
            startedAt: summary.startedAt,
            endedAt: summary.endedAt,
            durationSeconds: max(0, Int(summary.duration.rounded())),
            status: .completed,
            sets: [],
            notes: notes(for: summary),
            formAnalysis: record(for: summary, sessionID: sessionID)
        )
    }

    private static func notes(for summary: FormAnalysisSessionSummary) -> String {
        var parts = ["On-device camera form check."]
        if let count = summary.repCount {
            parts.append("\(count) rep\(count == 1 ? "" : "s") counted.")
        } else {
            parts.append("Rep counting unavailable.")
        }
        if let coverage = summary.coverage {
            parts.append("\(Int((coverage * 100).rounded()))% of analysed frames were reliable.")
        }
        return parts.joined(separator: " ")
    }
}

final class FormAnalysisSessionRecorder {
    let exercise: FormAnalysisExercise
    let cameraPosition: FormCameraPosition
    let startedAt: Date

    private(set) var analyzedFrames = 0
    private(set) var reliableFrames = 0
    private(set) var reps: [RepObservation] = []
    private(set) var observations: [FormObservation] = []

    init(exercise: FormAnalysisExercise, cameraPosition: FormCameraPosition, startedAt: Date = Date()) {
        self.exercise = exercise
        self.cameraPosition = cameraPosition
        self.startedAt = startedAt
    }

    func record(frame analysis: MovementAnalysis) {
        analyzedFrames += 1
        if analysis.reliability == .reliable {
            reliableFrames += 1
        }
    }

    func record(rep: RepObservation) {
        reps.append(rep)
    }

    func record(observations newObservations: [FormObservation]) {
        observations.append(contentsOf: newObservations)
    }

    func summary(endedAt: Date = Date(), repCount: Int, trackingInterruptions: Int = 0) -> FormAnalysisSessionSummary {
        let coverage: Double? = analyzedFrames > 0
            ? Double(reliableFrames) / Double(analyzedFrames)
            : nil
        let reliable = reliableFrames > 0 && (coverage ?? 0) >= 0.5
        let presentedCount: Int? = reliableFrames > 0 ? repCount : nil

        var limitations = [
            "Single 2D camera view. Joint angles are estimates and change with camera position, clothing and lighting.",
            "This feature measures visible movement only. It does not measure muscle activity, joint loading or injury risk, and it is not a medical assessment.",
            "On-device pose analysis has not been validated on a physical device in this build."
        ]
        if let coverage, coverage < 0.5, analyzedFrames > 0 {
            limitations.insert(
                "Tracking was reliable for \(Int((coverage * 100).rounded()))% of analysed frames, so the rep count may be incomplete.",
                at: 0
            )
        }
        if reliableFrames > 0 && repCount == 0 {
            limitations.insert("No complete repetitions were counted in this session.", at: 0)
        }

        let keyObservations = observations
            .filter { $0.status != .unavailable }
            .suffix(6)

        return FormAnalysisSessionSummary(
            exercise: exercise,
            startedAt: startedAt,
            endedAt: endedAt,
            duration: max(0, endedAt.timeIntervalSince(startedAt)),
            repCount: presentedCount,
            repCountingReliable: reliable,
            coverage: coverage,
            observations: Array(keyObservations),
            limitations: limitations,
            cameraPosition: cameraPosition,
            trackingInterruptions: max(0, trackingInterruptions)
        )
    }
}

