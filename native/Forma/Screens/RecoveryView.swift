import SwiftUI

struct RecoveryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.formaPalette) private var palette

    private var mobility: [Exercise] {
        model.exercises.filter { $0.category == .mobility }
    }

    private var today: WorkoutDay? {
        model.todayDay
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                PageHeading(
                    eyebrow: "Recover",
                    title: "Recovery",
                    subtitle: "Rest is part of the programme. Keep it deliberate, not accidental."
                )
                snapshotCard
                guidanceCard
                mobilitySection
                checklistCard
                NoticeBanner(
                    message: "Recovery guidance is general. Persistent pain, sleep problems, or unusual fatigue deserve a qualified professional.",
                    systemImage: "heart.text.square"
                )
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.top, Spacing.sm)
            .padding(.bottom, Spacing.xxxl)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(FormaBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    private var snapshotCard: some View {
        FormaCard(style: .raised) {
            Overline(text: "Right now")
            HStack(spacing: Spacing.lg) {
                Image(systemName: today?.isRestDay == true ? "moon.stars" : "figure.cooldown")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(palette.accentText)
                    .frame(width: 46, height: 46)
                    .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(today?.isRestDay == true ? "Scheduled rest day" : "Training day")
                        .font(FormaFont.displayFont(19, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text(today?.isRestDay == true
                         ? (today?.restNote ?? "Keep today easy and let the work settle.")
                         : "If you have trained today, protect the rest of the evening: food, water, and sleep.")
                        .font(FormaFont.bodyFont(12))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            FormaDivider()
            HStack(spacing: Spacing.xxl) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(lastSessionLabel)
                        .font(FormaFont.bodyFont(13, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text("last session")
                        .font(FormaFont.bodyFont(10))
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(TrainingStats.currentWeekCount(model.sessions))/\(max(1, model.plan?.daysPerWeek ?? 3))")
                        .font(FormaFont.bodyFont(13, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text("this week")
                        .font(FormaFont.bodyFont(10))
                        .foregroundStyle(palette.textTertiary)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(TrainingStats.currentStreak(model.sessions)) days")
                        .font(FormaFont.bodyFont(13, weight: .semibold))
                        .foregroundStyle(palette.text)
                    Text("streak")
                        .font(FormaFont.bodyFont(10))
                        .foregroundStyle(palette.textTertiary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var lastSessionLabel: String {
        guard let session = model.completedSessions.first else { return "—" }
        return Formatters.shortDate(session.startedAt)
    }

    private var guidanceCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Today's guidance")
            guidanceRow(icon: "bed.double", title: "Sleep 7–9 hours", detail: "The strongest recovery tool you have. Keep a consistent window.")
            FormaDivider()
            guidanceRow(icon: "drop", title: "Drink water through the day", detail: "Urine should stay pale. More if it is hot or you trained hard.")
            FormaDivider()
            guidanceRow(icon: "fork.knife", title: "Eat enough protein", detail: "Spread it across meals. You do not need to track every gram.")
            FormaDivider()
            guidanceRow(icon: "figure.walk", title: "Move easily", detail: "A 10–20 minute walk helps soreness without adding training stress.")
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }

    private func guidanceRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.accentText)
                .frame(width: 34, height: 34)
                .background(palette.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FormaFont.bodyFont(13.5, weight: .semibold))
                    .foregroundStyle(palette.text)
                Text(detail)
                    .font(FormaFont.bodyFont(11.5))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var mobilitySection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: "Gentle mobility")
            if mobility.isEmpty {
                Text("No mobility exercises are available in the library right now.")
                    .font(FormaFont.bodyFont(12))
                    .foregroundStyle(palette.textTertiary)
            } else {
                VStack(spacing: Spacing.sm) {
                    ForEach(mobility.prefix(4)) { exercise in
                        NavigationLink {
                            ExerciseDetailView(exercise: exercise)
                        } label: {
                            HStack(spacing: Spacing.md) {
                                ExerciseGlyph(exercise: exercise, size: 38)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(exercise.name)
                                        .font(FormaFont.bodyFont(13.5, weight: .semibold))
                                        .foregroundStyle(palette.text)
                                    Text(exercise.primaryMuscles.map(\.label).joined(separator: " · "))
                                        .font(FormaFont.bodyFont(10.5))
                                        .foregroundStyle(palette.textTertiary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(palette.textTertiary)
                            }
                            .padding(Spacing.md)
                            .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                    .strokeBorder(palette.border, lineWidth: 1)
                            }
                        }
                        .buttonStyle(PressableScaleStyle())
                    }
                }
            }
        }
    }

    private var checklistCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Simple checklist")
            ForEach([
                "Soreness that fades with easy movement is normal. Sharp or joint pain is not.",
                "If a warm-up makes a movement feel worse, skip that movement today.",
                "Two hard sessions back to back are fine only if sleep and food are on point.",
                "Hydration and a short walk beat an extra set of stretching.",
            ], id: \.self) { line in
                HStack(alignment: .top, spacing: Spacing.sm) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(palette.accentText)
                        .padding(.top, 2)
                    Text(line)
                        .font(FormaFont.bodyFont(12.5))
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(palette.border, lineWidth: 1)
        }
    }
}
