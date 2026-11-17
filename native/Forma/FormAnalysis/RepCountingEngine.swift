import Foundation

enum RepPhase: String, Equatable, Sendable {
    case ready, descending, bottom, ascending
}

struct RepCountingConfiguration: Equatable, Sendable {
    /// Signal level (0 = extended, 1 = fully contracted) at which a rep may begin.
    var startThreshold: Double = 0.18
    /// Signal level that counts as the bottom of the movement.
    var bottomThreshold: Double = 0.72
    /// Signal must fall below this before the ascent is recognised (hysteresis).
    var bottomExitThreshold: Double = 0.55
    /// Signal level at which a rep ends.
    var returnThreshold: Double = 0.20
    var minimumRepDuration: TimeInterval = 0.9
    var maximumRepDuration: TimeInterval = 8
    var minimumBottomHold: TimeInterval = 0.06
    var minimumTimeBetweenReps: TimeInterval = 0.35
    var minimumConfidence: Double = 0.55
    /// The movement must start from a settled top position.
    var stableStartDuration: TimeInterval = 0.35
}

struct CompletedRepBoundary: Equatable, Sendable {
    var index: Int
    var startedAt: TimeInterval
    var bottomedAt: TimeInterval
    var completedAt: TimeInterval
    var minimumSignal: Double
    var maximumSignal: Double
}

struct RepUpdate: Equatable, Sendable {
    var phase: RepPhase
    var count: Int
    var completed: CompletedRepBoundary?
    /// True on the update where an in-flight or attempted rep was discarded.
    var rejectedIncompleteRep: Bool
    /// True when pose confidence/tracking was too low to evaluate this frame.
    var suspended: Bool
}

/// Exercise-agnostic repetition state machine driven by a normalised 0...1 signal.
/// It only counts a complete top → bottom → top cycle that is deep enough, slow
/// enough, held briefly at the bottom, and completed after a settled start.
final class RepCountingEngine {
    private(set) var configuration: RepCountingConfiguration
    private(set) var count: Int = 0
    private(set) var phase: RepPhase = .ready
    private(set) var lastCompletedRep: CompletedRepBoundary?

    private var lastTimestamp: TimeInterval?
    private var stableSince: TimeInterval?
    private var armed = false
    private var lastCompletionTime: TimeInterval?
    private var wasSuspended = false

    private var repStart: TimeInterval = 0
    private var bottomEnteredAt: TimeInterval = 0
    private var bottomConfirmed = false
    private var repMinimum: Double = 1
    private var repMaximum: Double = 0

    init(configuration: RepCountingConfiguration = RepCountingConfiguration()) {
        self.configuration = configuration
    }

    /// Clears in-flight state. The count is preserved unless `keepingCount` is false.
    func reset(keepingCount: Bool = true) {
        phase = .ready
        stableSince = nil
        armed = false
        bottomConfirmed = false
        repMinimum = 1
        repMaximum = 0
        lastTimestamp = nil
        wasSuspended = false
        if !keepingCount {
            count = 0
            lastCompletedRep = nil
            lastCompletionTime = nil
        }
    }

    @discardableResult
    func update(signal: Double?, confidence: Double, timestamp: TimeInterval) -> RepUpdate {
        if let previous = lastTimestamp, timestamp < previous {
            return RepUpdate(phase: phase, count: count, completed: nil, rejectedIncompleteRep: false, suspended: wasSuspended)
        }
        lastTimestamp = timestamp

        guard let signal, confidence >= configuration.minimumConfidence, signal.isFinite else {
            return suspend(timestamp: timestamp)
        }
        wasSuspended = false

        let value = min(1, max(0, signal))

        if phase != .ready, timestamp - repStart > configuration.maximumRepDuration {
            resetInFlight()
            return RepUpdate(phase: .ready, count: count, completed: nil, rejectedIncompleteRep: true, suspended: false)
        }

        switch phase {
        case .ready:
            return updateReady(value: value, timestamp: timestamp)
        case .descending:
            return updateDescending(value: value, timestamp: timestamp)
        case .bottom:
            return updateBottom(value: value, timestamp: timestamp)
        case .ascending:
            return updateAscending(value: value, timestamp: timestamp)
        }
    }

