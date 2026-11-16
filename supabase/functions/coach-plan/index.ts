import { authenticate, AuthError } from '../_shared/auth.ts';
import {
  formatExerciseCatalog,
  formatExerciseHistory,
  formatHistory,
  formatPlan,
  formatProfile,
  loadTrainingContext,
  type TrainingContext,
} from '../_shared/context.ts';
import { json, methodNotAllowed, preflight } from '../_shared/http.ts';
import { openAiChat, openAiError, stripCodeFence } from '../_shared/openai.ts';
import {
  validateAndNormalizePlan,
  type PlanConstraints,
  type PlanPayload,
  type ValidationIssue,
} from '../_shared/planValidation.ts';

const PLAN_RULES = `You design conservative, well-balanced resistance and movement plans.

Rules:
- Return all seven weekdays exactly once (ISO: 1 = Monday … 7 = Sunday).
- Training days MUST be exactly the athlete's selected weekdays. Every other day is rest with an empty exercises array and a short restNote.
- Training days must contain 3-6 exercises, chosen only from the provided allowed exercise IDs.
- Match the athlete's equipment. Never prescribe equipment they do not have.
- Respect every limitation and avoid-listed exercise. If a movement could aggravate a limitation, choose an alternative from the allowed list.
- Use 2-3 sets for beginners, up to 4 for others; 6-15 reps for strength/general goals, 10-20 for endurance; 45-120 seconds of rest.
- Each session's estimatedMinutes must be within 15 minutes of the athlete's session length. Include a short warm-up and cool-down.
- Beginners: simple bilateral movements, one exercise per muscle group, no max-effort work.
- Advanced athletes may use more volume, but never add max-effort or unsafe loading cues.
- Never include medical advice or claims.`;

const PLAN_SHAPE = `Respond with a single JSON object and nothing else:
{
  "name": "Short plan name",
  "days": [
    {
      "weekday": 1,
      "title": "Lower strength",
      "focus": ["quads", "glutes"],
      "estimatedMinutes": 45,
      "isRestDay": false,
      "restNote": null,
      "warmup": ["5 minutes easy cycling", "Hip openers"],
      "cooldown": ["Easy walk", "Hamstring stretch"],
      "exercises": [
        {
          "exerciseId": "goblet-squat",
          "sets": 3,
          "repsMin": 8,
          "repsMax": 12,
          "restSeconds": 90,
          "notes": "Leave two reps in reserve."
        }
      ]
    }
  ]
}`;

const INSIGHT_PROMPT = `You are Forma, a careful gym coach writing a short daily note inside the app.

Write 2-3 sentences (maximum 55 words) in second person. Be warm and specific, never hype.
Use only facts present in the context: the plan, recent sessions, exercise history, and the actual date.
If there is no recent training, say so plainly and suggest the next useful step.
Do not invent weights, streaks, calories, or performance numbers.
Do not diagnose or treat anything. If a limitation appears, keep the suggestion conservative.
Return plain text only: no markdown, no lists, no quotation marks around the whole answer.`;

type ExerciseMeta = {
  id: string;
  name: string;
  equipment: string[];
  difficulty: string;
};

function stringList(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === 'string') : [];
}

/** Exercises the athlete can actually perform, further filtered for experience. */
function allowedExercises(context: TrainingContext): ExerciseMeta[] {
  const preferences = context.preferences ?? {};
  const equipment = new Set(stringList(preferences.equipment));
  const avoid = new Set(stringList(preferences.avoid_exercises));
  const experience = String(context.profile?.experience ?? 'beginner');
  const allowedDifficulty =
    experience === 'advanced'
      ? new Set(['beginner', 'intermediate', 'advanced'])
      : experience === 'intermediate'
        ? new Set(['beginner', 'intermediate'])
        : new Set(['beginner']);

  return context.exercises
    .map((exercise) => ({
      id: String(exercise.id),
      name: String(exercise.name),
      equipment: stringList(exercise.equipment),
      difficulty: String(exercise.difficulty ?? 'beginner'),
    }))
    .filter((exercise) => {
      if (avoid.has(exercise.id)) return false;
      if (!allowedDifficulty.has(exercise.difficulty)) return false;
      return exercise.equipment.every((item) => item === 'bodyweight' || equipment.has(item));
    });
}

