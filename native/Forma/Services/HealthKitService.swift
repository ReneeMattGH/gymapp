import Foundation
import HealthKit

struct HealthHeartSample {
    let bpm: Double
    let date: Date
}

struct HealthWorkout: Identifiable {
    let id: UUID
    let activity: String
    let start: Date
    let duration: TimeInterval
    let energyKcal: Double?
}

struct HealthSummary {
    let workouts: [HealthWorkout]
    let activeEnergyKcal: Double?
    let steps: Int?
    let latestHeartRate: HealthHeartSample?
    let fetchedAt: Date
}

enum HealthAvailability {
    case unavailable
    case ready
}

/// Read-only Health access. HealthKit does not reveal read authorization, so
/// the UI must not claim "connected" — it reports whether a fetch returned data.
final class HealthKitService {
    static let shared = HealthKitService()

    private let store = HKHealthStore()
    private let readTypes: Set<HKObjectType> = {
        var types = Set<HKObjectType>()
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) { types.insert(steps) }
        if let heart = HKObjectType.quantityType(forIdentifier: .heartRate) { types.insert(heart) }
        types.insert(HKObjectType.workoutType())
        return types
    }()

    var availability: HealthAvailability {
        HKHealthStore.isHealthDataAvailable() ? .ready : .unavailable
    }

    func requestAuthorization() async throws -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw FormaError.message("HealthKit is not available on this device.")
        }
        do {
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return true
        } catch {
            throw FormaError.message("Health access could not be requested: \(error.localizedDescription)")
        }
    }

    /// Fetches the last `days` of activity. Returns nil values when no samples exist.
    func fetchSummary(days: Int = 7) async throws -> HealthSummary {
        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -max(1, days), to: end) ?? end
        return try await summary(from: start, to: end)
    }

    /// Fetches only today's samples, for the dashboard's today's-performance card.
    func fetchToday() async throws -> HealthSummary {
        let end = Date()
        let start = Calendar.current.startOfDay(for: end)
        return try await summary(from: start, to: end)
    }

    private func summary(from start: Date, to end: Date) async throws -> HealthSummary {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw FormaError.message("HealthKit is not available on this device.")
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        async let workouts = fetchWorkouts(predicate: predicate)
        async let energy = fetchSum(.activeEnergyBurned, unit: .kilocalorie(), predicate: predicate)
        async let steps = fetchSum(.stepCount, unit: .count(), predicate: predicate)
        async let heart = fetchLatestHeartRate(predicate: predicate)

        let workoutRows = try await workouts
        let energyTotal = try await energy
        let stepTotal = try await steps
        let heartSample = try await heart

        return HealthSummary(
            workouts: workoutRows,
            activeEnergyKcal: energyTotal,
            steps: stepTotal.map { Int($0.rounded()) },
            latestHeartRate: heartSample,
            fetchedAt: Date()
        )
    }

    private func fetchWorkouts(predicate: NSPredicate) async throws -> [HealthWorkout] {
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 20
        )
        let samples = try await descriptor.result(for: store)
        let energyType = HKQuantityType(.activeEnergyBurned)
        return samples.map { workout in
            let energy = workout.statistics(for: energyType)?
                .sumQuantity()?
                .doubleValue(for: .kilocalorie())
            return HealthWorkout(
                id: workout.uuid,
                activity: Self.name(for: workout.workoutActivityType),
                start: workout.startDate,
                duration: workout.duration,
                energyKcal: energy
            )
        }
    }

    private func fetchSum(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, predicate: NSPredicate) async throws -> Double? {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return nil }
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: .cumulativeSum
        )
        let statistics = try await descriptor.result(for: store)
        return statistics?.sumQuantity()?.doubleValue(for: unit)
    }

    private func fetchLatestHeartRate(predicate: NSPredicate) async throws -> HealthHeartSample? {
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return nil }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: type, predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        let samples = try await descriptor.result(for: store)
        guard let sample = samples.first else { return nil }
        return HealthHeartSample(
            bpm: sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())),
            date: sample.endDate
        )
    }

    private static func name(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining: "Strength training"
        case .functionalStrengthTraining: "Functional strength"
        case .highIntensityIntervalTraining: "HIIT"
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .yoga: "Yoga"
        case .flexibility: "Mobility"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .coreTraining: "Core training"
        case .mixedCardio: "Mixed cardio"
        case .other: "Workout"
        default: "Workout"
        }
    }
}
