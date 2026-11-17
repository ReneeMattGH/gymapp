import Foundation
import XCTest
@testable import Forma

final class FormAnalysisPersistenceTests: XCTestCase {
    private let startedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func summary(
        repCount: Int? = 12,
        reliable: Bool = true,
        coverage: Double? = 0.8,
        interruptions: Int = 2,
        observations: [FormObservation] = []
    ) -> FormAnalysisSessionSummary {
        FormAnalysisSessionSummary(
            exercise: .squat,
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(75),
            duration: 75,
            repCount: repCount,
            repCountingReliable: reliable,
            coverage: coverage,
            observations: observations,
            limitations: ["Single 2D camera view.", "Not a medical assessment."],
            cameraPosition: .front,
            trackingInterruptions: interruptions
        )
    }

    private func measuredObservation() -> FormObservation {
        FormObservation(
            id: "rep-1-squat-angle",
            status: .reliable,
            text: "Rep 1: your knee angle reached about 96° at the lowest point.",
            joints: [.leftHip, .leftKnee, .leftAnkle],
            limitation: "Measured from a single 2D camera view.",
            timestamp: 10,
            kind: .rep,
            exercise: .squat,
            measurements: ["minimumKneeAngle": 96]
        )
    }

    func testAvailabilityFollowsTrackingQuality() {
        XCTAssertEqual(summary(repCount: 4, reliable: true).availability, .reliable)
        XCTAssertEqual(summary(repCount: nil, reliable: false, coverage: 0.3).availability, .limited)
        XCTAssertEqual(summary(repCount: nil, reliable: false, coverage: nil).availability, .unavailable)
        XCTAssertEqual(summary(repCount: nil, reliable: false, coverage: 0).availability, .unavailable)
    }

    func testRecordKeepsMeasuredObservationsAndValues() {
        let record = FormAnalysisSavedSession.record(
            for: summary(observations: [measuredObservation()]),
            sessionID: "session-1"
        )

        XCTAssertEqual(record.sessionID, "session-1")
        XCTAssertEqual(record.repCount, 12)
        XCTAssertEqual(record.availability, .reliable)
        XCTAssertEqual(record.coverage ?? -1, 0.8, accuracy: 0.0001)
        XCTAssertEqual(record.trackingInterruptions, 2)
        XCTAssertEqual(record.exercise, .squat)
        XCTAssertEqual(record.observations.count, 1)
        XCTAssertEqual(record.observations[0].measurements["minimumKneeAngle"], 96)
        XCTAssertEqual(record.observations[0].formObservation.measurementSummary, "knee 96°")
    }

    func testSavedSessionStoresRepsInRecordNotSets() {
        let session = FormAnalysisSavedSession.workoutSession(
            for: summary(observations: [measuredObservation()]),
            sessionID: "session-2",
            userId: "user-1"
        )

        XCTAssertEqual(session.id, "session-2")
        XCTAssertEqual(session.userId, "user-1")
        XCTAssertTrue(session.sets.isEmpty)
        XCTAssertEqual(session.status, .completed)
        XCTAssertEqual(session.formAnalysis?.repCount, 12)
        XCTAssertEqual(session.formAnalysis?.observations.count, 1)
        XCTAssertNil(session.planDayId)
        XCTAssertTrue(session.title.contains("form check"))
        XCTAssertTrue(session.notes?.contains("12 reps counted") == true)
    }

    func testSessionRepsAddsFormCountWithoutDoubleCounting() {
        let formSession = FormAnalysisSavedSession.workoutSession(
            for: summary(repCount: 9),
            sessionID: "session-3",
            userId: "user-1"
        )

        var setSession = WorkoutSession(
            id: "session-4",
            userId: "user-1",
            planDayId: nil,
            title: "Lower body",
            focus: [],
            startedAt: startedAt,
            endedAt: startedAt.addingTimeInterval(60),
            durationSeconds: 60,
            status: .completed,
            sets: [
                CompletedSet(
                    id: "set-1",
                    sessionId: "session-4",
                    workoutExerciseId: nil,
                    exerciseId: "squat",
                    setNumber: 1,
                    reps: 5,
                    weightKg: nil,
                    completedAt: startedAt
                )
            ],
            notes: nil
        )

        XCTAssertEqual(TrainingStats.sessionReps(formSession), 9)
        XCTAssertEqual(TrainingStats.sessionReps(setSession), 5)

        setSession.formAnalysis = formSession.formAnalysis
        XCTAssertEqual(TrainingStats.sessionReps(setSession), 14)
    }

    func testUnreliableSummaryHasNoStoredCount() {
        let session = FormAnalysisSavedSession.workoutSession(
            for: summary(repCount: nil, reliable: false, coverage: 0.2),
            sessionID: "session-5",
            userId: "user-1"
        )

        XCTAssertNil(session.formAnalysis?.repCount)
        XCTAssertEqual(session.formAnalysis?.availability, .limited)
        XCTAssertEqual(TrainingStats.sessionReps(session), 0)
        XCTAssertTrue(session.notes?.contains("Rep counting unavailable") == true)
    }

    func testQueuedSessionRoundTripsThroughLocalStore() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("forma-persistence-\(UUID().uuidString)", isDirectory: true)
        let store = LocalStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let userId = "user-\(UUID().uuidString)"
        let session = FormAnalysisSavedSession.workoutSession(
            for: summary(observations: [measuredObservation()]),
            sessionID: "session-6",
            userId: userId
        )

        await store.enqueuePendingFormSession(session, userId: userId)
        await store.enqueuePendingFormSession(session, userId: userId)

        let queued = await store.pendingFormSessions(userId: userId)
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued[0], session)
        XCTAssertEqual(queued[0].formAnalysis?.observations[0].measurements["minimumKneeAngle"], 96)

        await store.removePendingFormSession(id: session.id, userId: userId)
        let remaining = await store.pendingFormSessions(userId: userId)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testQueuesAreScopedPerUser() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("forma-persistence-\(UUID().uuidString)", isDirectory: true)
        let store = LocalStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = FormAnalysisSavedSession.workoutSession(
            for: summary(),
            sessionID: "session-a",
            userId: "user-a"
        )
        let second = FormAnalysisSavedSession.workoutSession(
            for: summary(),
            sessionID: "session-b",
            userId: "user-b"
        )

        await store.enqueuePendingFormSession(first, userId: "user-a")
        await store.enqueuePendingFormSession(second, userId: "user-b")

        let firstQueue = await store.pendingFormSessions(userId: "user-a")
        let secondQueue = await store.pendingFormSessions(userId: "user-b")
        XCTAssertEqual(firstQueue.map(\.id), ["session-a"])
        XCTAssertEqual(secondQueue.map(\.id), ["session-b"])
    }

    func testLegacySessionJSONDecodesWithoutFormAnalysis() throws {
        let json = """
        {
          "id": "legacy",
          "userId": "user-1",
          "title": "Upper body",
          "focus": [],
          "startedAt": 0,
          "durationSeconds": 30,
          "status": "completed",
          "sets": []
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let session = try decoder.decode(WorkoutSession.self, from: Data(json.utf8))
        XCTAssertNil(session.formAnalysis)
    }
}
