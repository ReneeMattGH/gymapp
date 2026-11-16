import type { Exercise, Profile, Preferences, WorkoutPlan, WorkoutSession } from '@/data/types';
import { currentStreak, currentWeekCount, formatLongDate } from '@/lib/date';
import { EXERCISE_LIBRARY, planForDate } from '@/lib/plan';

export type LocalCoachContext = {
  profile: Profile;
  preferences: Preferences;
  plan: WorkoutPlan | null;
  sessions: WorkoutSession[];
  exercises: Exercise[];
};

function nameList(ids: string[]): string {
  const map = new Map(EXERCISE_LIBRARY.map((exercise) => [exercise.id, exercise.name]));
  return ids.map((id) => map.get(id) ?? id).join(', ');
}

function describeExercise(exercise: Exercise): string {
  return [
    `**${exercise.name}**`,
    '',
    ...exercise.instructions.map((step, index) => `${index + 1}. ${step}`),
    '',
    '**Form cues**',
    ...exercise.cues.map((cue) => `• ${cue}`),
    '',
    '**Watch out for**',
    ...exercise.mistakes.map((mistake) => `• ${mistake}`),
  ].join('\n');
}

function findExercise(message: string, exercises: Exercise[]): Exercise | undefined {
  const text = message.toLowerCase();
  const sorted = [...exercises].sort((a, b) => b.name.length - a.name.length);
  return sorted.find((exercise) => text.includes(exercise.name.toLowerCase()));
}

