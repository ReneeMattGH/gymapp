import Foundation

// MARK: - IDs

enum IDs {
    static func uuid() -> String {
        UUID().uuidString.lowercased()
    }
}

// MARK: - Dates

enum FormaDate {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let withoutFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        if let date = withFractional.date(from: value) { return date }
        if let date = withoutFractional.date(from: value) { return date }
        // Supabase can return offsets without a colon (e.g. +0000).
        let normalised = value.replacingOccurrences(of: " ", with: "T")
        if let date = withFractional.date(from: normalised) { return date }
        if let date = withoutFractional.date(from: normalised) { return date }
        return nil
    }

    static func string(_ date: Date) -> String {
        withFractional.string(from: date)
    }
}

extension JSONDecoder {
    static var forma: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = FormaDate.parse(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognised date: \(raw)"
                )
            }
            return date
        }
        return decoder
    }
}

extension JSONEncoder {
    static var forma: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(FormaDate.string(date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

// MARK: - Display

enum Formatters {
    static func clock(_ seconds: Int) -> String {
        let safe = max(0, seconds)
        let hours = safe / 3600
        let minutes = (safe % 3600) / 60
        let secs = safe % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }

    static func minutesLabel(_ seconds: Int) -> String {
        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    static func duration(minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) hr" : "\(hours) hr \(rest) min"
    }

    static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }

    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated))
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    static func greeting(_ date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 5 { return "Late session" }
        if hour < 12 { return "Good morning" }
        if hour < 17 { return "Good afternoon" }
        return "Good evening"
    }

    static func timeOfDay(_ value: String) -> String {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return value }
        let suffix = hour >= 12 ? "PM" : "AM"
        let display = hour % 12 == 0 ? 12 : hour % 12
        return "\(display):\(String(format: "%02d", minute)) \(suffix)"
    }

    /// Converts a "HH:mm" reminder time into an hour/minute pair.
    static func hourMinute(_ value: String) -> (hour: Int, minute: Int) {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
            return (18, 0)
        }
        return (min(max(hour, 0), 23), min(max(minute, 0), 59))
    }

    static func weekdayFull(_ weekday: Int) -> String {
        let calendar = Calendar.current
        let symbols = calendar.weekdaySymbols
        guard (1...7).contains(weekday) else { return "—" }
        // Calendar weekday symbols start on Sunday; reminders use ISO weekdays.
        let index = weekday == 7 ? 0 : weekday
        return symbols[index]
    }

    /// Weight shown in the user's preferred units. Stored values are always kilograms.
    static func weight(kilograms: Double, units: UnitSystem) -> String {
        if units == .kg {
            let rounded = (kilograms * 10).rounded() / 10
            return rounded == rounded.rounded() ? "\(Int(rounded)) kg" : String(format: "%.1f kg", rounded)
        }
        let pounds = kilograms * 2.2046226218
        let rounded = (pounds * 10).rounded() / 10
        return rounded == rounded.rounded() ? "\(Int(rounded)) lb" : String(format: "%.1f lb", rounded)
    }

    static func bodyWeight(kilograms: Double?, units: UnitSystem) -> String {
        guard let kilograms, kilograms > 0 else { return "—" }
        return weight(kilograms: kilograms, units: units)
    }
}

// MARK: - Training analytics

enum TrainingStats {
    static func startOfWeek(_ reference: Date = Date(), calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: reference)
        return calendar.date(from: components) ?? reference
    }

    static func dateKey(_ date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    static func completedSessions(_ sessions: [WorkoutSession]) -> [WorkoutSession] {
        sessions.filter { $0.status == .completed && $0.endedAt != nil }
    }

    static func sessionsOnDay(_ sessions: [WorkoutSession], date: Date, calendar: Calendar = .current) -> [WorkoutSession] {
        completedSessions(sessions).filter { calendar.isDate($0.startedAt, inSameDayAs: date) }
    }

    static func activeDayKeys(_ sessions: [WorkoutSession], calendar: Calendar = .current) -> Set<Date> {
        Set(completedSessions(sessions).map { calendar.startOfDay(for: $0.startedAt) })
    }

    static func currentWeekCount(_ sessions: [WorkoutSession], reference: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = startOfWeek(reference, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? reference
        return completedSessions(sessions).filter { $0.startedAt >= start && $0.startedAt < end }.count
    }

    struct WeekCount: Identifiable {
        let start: Date
        let value: Int
        var id: Date { start }
        var label: String { start.formatted(.dateTime.day().month(.abbreviated)) }
    }

    static func lastWeeksCounts(_ sessions: [WorkoutSession], weeks: Int, reference: Date = Date(), calendar: Calendar = .current) -> [WeekCount] {
        let currentStart = startOfWeek(reference, calendar: calendar)
        return (0..<weeks).map { index in
            let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1 - index), to: currentStart) ?? currentStart
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            let value = completedSessions(sessions).filter { $0.startedAt >= start && $0.startedAt < end }.count
            return WeekCount(start: start, value: value)
        }
    }

    /// Consecutive calendar days with a completed session, counting back from today or yesterday.
    static func currentStreak(_ sessions: [WorkoutSession], reference: Date = Date(), calendar: Calendar = .current) -> Int {
        let days = activeDayKeys(sessions, calendar: calendar)
        var day = calendar.startOfDay(for: reference)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), days.contains(yesterday) else {
                return 0
            }
            day = yesterday
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    static func totalReps(_ sets: [CompletedSet]) -> Int {
        sets.reduce(0) { $0 + $1.reps }
    }

    /// Form-analysis reps are stored in the analysis record, never as completed
    /// sets, so adding them here cannot double-count.
    static func sessionReps(_ session: WorkoutSession) -> Int {
        totalReps(session.sets) + (session.formAnalysis?.repCount ?? 0)
    }

    static func sessionSubtitle(_ session: WorkoutSession) -> String {
        let base = "\(Formatters.shortDate(session.startedAt)) · \(Formatters.minutesLabel(session.durationSeconds))"
        guard let form = session.formAnalysis else {
            return "\(base) · \(session.sets.count) sets"
        }
        let reps = form.repCount.map { "\($0) reps" } ?? "reps unavailable"
        return "\(base) · \(reps) · form check"
    }
}
