import SwiftUI

enum WidgetLinks {
    static let today = URL(string: "forma://today")!
    static let startWorkout = URL(string: "forma://start-workout")!
    static let workouts = URL(string: "forma://workouts")!
    static let progress = URL(string: "forma://progress")!
    static let community = URL(string: "forma://community")!
    static let connectionRequests = URL(string: "forma://community/requests")!
    static let messages = URL(string: "forma://community/messages")!
}

struct WidgetStateCopy {
    let eyebrow: String
    let title: String
    let detail: String
    let cta: String
    let ctaIcon: String
    let url: URL

    init(snapshot: WidgetSnapshot) {
        let today = snapshot.today
        switch today.state {
        case .workout:
            eyebrow = "TODAY"
            title = today.title ?? "Today's session"
            detail = Self.workoutDetail(today)
            cta = "Start workout"
            ctaIcon = "play.fill"
            url = WidgetLinks.startWorkout
        case .completed:
            eyebrow = "COMPLETE"
            title = today.completedTitle ?? today.title ?? "Workout complete"
            detail = "Done today. Recovery is part of the plan."
            cta = "View progress"
            ctaIcon = "chart.line.uptrend.xyaxis"
            url = WidgetLinks.progress
        case .inProgress:
            eyebrow = "IN PROGRESS"
            title = today.activeSessionTitle ?? today.title ?? "Workout in progress"
            detail = "Tap to pick up where you left off."
            cta = "Resume"
            ctaIcon = "play.fill"
            url = WidgetLinks.today
        case .rest:
            eyebrow = "RECOVERY"
            title = today.title ?? "Rest day"
            detail = today.nextTitle.map { "Next: \($0)" } ?? "Recovery is part of the programme."
            cta = "Open Forma"
            ctaIcon = "arrow.up.right"
            url = WidgetLinks.today
        case .notScheduled:
            eyebrow = "NO SESSION"
            title = "No workout today"
            detail = today.nextTitle.map { "Next: \($0)" } ?? "Nothing scheduled for today."
            cta = "View plan"
            ctaIcon = "calendar"
            url = WidgetLinks.workouts
        case .noPlan:
            eyebrow = "GET STARTED"
            title = "Build your plan"
            detail = "Add your plan in Forma to see today's focus and weekly progress."
            cta = "Open Forma"
            ctaIcon = "arrow.up.right"
            url = WidgetLinks.today
        }
    }

    private static func workoutDetail(_ today: WidgetTodaySummary) -> String {
        if today.estimatedMinutes > 0, today.exerciseCount > 0 {
            return "\(today.estimatedMinutes) min · \(today.exerciseCount) exercises"
        }
        if today.exerciseCount > 0 {
            return "\(today.exerciseCount) exercises"
        }
        return "Planned for today"
    }
}

struct WidgetCTA: View {
    let title: String
    let systemImage: String
    let url: URL
    let palette: WidgetPalette

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(palette.accentInk)
            .padding(.horizontal, 10)
            .frame(height: 27)
            .background(palette.accent, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct WeekProgressBar: View {
    let progress: Double
    let palette: WidgetPalette
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule()
                    .fill(palette.accent)
                    .frame(width: max(0, min(1, progress)) * geometry.size.width)
            }
        }
        .frame(height: height)
    }
}

struct SevenDayChart: View {
    let week: WidgetWeekSummary
    let today: Date
    let palette: WidgetPalette
    var barHeight: CGFloat = 30
    var showsCounts: Bool = false

    private var maximum: Int {
        max(week.goal, week.days.map(\.completedCount).max() ?? 0, 1)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(week.days) { day in
                let isToday = Calendar.current.isDate(day.date, inSameDayAs: today)
                VStack(spacing: 3) {
                    ZStack(alignment: .bottom) {
                        Capsule()
                            .fill(palette.track)
                            .frame(height: barHeight)
                        if day.didTrain {
                            Capsule()
                                .fill(palette.accent)
                                .frame(height: max(barHeight * 0.28, barHeight * CGFloat(day.completedCount) / CGFloat(maximum)))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(width: 9)
                    Text(WidgetText.narrowWeekday(day.date))
                        .font(.system(size: 8.5, weight: isToday ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(isToday ? palette.accentText : palette.textTertiary)
                        .overlay(alignment: .bottom) {
                            if isToday {
                                Circle()
                                    .fill(palette.accentText)
                                    .frame(width: 2.5, height: 2.5)
                                    .offset(y: 3.5)
                            }
                        }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(for: day, isToday: isToday))
            }
        }
    }

    private func accessibilityLabel(for day: WidgetWeekDay, isToday: Bool) -> String {
        let status: String
        if day.didTrain {
            status = "\(day.completedCount) workout\(day.completedCount == 1 ? "" : "s")"
        } else {
            status = "no workout"
        }
        return "\(WidgetText.shortWeekday(day.date)): \(status)\(isToday ? ", today" : "")"
    }
}

struct WeekRing: View {
    let week: WidgetWeekSummary
    let palette: WidgetPalette
    var size: CGFloat = 64
    var lineWidth: CGFloat = 7

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.track, lineWidth: lineWidth)
            if week.goal > 0 {
                Circle()
                    .trim(from: 0, to: week.progress)
                    .stroke(palette.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text(WidgetText.weekFraction(week))
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.text)
                Text("sessions")
                    .font(.system(size: size * 0.11, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.textTertiary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(weekAccessibilityLabel(week))
    }
}

func weekAccessibilityLabel(_ week: WidgetWeekSummary) -> String {
    guard week.goal > 0 else { return "No weekly goal set. \(week.completed) sessions completed." }
    return "\(week.completed) of \(week.goal) sessions this week. \(WidgetText.remaining(week))."
}

struct FreshnessLabel: View {
    let snapshot: WidgetSnapshot
    let now: Date
    let palette: WidgetPalette

    var body: some View {
        HStack(spacing: 4) {
            if snapshot.isPreview {
                Text("PREVIEW")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(palette.accentText)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(palette.accent.opacity(0.16), in: Capsule())
            }
            Text(WidgetTimelineLogic.freshnessLabel(generatedAt: snapshot.generatedAt, now: now))
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(
                    WidgetTimelineLogic.isStale(generatedAt: snapshot.generatedAt, now: now)
                        ? palette.warning
                        : palette.textTertiary
                )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = WidgetTimelineLogic.freshnessLabel(generatedAt: snapshot.generatedAt, now: now)
        if snapshot.isPreview { text = "Preview data. " + text }
        return text
    }
}