export function localCoachReply(message: string, context: LocalCoachContext): string {
  const text = message.toLowerCase().trim();
  const { plan, profile, preferences, sessions, exercises } = context;

  if (/(pain|hurt|injur|dizzy|chest tight|sharp)/i.test(text)) {
    return [
      'Stop the exercise for now — especially if the pain is sharp, sudden, or accompanied by dizziness.',
      '',
      'I cannot diagnose what is happening. Rest the area, avoid loading it, and speak with a qualified medical professional or physiotherapist if it continues or worries you.',
      '',
      'When you are cleared to train again, we can adjust the plan around it. Use the limitations field in your profile to note anything you want the plan to avoid.',
    ].join('\n');
  }

  if (/(sore|soreness|doms|achy)/i.test(text)) {
    return [
      'Mild soreness a day or two after training is common. Sharp pain, swelling, or pain that changes how you walk is not something to train through.',
      '',
      'For general soreness:',
      '• Keep moving gently — an easy walk and a few mobility drills',
      '• Prioritize sleep and regular meals',
      '• Reduce the load or range for the next session if you are still sore',
      '• Skip any exercise that reproduces sharp pain',
      '',
      'If soreness lasts more than a few days or keeps getting worse, get it looked at by a professional.',
    ].join('\n');
  }

  if (/(short on time|busy|only have|quick workout|20 min|15 min|no time|tired|exhausted|low energy)/i.test(text)) {
    const today = plan ? planForDate(plan, new Date()) : undefined;
    const exercisesToday =
      plan && today && !today.isRestDay
        ? today.exercises.slice(0, 3).map((row) => exercises.find((exercise) => exercise.id === row.exerciseId)?.name ?? row.exerciseId)
        : [];
    return [
      'A shorter session still counts. The goal is to keep the habit and leave a little in the tank.',
      '',
      exercisesToday.length
        ? `Try this 15–20 minute version of today's session: ${exercisesToday.join(', ')}.`
        : 'Try 15 minutes of easy movement: a brisk walk, a few squats, and some mobility.',
      '',
      '• Use 2 sets per exercise instead of the planned amount',
      '• Rest 60 seconds between sets',
      '• Keep the last set two reps away from failure',
      '• Finish with 3 minutes of easy breathing and a gentle stretch',
      '',
      'If you are genuinely exhausted, a rest day is the better training decision. Recovery is part of the plan.',
    ].join('\n');
  }

  if (/(warm.?up|warmup)/i.test(text)) {
    return [
      'A good warm-up raises your temperature and rehearses the movements you are about to do.',
      '',
      '**Five-minute template**',
      '• 2–3 minutes of easy cardio: walk, bike, or row',
      '• 10 arm circles each direction and 10 shoulder rolls',
      '• 10 bodyweight squats and 10 hip hinges',
      '• One light set of the first exercise in your session',
      '',
      'You should feel warmer and more mobile — not tired. If a movement hurts, stop and choose a pain-free alternative.',
    ].join('\n');
  }

  if (/(cool.?down|cooldown|stretch)/i.test(text)) {
    return [
      'A cool-down helps you transition out of training without rushing.',
      '',
      '• 3–5 minutes of easy walking',
      '• 30–45 seconds per side for the muscles you trained',
      '• Slow nasal breathing for a minute or two',
      '',
      'Stretching does not need to be aggressive. Gentle tension is enough; sharp pain is a signal to back off.',
    ].join('\n');
  }

  if (/(recovery|rest day|sleep|deload)/i.test(text)) {
    return [
      'Recovery is when adaptation happens. Training hard and never resting is not a shortcut — it is a plateau waiting to happen.',
      '',
      '**A productive recovery day looks like:**',
      '• A 20–30 minute easy walk',
      '• Gentle mobility for hips, shoulders, and spine',
      '• Enough food and water through the day',
      '• A consistent sleep window if possible',
      '',
      plan
        ? `Your plan already marks ${plan.days.filter((day) => day.isRestDay).length} rest day(s) each week. Keep them.`
        : 'Once your plan is generated, rest days are built into the week.',
    ].join('\n');
  }

  if (/(alternative|substitute|swap|replace|instead of)/i.test(text)) {
    const exercise = findExercise(message, exercises);
    if (exercise) {
      return [
        `Alternatives for **${exercise.name}**: ${nameList(exercise.alternatives)}.`,
        '',
        'Pick one that matches your equipment and feels comfortable. Keep the same number of sets and a similar effort level.',
        '',
        'If an exercise is painful, do not force it. Choose a pain-free option or ask a qualified professional for a movement screen.',
      ].join('\n');
    }
    return [
      'Tell me which exercise you want to replace and I can suggest alternatives from your library.',
      '',
      ...exercises.slice(0, 5).map((exercise) => `• ${exercise.name}`),
      '…and more in the Exercise Library.',
    ].join('\n');
  }

  const exercise = findExercise(message, exercises);
  if (exercise && /(how|form|do|technique|explain|mistake|cue)/i.test(text)) {
    return describeExercise(exercise);
  }

  if (/(my plan|today|session|workout today|routine|split)/i.test(text)) {
    if (!plan) {
      return 'You do not have a plan yet. Open the Workouts tab and generate one — it only takes a moment.';
    }
    const today = planForDate(plan, new Date());
    if (!today) return `I could not find a day for ${formatLongDate(new Date())} in your plan.`;
    if (today.isRestDay) {
      return [
        `Today is a recovery day in **${plan.name}**.`,
        '',
        today.restNote ?? 'Keep it light: an easy walk and some gentle mobility is plenty.',
        '',
        'Your next training day is ready whenever you are — no guilt about taking the rest you planned.',
      ].join('\n');
    }
    return [
      `**${today.title}** · about ${today.estimatedMinutes} min`,
      '',
      ...today.exercises.map(
        (row, index) =>
          `${index + 1}. ${exercises.find((exercise) => exercise.id === row.exerciseId)?.name ?? row.exerciseId} — ${row.sets} × ${row.repsMin}–${row.repsMax} reps, ${row.restSeconds}s rest`,
      ),
      '',
      'Start when you are ready. Keep the final set a couple of reps away from failure.',
    ].join('\n');
  }

  if (/(progress|streak|consistency|week)/i.test(text)) {
    const thisWeek = currentWeekCount(sessions);
    const streak = currentStreak(sessions);
    const completed = sessions.filter((session) => session.status === 'completed');
    const last = completed[0];
    return [
      `This week: **${thisWeek} completed session${thisWeek === 1 ? '' : 's'}**.`,
      streak > 0 ? `Current streak: **${streak} day${streak === 1 ? '' : 's'}** with training.` : 'No active streak right now — the next session restarts it.',
      last
        ? `Last session: ${last.title} on ${new Date(last.startedAt).toLocaleDateString()} (${Math.round(last.durationSeconds / 60)} min, ${last.sets.length} sets).`
        : 'No sessions logged yet. Your first one is the hardest — start small.',
      '',
      'Consistency beats intensity. Hitting 2–3 sessions every week is a strong foundation.',
    ].join('\n');
  }

  if (/(equipment|no equipment|dumbbell|barbell|machine|band)/i.test(text)) {
    const available = preferences.equipment.join(', ') || 'bodyweight';
    return [
      `Your saved equipment: **${available}**.`,
      '',
      'Your plan only uses exercises that match this list. If your equipment changes, update it in Profile → Training preferences and regenerate the plan.',
      '',
      'If you are missing something for a session, use the substitution option during the workout — bodyweight alternatives are always available.',
    ].join('\n');
  }

  if (/(app|how do i|where do i|use forma)/i.test(text)) {
    return [
      'A quick tour:',
      '',
      '• **Home** — today\'s session, weekly activity, and a coaching note',
      '• **Workouts** — your plan, exercise library, and recovery',
      '• **Coach** — ask questions about form, substitutions, or your plan',
      '• **Progress** — real session history and trends',
      '• **Profile** — training preferences, reminders, theme, account',
      '',
      'Start a workout from Home or Workouts; your progress is saved as you go.',
    ].join('\n');
  }

  if (/(hi|hello|hey)\b/i.test(text) && text.length < 20) {
    return `Hi ${profile.name || 'there'} — what would you like to work on today? You can ask about an exercise, your plan, recovery, or substitutions.`;
  }

  if (/(motivat|lazy|can.?t get|struggl)/i.test(text)) {
    return [
      'Motivation is unreliable; a small start is more useful.',
      '',
      '• Put on your training clothes and do five minutes',
      '• Start with the easiest exercise in the session',
      '• Do two sets instead of the full plan',
      '• If you still feel drained, call it a recovery day without guilt',
      '',
      'Showing up imperfectly beats waiting for the perfect day.',
    ].join('\n');
  }

  return [
    'I can help with the practical side of your training. In this preview I answer from your plan and the exercise library rather than a live AI model.',
    '',
    'Try asking:',
    ...(exercises.slice(0, 3).map((exercise) => `• "How do I do a ${exercise.name}?"`)),
    '• "What is today\'s workout?"',
    '• "What can I swap for goblet squats?"',
    '• "I only have 15 minutes today"',
    '',
    'With Supabase and OpenAI configured, the coach answers open-ended questions too.',
  ].join('\n');
}
