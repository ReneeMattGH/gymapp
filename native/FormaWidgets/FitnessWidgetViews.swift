import SwiftUI
import WidgetKit

struct FitnessWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    let entry: FitnessEntry

    var body: some View {
        let palette = WidgetPalette(scheme: colorScheme)
        Group {
            switch family {
            case .systemMedium:
                MediumWidgetView(entry: entry, palette: palette)
            case .systemLarge:
                LargeWidgetView(entry: entry, palette: palette)
            default:
                SmallWidgetView(entry: entry, palette: palette)
            }
        }
        .containerBackground(for: .widget) {
            WidgetBackground(palette: palette)
        }
        .widgetURL(WidgetLinks.today)
    }
}

// MARK: - Shared pieces

private func stateIcon(_ state: WidgetTodayState) -> String {
    switch state {
    case .workout: "figure.strengthtraining.traditional"
    case .completed: "checkmark.circle.fill"
    case .inProgress: "bolt.fill"
    case .rest: "moon.stars.fill"
    case .notScheduled: "calendar"
    case .noPlan: "sparkles"
    }
}

private struct BrandRow: View {
    let palette: WidgetPalette
    var trailingIcon: String?

    var body: some View {
        HStack(spacing: 5) {
            WidgetBrandMark(size: 13, color: palette.accent)
            Text("FORMA")
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .tracking(1.5)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.accentText)
                    .accessibilityHidden(true)
            }
        }
    }
}

private struct InlineLink: View {
    let title: String
    let url: URL
    let palette: WidgetPalette

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.right")
                    .font(.system(size: 7.5, weight: .bold))
            }
            .foregroundStyle(palette.accentText)
            .padding(.vertical, 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Small

struct SmallWidgetView: View {
    let entry: FitnessEntry
    let palette: WidgetPalette

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var copy: WidgetStateCopy { WidgetStateCopy(snapshot: snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandRow(palette: palette, trailingIcon: stateIcon(snapshot.today.state))
            Spacer(minLength: 5)
            switch entry.focus {
            case .weekly:
                weeklyEmphasis
            case .consistency:
                consistencyEmphasis
            case .automatic, .today:
                todayEmphasis
            }
        }
        .padding(12)
    }

    private var todayEmphasis: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(copy.eyebrow)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(palette.accentText)
            Text(copy.title)
                .font(.system(size: 21, weight: .bold, design: .rounded))
                .foregroundStyle(palette.text)
                .lineLimit(2)
                .minimumScaleFactor(0.72)
                .padding(.top, 2)
            Text(copy.detail)
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
                .padding(.top, 3)
            Spacer(minLength: 5)
            HStack(spacing: 5) {
                Text(WidgetText.weekFraction(snapshot.week))
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.text)
                Text("this week")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 4)
                WeekProgressBar(progress: snapshot.week.progress, palette: palette, height: 4)
                    .frame(width: 44)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(weekAccessibilityLabel(snapshot.week))
            InlineLink(title: copy.cta, url: copy.url, palette: palette)
                .padding(.top, 2)
        }
    }

    private var weeklyEmphasis: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("THIS WEEK")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(palette.accentText)
            Spacer(minLength: 4)
            HStack(spacing: 10) {
                WeekRing(week: snapshot.week, palette: palette, size: 62, lineWidth: 6.5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(WidgetText.remaining(snapshot.week))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                    Text("\(WidgetText.minutes(snapshot.week.minutes)) trained")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.textTertiary)
                }
            }
            Spacer(minLength: 4)
            SevenDayChart(week: snapshot.week, today: entry.date, palette: palette, barHeight: 13)
            InlineLink(title: "View progress", url: WidgetLinks.progress, palette: palette)
                .padding(.top, 1)
        }
    }

    private var consistencyEmphasis: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("CONSISTENCY")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(palette.accentText)
            Spacer(minLength: 2)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(snapshot.streak)")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.text)
                    .minimumScaleFactor(0.7)
                Text("day\(snapshot.streak == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(snapshot.streak) day streak")
            Text(snapshot.streak == 0 ? "Finish a session to start your streak." : "Consecutive training days.")
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(2)
            Spacer(minLength: 3)
            SevenDayChart(week: snapshot.week, today: entry.date, palette: palette, barHeight: 12)
            InlineLink(title: "View progress", url: WidgetLinks.progress, palette: palette)
                .padding(.top, 1)
        }
    }
}

// MARK: - Medium

struct MediumWidgetView: View {
    let entry: FitnessEntry
    let palette: WidgetPalette

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        Group {
            if snapshot.hasPlan {
                HStack(alignment: .top, spacing: 10) {
                    MediumTodayCard(entry: entry, palette: palette)
                    MediumWeekPanel(entry: entry, palette: palette)
                        .frame(width: 128)
                }
            } else {
                MediumNoPlanView(snapshot: snapshot, palette: palette)
            }
        }
        .padding(12)
    }
}