    // MARK: - States

    private func updateReady(value: Double, timestamp: TimeInterval) -> RepUpdate {
        if value > configuration.startThreshold {
            guard armed, canStartRep(at: timestamp) else {
                return currentUpdate()
            }
            phase = .descending
            repStart = timestamp
            repMinimum = value
            repMaximum = value
            bottomConfirmed = false
            stableSince = nil
            return currentUpdate()
        }

        if stableSince == nil {
            stableSince = timestamp
        }
        if let stableSince, timestamp - stableSince >= configuration.stableStartDuration {
            armed = true
        }
        return currentUpdate()
    }

    private func updateDescending(value: Double, timestamp: TimeInterval) -> RepUpdate {
        repMinimum = min(repMinimum, value)
        repMaximum = max(repMaximum, value)

        if value >= configuration.bottomThreshold {
            phase = .bottom
            bottomEnteredAt = timestamp
            bottomConfirmed = false
            return currentUpdate()
        }

        if value <= configuration.startThreshold {
            return rejectAndReset()
        }
        return currentUpdate()
    }

    private func updateBottom(value: Double, timestamp: TimeInterval) -> RepUpdate {
        repMinimum = min(repMinimum, value)
        repMaximum = max(repMaximum, value)

        if value >= configuration.bottomExitThreshold {
            if !bottomConfirmed, timestamp - bottomEnteredAt >= configuration.minimumBottomHold {
                bottomConfirmed = true
            }
            return currentUpdate()
        }

        if bottomConfirmed {
            phase = .ascending
            return currentUpdate()
        }

        // Dropped out of the bottom zone without ever pausing there. Give the
        // movement a chance to return to the top so it can be rejected cleanly.
        if value <= configuration.startThreshold {
            return rejectAndReset()
        }
        return currentUpdate()
    }

    private func updateAscending(value: Double, timestamp: TimeInterval) -> RepUpdate {
        repMinimum = min(repMinimum, value)
        repMaximum = max(repMaximum, value)

        guard value <= configuration.returnThreshold else {
            return currentUpdate()
        }

        let duration = timestamp - repStart
        let reachedDepth = repMaximum >= configuration.bottomThreshold
        guard bottomConfirmed, reachedDepth, duration >= configuration.minimumRepDuration else {
            return rejectAndReset()
        }

        count += 1
        let boundary = CompletedRepBoundary(
            index: count,
            startedAt: repStart,
            bottomedAt: bottomEnteredAt,
            completedAt: timestamp,
            minimumSignal: repMinimum,
            maximumSignal: repMaximum
        )
        lastCompletedRep = boundary
        lastCompletionTime = timestamp

        phase = .ready
        stableSince = timestamp
        armed = true
        bottomConfirmed = false
        repMinimum = 1
        repMaximum = 0

        return RepUpdate(phase: phase, count: count, completed: boundary, rejectedIncompleteRep: false, suspended: false)
    }

    // MARK: - Helpers

    private func canStartRep(at timestamp: TimeInterval) -> Bool {
        guard let lastCompletionTime else { return true }
        return timestamp - lastCompletionTime >= configuration.minimumTimeBetweenReps
    }

    private func suspend(timestamp: TimeInterval) -> RepUpdate {
        if phase != .ready {
            resetInFlight()
        }
        stableSince = nil
        armed = false
        wasSuspended = true
        return RepUpdate(phase: phase, count: count, completed: nil, rejectedIncompleteRep: false, suspended: true)
    }

    private func rejectAndReset() -> RepUpdate {
        resetInFlight()
        return RepUpdate(phase: .ready, count: count, completed: nil, rejectedIncompleteRep: true, suspended: false)
    }

    private func resetInFlight() {
        phase = .ready
        stableSince = nil
        armed = false
        bottomConfirmed = false
        repMinimum = 1
        repMaximum = 0
    }

    private func currentUpdate() -> RepUpdate {
        RepUpdate(phase: phase, count: count, completed: nil, rejectedIncompleteRep: false, suspended: false)
    }
}