function preferredWeekdays(context: TrainingContext): number[] {
  const raw = context.preferences?.workout_days;
  if (!Array.isArray(raw)) return [];
  const days = raw.filter((day): day is number => typeof day === 'number' && day >= 1 && day <= 7);
  return [...new Set(days)].sort((a, b) => a - b);
}

type AttemptOutcome =
  | { kind: 'plan'; plan: PlanPayload; issues: ValidationIssue[] }
  | { kind: 'invalid'; raw: string; issues: ValidationIssue[] };

async function attemptPlan(
  content: string,
  constraints: PlanConstraints,
  repair?: { raw: string; issues: ValidationIssue[] },
): Promise<AttemptOutcome> {
  const messages = [
    { role: 'system' as const, content: PLAN_RULES },
    { role: 'user' as const, content },
  ];

  if (repair) {
    const problems = repair.issues
      .filter((issue) => issue.severity === 'error')
      .slice(0, 8)
      .map((issue) => `- ${issue.message}`)
      .join('\n');
    messages.push({ role: 'assistant' as const, content: repair.raw.slice(0, 7000) });
    messages.push({
      role: 'user' as const,
      content: [
        'That plan was rejected by the server validator for these reasons:',
        problems,
        '',
        'Return a corrected JSON object only. Keep the same schema. Fix every listed problem: use only allowed IDs, the athlete’s exact training weekdays, no duplicate exercises in a day, and session lengths within 15 minutes of the target.',
      ].join('\n'),
    });
  }

  const upstream = await openAiChat({
    json: true,
    temperature: 0.4,
    maxTokens: 3000,
    retries: 1,
    timeoutMs: 60_000,
    messages,
  });

  if (!upstream.ok) {
    const detail = await openAiError(upstream);
    console.error('coach-plan upstream failure', upstream.status);
    throw new Error(detail);
  }

  const completion = (await upstream.json()) as {
    choices?: { message?: { content?: string } }[];
  };
  const raw = completion.choices?.[0]?.message?.content;
  if (!raw) return { kind: 'invalid', raw: '', issues: [] };

  let parsed: unknown;
  try {
    parsed = JSON.parse(stripCodeFence(raw));
  } catch {
    return {
      kind: 'invalid',
      raw,
      issues: [
        {
          severity: 'error',
          code: 'invalid_json',
          message: 'The response was not valid JSON.',
        },
      ],
    };
  }

  const result = validateAndNormalizePlan(parsed, constraints);
  if (result.plan) return { kind: 'plan', plan: result.plan, issues: result.issues };
  return { kind: 'invalid', raw, issues: result.issues };
}