private struct MediumTodayCard: View {
    let entry: FitnessEntry
    let palette: WidgetPalette

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var copy: WidgetStateCopy { WidgetStateCopy(snapshot: snapshot) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandRow(palette: palette, trailingIcon: stateIcon(snapshot.today.state))
            Text(copy.eyebrow)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(palette.accentText)
                .padding(.top, 5)
            Text(copy.title)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(palette.text)
                .lineLimit(2)
                .minimumScaleFactor(0.78)
                .padding(.top, 1)
            Text(copy.detail)
                .font(.system(size: 9.5, weight: .regular, design: .rounded))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(2)
                .padding(.top, 2)
            Spacer(minLength: 3)
            WidgetCTA(title: copy.cta, systemImage: copy.ctaIcon, url: copy.url, palette: palette)
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }
}

private struct MediumWeekPanel: View {
    let entry: FitnessEntry
    let palette: WidgetPalette

    private var week: WidgetWeekSummary { entry.snapshot.week }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("THIS WEEK")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(palette.textTertiary)
                Spacer(minLength: 2)
                Text(WidgetText.weekFraction(week))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.text)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(weekAccessibilityLabel(week))
            WeekProgressBar(progress: week.progress, palette: palette, height: 4.5)
                .padding(.top, 4)
            SevenDayChart(week: week, today: entry.date, palette: palette, barHeight: 27)
                .padding(.top, 5)
            Text(WidgetText.remaining(week))
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 3)
            Spacer(minLength: 2)
            HStack(spacing: 3) {
                Text("\(WidgetText.minutes(week.minutes)) trained")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                Spacer(minLength: 2)
                Link(destination: WidgetLinks.progress) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(palette.accentText)
                        .frame(width: 17, height: 17)
                        .background(palette.accent.opacity(0.14), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open progress")
            }
        }
    }
}

private struct MediumNoPlanView: View {
    let snapshot: WidgetSnapshot
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                BrandRow(palette: palette)
                Text("Your plan starts here")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.text)
                    .padding(.top, 6)
                Text("Create a training plan in Forma to see today's session and weekly progress on your Home Screen.")
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(3)
                    .padding(.top, 3)
                Spacer(minLength: 3)
                WidgetCTA(title: "Open Forma", systemImage: "arrow.up.right", url: WidgetLinks.today, palette: palette)
            }
            Spacer(minLength: 0)
            WidgetBrandMark(size: 42, color: palette.accent)
                .opacity(0.35)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - Large

struct LargeWidgetView: View {
    let entry: FitnessEntry
    let palette: WidgetPalette

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        Group {
            if snapshot.hasPlan {
                VStack(alignment: .leading, spacing: 8) {
                    LargeHeader(entry: entry, palette: palette)
                    HStack(alignment: .top, spacing: 8) {
                        LargeTodayCard(entry: entry, palette: palette)
                        LargeWeekCard(entry: entry, palette: palette)
                            .frame(width: 112)
                    }
                    LargeChartCard(entry: entry, palette: palette)
                    HStack(alignment: .top, spacing: 8) {
                        LargeConsistencyCard(entry: entry, palette: palette)
                        if let community = snapshot.community {
                            LargeCommunityCard(summary: community, palette: palette)
                                .frame(width: 112)
                        }
                    }
                    Text("General fitness guidance, not medical advice.")
                        .font(.system(size: 8, weight: .regular, design: .rounded))
                        .foregroundStyle(palette.textTertiary)
                }
            } else {
                LargeNoPlanView(snapshot: snapshot, palette: palette)
            }
        }
        .padding(14)
    }
}

private struct LargeHeader: View {
    let entry: FitnessEntry
    let palette: WidgetPalette

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            WidgetBrandMark(size: 17, color: palette.accent)
            VStack(alignment: .leading, spacing: 0) {
                Text("FORMA")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(palette.text)
                Text("Fitness command center")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.textTertiary)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(WidgetText.dayAndMonth(entry.date))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
                FreshnessLabel(snapshot: entry.snapshot, now: entry.date, palette: palette)
            }
        }
    }
}

private struct LargeTodayCard: View {
    let entry: FitnessEntry
    let palette: WidgetPalette

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var copy: WidgetStateCopy { WidgetStateCopy(snapshot: snapshot) }

