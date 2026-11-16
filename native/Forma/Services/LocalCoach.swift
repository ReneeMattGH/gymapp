import Foundation

/// Deterministic on-device replies used only in the clearly-labelled preview
/// mode. These are safety-reviewed fallbacks, not a language model.
enum LocalCoach {
    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func findExercise(_ message: String, exercises: [Exercise]) -> Exercise? {
        let text = message.lowercased()
        return exercises
            .sorted { $0.name.count > $1.name.count }
            .first { text.contains($0.name.lowercased()) }
    }

    private static func describe(_ exercise: Exercise) -> String {
        var lines = ["**\(exercise.name)**", ""]
        for (index, step) in exercise.instructions.enumerated() {
            lines.append("\(index + 1). \(step)")
        }
        if !exercise.cues.isEmpty {
            lines.append("")
            lines.append("**Form cues**")
            lines.append(contentsOf: exercise.cues.map { "• \($0)" })
        }
        if !exercise.mistakes.isEmpty {
            lines.append("")
            lines.append("**Watch out for**")
            lines.append(contentsOf: exercise.mistakes.map { "• \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    static func reply(
        to message: String,
        profile: Profile,
        preferences: Preferences,
        plan: WorkoutPlan?,
        sessions: [WorkoutSession],
        exercises: [Exercise]
    ) -> String {
        let text = message.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        if matches(text, "pain|hurt|injur|dizzy|chest tight|sharp") {
            return [
                "Stop the exercise for now — especially if the pain is sharp, sudden, or accompanied by dizziness.",
                "",
                "I cannot diagnose what is happening. Rest the area, avoid loading it, and speak with a qualified medical professional or physiotherapist if it continues or worries you.",
                "",
                "When you are cleared to train again, we can adjust the plan around it. Use the limitations field in your profile to note anything you want the plan to avoid.",
            ].joined(separator: "\n")
        }

        if matches(text, "sore|soreness|doms|achy") {
            return [
                "Mild soreness a day or two after training is common. Sharp pain, swelling, or pain that changes how you walk is not something to train through.",
                "",
                "For general soreness:",
                "• Keep moving gently — an easy walk and a few mobility drills",
                "• Prioritize sleep and regular meals",
                "• Reduce the load or range for the next session if you are still sore",
                "• Skip any exercise that reproduces sharp pain",
                "",
                "If soreness lasts more than a few days or keeps getting worse, get it looked at by a professional.",
            ].joined(separator: "\n")
        }

        if matches(text, "short on time|busy|only have|quick workout|20 min|15 min|no time|tired|exhausted|low energy") {
            let today = plan.flatMap { PlanGenerator.planForDate($0, date: Date()) }
            let names: [String]
            if let today, !today.isRestDay {
                names = today.exercises.prefix(3).map { PlanGenerator.exerciseName($0.exerciseId) }
            } else {
                names = []
            }
            return [
                "A shorter session still counts. The goal is to keep the habit and leave a little in the tank.",
                "",
                names.isEmpty
                    ? "Try 15 minutes of easy movement: a brisk walk, a few squats, and some mobility."
                    : "Try this 15–20 minute version of today's session: \(names.joined(separator: ", ")).",
                "",
                "• Use 2 sets per exercise instead of the planned amount",
                "• Rest 60 seconds between sets",
                "• Keep the last set two reps away from failure",
                "• Finish with 3 minutes of easy breathing and a gentle stretch",
                "",
                "If you are genuinely exhausted, a rest day is the better training decision. Recovery is part of the plan.",
            ].joined(separator: "\n")
        }

        if matches(text, "warm.?up|warmup") {
            return [
                "A good warm-up raises your temperature and rehearses the movements you are about to do.",
                "",
                "**Five-minute template**",
                "• 2–3 minutes of easy cardio: walk, bike, or row",
                "• 10 arm circles each direction and 10 shoulder rolls",
                "• 10 bodyweight squats and 10 hip hinges",
                "• One light set of the first exercise in your session",
                "",
                "You should feel warmer and more mobile — not tired. If a movement hurts, stop and choose a pain-free alternative.",
            ].joined(separator: "\n")
        }

        if matches(text, "cool.?down|cooldown|stretch") {
            return [
                "A cool-down helps you transition out of training without rushing.",
                "",
                "• 3–5 minutes of easy walking",
                "• 30–45 seconds per side for the muscles you trained",
                "• Slow nasal breathing for a minute or two",
                "",
                "Stretching does not need to be aggressive. Gentle tension is enough; sharp pain is a signal to back off.",
            ].joined(separator: "\n")
        }

        if matches(text, "recovery|rest day|sleep|deload") {
            let restCount = plan?.days.filter(\.isRestDay).count
            return [
                "Recovery is when adaptation happens. Training hard and never resting is not a shortcut — it is a plateau waiting to happen.",
                "",
                "**A productive recovery day looks like:**",
                "• A 20–30 minute easy walk",
                "• Gentle mobility for hips, shoulders, and spine",
                "• Enough food and water through the day",
                "• A consistent sleep window if possible",
                "",
                restCount.map { "Your plan already marks \($0) rest day(s) each week. Keep them." }
                    ?? "Once your plan is generated, rest days are built into the week.",
            ].joined(separator: "\n")
        }

        if matches(text, "alternative|substitute|swap|replace|instead of") {
            if let exercise = findExercise(message, exercises: exercises) {
                let alternatives = exercise.alternatives.map { PlanGenerator.exerciseName($0) }
                return [
                    "Alternatives for **\(exercise.name)**: \(alternatives.joined(separator: ", ")).",
                    "",
                    "Pick one that matches your equipment and feels comfortable. Keep the same number of sets and a similar effort level.",
                    "",
                    "If an exercise is painful, do not force it. Choose a pain-free option or ask a qualified professional for a movement screen.",
                ].joined(separator: "\n")
            }
            return ([
                "Tell me which exercise you want to replace and I can suggest alternatives from your library.",
                "",
            ] + exercises.prefix(5).map { "• \($0.name)" }).joined(separator: "\n")
        }

        if let exercise = findExercise(message, exercises: exercises),
           matches(text, "how|form|do|technique|explain|mistake|cue") {
            return describe(exercise)
        }

        if matches(text, "my plan|today|session|workout today|routine|split") {
            guard let plan else {
                return "You do not have a plan yet. Open the Workouts tab and generate one — it only takes a moment."
            }
            guard let today = PlanGenerator.planForDate(plan, date: Date()) else {
                return "I could not find a day for \(Formatters.longDate(Date())) in your plan."
            }
            if today.isRestDay {
                return [
                    "Today is a recovery day in **\(plan.name)**.",
                    "",
                    today.restNote ?? "Keep it light: an easy walk and some gentle mobility is plenty.",
                    "",
                    "Your next training day is ready whenever you are — no guilt about taking the rest you planned.",
                ].joined(separator: "\n")
            }
            var lines = [
                "**\(today.title)** · about \(today.estimatedMinutes) min",
                "",
            ]
            for (index, row) in today.exercises.enumerated() {
                lines.append("\(index + 1). \(PlanGenerator.exerciseName(row.exerciseId)) — \(row.sets) × \(row.repsMin)–\(row.repsMax) reps, \(row.restSeconds)s rest")
            }
            lines.append("")
            lines.append("Start when you are ready. Keep the final set a couple of reps away from failure.")
            return lines.joined(separator: "\n")
        }

        if matches(text, "progress|streak|consistency|week") {
            let week = TrainingStats.currentWeekCount(sessions)
            let streak = TrainingStats.currentStreak(sessions)
            let completed = TrainingStats.completedSessions(sessions)
            var lines = [
                "This week: **\(week) completed session\(week == 1 ? "" : "s")**.",
                streak > 0
                    ? "Current streak: **\(streak) day\(streak == 1 ? "" : "s")** with training."
                    : "No active streak right now — the next session restarts it.",
            ]
            if let last = completed.first {
                lines.append("Last session: \(last.title) on \(Formatters.shortDate(last.startedAt)) (\(Formatters.minutesLabel(last.durationSeconds)), \(last.sets.count) sets).")
            } else {
                lines.append("No sessions logged yet. Your first one is the hardest — start small.")
            }
            lines.append("")
            lines.append("Consistency beats intensity. Hitting 2–3 sessions every week is a strong foundation.")
            return lines.joined(separator: "\n")
        }

        if matches(text, "equipment|no equipment|dumbbell|barbell|machine|band") {
            let available = preferences.equipment.isEmpty
                ? "bodyweight"
                : preferences.equipment.map(\.label).joined(separator: ", ")
            return [
                "Your saved equipment: **\(available)**.",
                "",
                "Your plan only uses exercises that match this list. If your equipment changes, update it in Profile → Training preferences and regenerate the plan.",
                "",
                "If you are missing something for a session, use the substitution option during the workout — bodyweight alternatives are always available.",
            ].joined(separator: "\n")
        }

        if matches(text, "app|how do i|where do i|use forma") {
            return [
                "A quick tour:",
                "",
                "• **Home** — today's session, weekly activity, and a coaching note",
                "• **Workouts** — your plan, exercise library, and recovery",
                "• **Coach** — ask questions about form, substitutions, or your plan",
                "• **Progress** — real session history and trends",
                "• **Profile** — training preferences, reminders, theme, account",
                "",
                "Start a workout from Home or Workouts; your progress is saved as you go.",
            ].joined(separator: "\n")
        }

        if matches(text, "^(hi|hello|hey)\\b") && text.count < 20 {
            return "Hi \(profile.name.isEmpty ? "there" : profile.name) — what would you like to work on today? You can ask about an exercise, your plan, recovery, or substitutions."
        }

        if matches(text, "motivat|lazy|can.?t get|struggl") {
            return [
                "Motivation is unreliable; a small start is more useful.",
                "",
                "• Put on your training clothes and do five minutes",
                "• Start with the easiest exercise in the session",
                "• Do two sets instead of the full plan",
                "• If you still feel drained, call it a recovery day without guilt",
                "",
                "Showing up imperfectly beats waiting for the perfect day.",
            ].joined(separator: "\n")
        }

        return ([
            "I can help with the practical side of your training. Preview mode answers from your plan and the exercise library rather than a live AI model.",
            "",
            "Try asking:",
        ] + exercises.prefix(3).map { "• \"How do I do a \($0.name)?\"" } + [
            "• \"What is today's workout?\"",
            "• \"What can I swap for goblet squats?\"",
            "• \"I only have 15 minutes today\"",
            "",
            "With Supabase and OpenAI configured, the coach answers open-ended questions too.",
        ]).joined(separator: "\n")
    }
}