async function handlePlan(client: Awaited<ReturnType<typeof authenticate>>['client'], userId: string) {
  const context = await loadTrainingContext(client, userId);
  if (!context.profile || context.profile.onboarding_completed !== true) {
    return json({ error: 'Complete onboarding before generating an AI plan.' }, 400);
  }
  if (!context.preferences) {
    return json({ error: 'Save your training preferences before generating an AI plan.' }, 400);
  }

  const weekdays = preferredWeekdays(context);
  const sessionMinutes = Number(context.preferences.session_minutes ?? 45);
  const experience = String(context.profile.experience ?? 'beginner');
  const allowed = allowedExercises(context);

  if (allowed.length === 0) {
    return json(
      {
        error:
          'No verified exercises match your equipment and experience yet. Add equipment or use the on-device plan.',
      },
      422,
    );
  }

  const constraints: PlanConstraints = {
    allowedIds: new Set(allowed.map((exercise) => exercise.id)),
    preferredWeekdays: weekdays,
    sessionMinutes,
    experience: experience === 'advanced' ? 'advanced' : experience === 'intermediate' ? 'intermediate' : 'beginner',
  };

  const weekdayNames = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const scheduleLine = weekdays.length > 0
    ? `Selected training weekdays: ${weekdays.map((day) => weekdayNames[day]).join(', ')}. The plan must include exactly ${weekdays.length} training days on these weekdays.`
    : `No specific weekdays were selected. Choose ${Math.max(1, Math.min(7, weekdays.length || 3))} realistic training days and make every other day a rest day.`;

  const content = [
    '## Athlete profile',
    formatProfile(context),
    '',
    '## Schedule requirement',
    scheduleLine,
    `Required session length: ${sessionMinutes} minutes (estimated minutes must be within 15 minutes).`,
    '',
    '## Current plan (for reference only; replace it)',
    formatPlan(context),
    '',
    '## Recent training',
    formatHistory(context),
    '',
    '## Recent exercise history',
    formatExerciseHistory(context),
    '',
    '## Allowed exercise library — choose only these exact IDs',
    formatExerciseCatalog({
      ...context,
      exercises: allowed.map((exercise) => ({
        id: exercise.id,
        name: exercise.name,
        category: '',
        primary_muscles: [],
        secondary_muscles: [],
        equipment: exercise.equipment,
        difficulty: exercise.difficulty,
      })),
    }),
    '',
    '## Output format',
    PLAN_SHAPE,
  ].join('\n');

  let outcome = await attemptPlan(content, constraints);
  let repaired = false;
  if (outcome.kind === 'invalid') {
    repaired = true;
    outcome = await attemptPlan(content, constraints, {
      raw: outcome.raw,
      issues: outcome.issues,
    });
  }

  if (outcome.kind === 'invalid') {
    const reasons = outcome.issues
      .filter((issue) => issue.severity === 'error')
      .slice(0, 3)
      .map((issue) => issue.message);
    return json(
      {
        error:
          reasons.length > 0
            ? `The AI plan did not pass validation: ${reasons.join(' ')} Generate again, or use the on-device plan.`
            : 'The AI plan could not be validated. Generate again, or use the on-device plan.',
        validation: outcome.issues.map((issue) => issue.code),
      },
      422,
    );
  }

  return json({
    plan: outcome.plan,
    repaired,
    warnings: outcome.issues.filter((issue) => issue.severity === 'warning').length,
  });
}

async function handleInsight(client: Awaited<ReturnType<typeof authenticate>>['client'], userId: string) {
  const context = await loadTrainingContext(client, userId);
  const today = new Date().toISOString().slice(0, 10);

  const upstream = await openAiChat({
    json: false,
    temperature: 0.6,
    maxTokens: 220,
    retries: 1,
    timeoutMs: 30_000,
    messages: [
      { role: 'system', content: INSIGHT_PROMPT },
      {
        role: 'user',
        content: [
          `Today's date: ${today}`,
          '',
          '## Athlete profile',
          formatProfile(context),
          '',
          '## Active plan',
          formatPlan(context),
          '',
          '## Recent completed training',
          formatHistory(context),
          '',
          '## Recent exercise history',
          formatExerciseHistory(context),
        ].join('\n'),
      },
    ],
  });

  if (!upstream.ok) {
    const detail = await openAiError(upstream);
    console.error('coach-plan insight upstream failure', upstream.status);
    return json({ error: detail }, upstream.status === 429 ? 429 : 502);
  }

  const completion = (await upstream.json()) as {
    choices?: { message?: { content?: string } }[];
  };
  const insight = completion.choices?.[0]?.message?.content?.trim();
  if (!insight) return json({ error: 'The AI coach did not return a note.' }, 502);

  return json({ insight: insight.replace(/<\/?[^>]+>/g, '').slice(0, 600) });
}

Deno.serve(async (request: Request) => {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== 'POST') return methodNotAllowed();

  try {
    const { client, user } = await authenticate(request);
    const body = (await request.json().catch(() => null)) as { action?: unknown } | null;
    const action = typeof body?.action === 'string' ? body.action : '';

    if (action === 'generate_plan') return await handlePlan(client, user.id);
    if (action === 'daily_insight') return await handleInsight(client, user.id);
    return json({ error: 'Unknown action.' }, 400);
  } catch (error) {
    if (error instanceof AuthError) return json({ error: error.message }, 401);
    if (error instanceof DOMException && error.name === 'TimeoutError') {
      return json({ error: 'The AI coach took too long to respond. Please try again.' }, 504);
    }
    console.error('coach-plan failed', error instanceof Error ? error.message : 'unknown');
    return json({ error: 'The AI coach is unavailable right now. Please try again shortly.' }, 500);
  }
});