    var body: some View {
        WidgetCard(palette: palette) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(copy.eyebrow)
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(palette.accentText)
                    Spacer(minLength: 2)
                    Image(systemName: stateIcon(snapshot.today.state))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(palette.accentText)
                        .accessibilityHidden(true)
                }
                Text(copy.title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .padding(.top, 3)
                Text(copy.detail)
                    .font(.system(size: 9.5, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(2)
                    .padding(.top, 2)
                Spacer(minLength: 4)
                WidgetCTA(title: copy.cta, systemImage: copy.ctaIcon, url: copy.url, palette: palette)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LargeWeekCard: View {
    let entry: FitnessEntry
    let palette: WidgetPalette

    private var week: WidgetWeekSummary { entry.snapshot.week }

    var body: some View {
        WidgetCard(palette: palette, raised: true) {
            VStack(alignment: .leading, spacing: 0) {
                Text("THIS WEEK")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(palette.textTertiary)
                HStack {
                    Spacer(minLength: 0)
                    WeekRing(week: week, palette: palette, size: 58, lineWidth: 6)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                Text(WidgetText.remaining(week))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.text)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text("\(WidgetText.minutes(week.minutes)) trained")
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .padding(.top, 1)
            }
        }
    }
}

private struct LargeChartCard: View {
    let entry: FitnessEntry
    let palette: WidgetPalette

    private var week: WidgetWeekSummary { entry.snapshot.week }

    var body: some View {
        WidgetCard(palette: palette) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("LAST 7 DAYS")
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(palette.textTertiary)
                    Spacer(minLength: 4)
                    Text(week.hasActivity ? "\(week.completed) sessions" : "No sessions yet")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.textTertiary)
                }
                SevenDayChart(week: week, today: entry.date, palette: palette, barHeight: 28)
                    .padding(.top, 5)
                if !week.hasActivity {
                    Text("Complete a workout and its day fills in here.")
                        .font(.system(size: 8.5, weight: .regular, design: .rounded))
                        .foregroundStyle(palette.textTertiary)
                        .padding(.top, 3)
                }
            }
        }
    }
}

private struct LargeConsistencyCard: View {
    let entry: FitnessEntry
    let palette: WidgetPalette

    private var snapshot: WidgetSnapshot { entry.snapshot }

    var body: some View {
        WidgetCard(palette: palette) {
            VStack(alignment: .leading, spacing: 0) {
                Text("CONSISTENCY")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(palette.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(snapshot.streak)")
                        .font(.system(size: 27, weight: .bold, design: .rounded))
                        .foregroundStyle(palette.text)
                    Text("day streak")
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(snapshot.streak) day streak")
                if snapshot.totalCompleted > 0 {
                    Text("\(snapshot.totalCompleted) sessions · \(snapshot.totalReps) reps logged")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.top, 1)
                } else {
                    Text("Finish your first session to start the streak.")
                        .font(.system(size: 8.5, weight: .medium, design: .rounded))
                        .foregroundStyle(palette.textTertiary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }
        }
    }
}

private struct LargeCommunityCard: View {
    let summary: WidgetCommunitySummary
    let palette: WidgetPalette

    var body: some View {
        WidgetCard(palette: palette) {
            VStack(alignment: .leading, spacing: 0) {
                Text("COMMUNITY")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .tracking(1)
                    .foregroundStyle(palette.textTertiary)
                if summary.hasAny {
                    HStack(alignment: .top, spacing: 4) {
                        countLink(value: summary.pendingRequests, label: "requests", icon: "person.badge.plus", url: WidgetLinks.connectionRequests, palette: palette)
                        countLink(value: summary.unreadMessages, label: "messages", icon: "bubble.left", url: WidgetLinks.messages, palette: palette)
                        countLink(value: summary.unreadNotifications, label: "alerts", icon: "bell", url: WidgetLinks.community, palette: palette)
                    }
                    .padding(.top, 5)
                } else {
                    Text("All caught up")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.text)
                        .padding(.top, 5)
                    Link(destination: WidgetLinks.community) {
                        Text("Open Community")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(palette.accentText)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
    }

    private func countLink(value: Int, label: String, icon: String, url: URL, palette: WidgetPalette) -> some View {
        Link(destination: url) {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(value > 0 ? palette.accentText : palette.textTertiary)
                Text("\(value)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(palette.text)
                Text(label)
                    .font(.system(size: 7, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(value) \(label). Open \(label).")
    }
}

private struct LargeNoPlanView: View {
    let snapshot: WidgetSnapshot
    let palette: WidgetPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                WidgetBrandMark(size: 17, color: palette.accent)
                Text("FORMA")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.8)
                    .foregroundStyle(palette.text)
                Spacer(minLength: 4)
                FreshnessLabel(snapshot: snapshot, now: Date(), palette: palette)
            }
            Spacer(minLength: 10)
            Text("Your plan starts here")
                .font(.system(size: 27, weight: .bold, design: .rounded))
                .foregroundStyle(palette.text)
            Text("Create a training plan in Forma. Today's session, weekly goal, streak and seven-day activity will appear here using only the workouts you actually complete.")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(5)
                .padding(.top, 5)
            WidgetCTA(title: "Open Forma", systemImage: "arrow.up.right", url: WidgetLinks.today, palette: palette)
                .padding(.top, 10)
            Spacer(minLength: 8)
            Text("General fitness guidance, not medical advice.")
                .font(.system(size: 8, weight: .regular, design: .rounded))
                .foregroundStyle(palette.textTertiary)
        }
    }
}
