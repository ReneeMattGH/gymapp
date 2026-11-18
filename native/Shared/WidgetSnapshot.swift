import Foundation

enum FormaWidgetKind {
    static let identifier = "FormaFitnessWidget"
    static let displayName = "Fitness Command Center"
}

/// The compact, account-scoped snapshot the main app writes and the widget
/// extension reads. It deliberately contains no free text from Community, no
/// health data, and no location.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var generatedAt: Date
    var accountID: String
    var isPreview: Bool
    var hasPlan: Bool
    var totalCompleted: Int
    var totalReps: Int
    var streak: Int
    var lastSessionAt: Date?
    var today: WidgetTodaySummary
    var week: WidgetWeekSummary
    var community: WidgetCommunitySummary?

    /// A neutral snapshot used by the widget gallery placeholder and by any
    /// launch where the app has never written real data. No fabricated metrics.
    static func empty(now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        let start = Self.weekStart(for: now, calendar: calendar)
        let days = (0..<7).map { offset in
            WidgetWeekDay(
                date: calendar.date(byAdding: .day, value: offset, to: start) ?? start,
                completedCount: 0,
                minutes: 0
            )
        }
        return WidgetSnapshot(
            schemaVersion: currentSchemaVersion,
            generatedAt: now,
            accountID: "",
            isPreview: false,
            hasPlan: false,
            totalCompleted: 0,
            totalReps: 0,
            streak: 0,
            lastSessionAt: nil,
            today: WidgetTodaySummary(
                state: .noPlan,
                title: nil,
                focus: [],
                exerciseCount: 0,
                setCount: 0,
                estimatedMinutes: 0,
                completedTitle: nil,
                activeSessionTitle: nil,
                nextTitle: nil,
                nextWeekday: nil
            ),
            week: WidgetWeekSummary(
                start: start,
                goal: 0,
                completed: 0,
                minutes: 0,
                days: days
            ),
            community: nil
        )
    }

    static func weekStart(for date: Date, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    func weekDay(on date: Date, calendar: Calendar = .current) -> WidgetWeekDay? {
        week.days.first { calendar.isDate($0.date, inSameDayAs: date) }
    }
}

enum WidgetTodayState: String, Codable, Sendable {
    case workout
    case completed
    case inProgress
    case rest
    case notScheduled
    case noPlan
}

struct WidgetTodaySummary: Codable, Equatable, Sendable {
    var state: WidgetTodayState
    var title: String?
    var focus: [String]
    var exerciseCount: Int
    var setCount: Int
    var estimatedMinutes: Int
    /// Title of a session actually completed today, when one exists.
    var completedTitle: String?
    /// Title of an unfinished workout the user already started.
    var activeSessionTitle: String?
    var nextTitle: String?
    /// ISO weekday (1 = Monday … 7 = Sunday) for the next non-rest day.
    var nextWeekday: Int?
}

struct WidgetWeekDay: Codable, Equatable, Identifiable, Sendable {
    var date: Date
    var completedCount: Int
    var minutes: Int

    var id: Date { date }
    var didTrain: Bool { completedCount > 0 }
}

struct WidgetWeekSummary: Codable, Equatable, Sendable {
    var start: Date
    var goal: Int
    var completed: Int
    var minutes: Int
    var days: [WidgetWeekDay]

    var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(completed) / Double(goal), 1)
    }

    var remaining: Int {
        max(0, goal - completed)
    }

    var hasActivity: Bool {
        days.contains { $0.didTrain }
    }
}

/// Counts only. The widget never receives message bodies, member identities,
/// gym details, or notification text.
struct WidgetCommunitySummary: Codable, Equatable, Sendable {
    var pendingRequests: Int
    var unreadMessages: Int
    var unreadNotifications: Int
    var updatedAt: Date

    var hasAny: Bool {
        pendingRequests > 0 || unreadMessages > 0 || unreadNotifications > 0
    }
}
