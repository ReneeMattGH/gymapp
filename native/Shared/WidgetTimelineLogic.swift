import Foundation

/// Small, pure helpers shared by the timeline provider and the views so widget
/// refresh behaviour is unit-testable outside WidgetKit.
enum WidgetTimelineLogic {
    static func nextDayBoundary(after date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start)
            ?? date.addingTimeInterval(60 * 60)
    }

    /// Widgets refresh at the next day boundary so the "today" state and the
    /// seven-day strip roll over without polling. The app also reloads the
    /// timeline whenever real training or Community data changes.
    static func nextRefreshDate(after date: Date, calendar: Calendar = .current) -> Date {
        nextDayBoundary(after: date, calendar: calendar)
    }

    static func freshnessLabel(generatedAt: Date, now: Date) -> String {
        let interval = max(0, now.timeIntervalSince(generatedAt))
        if interval < 60 { return "Updated just now" }
        if interval < 3600 { return "Updated \(Int(interval / 60)) min ago" }
        if interval < 86_400 { return "Updated \(Int(interval / 3600)) hr ago" }
        let days = Int(interval / 86_400)
        return days == 1 ? "Updated yesterday" : "Updated \(days) days ago"
    }

    static func isStale(generatedAt: Date, now: Date, threshold: TimeInterval = 12 * 60 * 60) -> Bool {
        now.timeIntervalSince(generatedAt) > threshold
    }
}
