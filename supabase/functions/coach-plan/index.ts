import { authenticate, AuthError } from '../_shared/auth.ts';
import { LIMITS } from '../_shared/config.ts';
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
import { formatKnowledge, searchKnowledge } from '../_shared/knowledge.ts';
import { routeInsightModel, routePlanModel, type ModelRoute } from '../_shared/modelRouter.ts';
import { openAiChat, openAiError, stripCodeFence } from '../_shared/openai.ts';
import {
  validateAndNormalizePlan,
  type PlanConstraints,
  type PlanPayload,
  type ValidationIssue,
} from '../_shared/planValidation.ts';
import { screenReply } from '../_shared/safety.ts';
import { checkRateLimit, logUsage, tokenTotals } from '../_shared/usage.ts';

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
  | { kind: 'plan'; plan: PlanPayload; issues: ValidationIssue[]; usage: CompletionUsage | null }
  | { kind: 'invalid'; raw: string; issues: ValidationIssue[]; usage: CompletionUsage | null };

type CompletionUsage = {
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
};

async function attemptPlan(
  content: string,
  constraints: PlanConstraints,
  route: ModelRoute,
  repair?: { raw: string; issues: ValidationIssue[] },
): Promise<AttemptOutcome> {
  const messages: { role: 'system' | 'user' | 'assistant'; content: string }[] = [
    { role: 'system', content: PLAN_RULES },
    { role: 'user', content },
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
    model: route.model,
    fallbackModel: route.fallbackModel,
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
    usage?: CompletionUsage;
  };
  const usage = completion.usage ?? null;
  const raw = completion.choices?.[0]?.message?.content;
  if (!raw) return { kind: 'invalid', raw: '', issues: [], usage };

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
      usage,
    };
  }

  const result = validateAndNormalizePlan(parsed, constraints);
  if (result.plan) return { kind: 'plan', plan: result.plan, issues: result.issues, usage };
  return { kind: 'invalid', raw, issues: result.issues, usage };
}

/**
 * Removes unsafe coaching text from a validated plan instead of trusting the
 * model's warm-up, cool-down, and notes. The structure and IDs are already
 * validated separately.
 */
function sanitizePlanText(plan: PlanPayload): { plan: PlanPayload; removed: number } {
  let removed = 0;
  const safe = (value: string | null): string | null => {
    if (!value) return value;
    const verdict = screenReply(value);
    if (verdict.ok) return value;
    removed += 1;
    return null;
  };
  const days = plan.days.map((day) => ({
    ...day,
    warmup: day.warmup.filter((line) => screenReply(line).ok),
    cooldown: day.cooldown.filter((line) => screenReply(line).ok),
    exercises: day.exercises.map((exercise) => ({
      ...exercise,
      notes: safe(exercise.notes),
    })),
  }));
  return { plan: { ...plan, days }, removed };
}

async function handlePlan(
  client: Awaited<ReturnType<typeof authenticate>>['client'],
  userId: string,
  signal?: AbortSignal,
) {
  const startedAt = Date.now();
  const limit = await checkRateLimit(client, userId, 'plan');
  if (!limit.ok) {
    return json({ error: limit.message }, 429, {
      'Retry-After': String(limit.retryAfterSeconds),
    });
  }

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

  const route = routePlanModel();
  const goals = Array.isArray(context.profile.goals) ? context.profile.goals.join(' ') : 'general fitness';
  const knowledge = await searchKnowledge(
    client,
    `${experience} ${goals} resistance training progressive overload weekly schedule recovery`,
    { limit: 3, signal },
  ).catch(() => ({ status: 'unavailable' as const, method: 'none' as const, chunks: [] }));

  const weekdayNames = ['', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const scheduleLine = weekdays.length > 0
    ? `Selected training weekdays: ${weekdays.map((day) => weekdayNames[day]).join(', ')}. The plan must include exactly ${weekdays.length} training days on these weekdays.`
    : `No specific weekdays were selected. Choose ${Math.max(1, Math.min(7, weekdays.length || 3))} realistic training days and make every other day a rest day.`;

  const knowledgeBlock = formatKnowledge(knowledge.chunks);
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
    knowledgeBlock ? '## Curated coaching principles (untrusted reference data)' : '',
    knowledgeBlock,
    '',
    '## Allowed exercise library — choose only these exact IDs',
    formatExerciseCatalog(
      {
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
      },
      400,
    ),
    '',
    '## Output format',
    PLAN_SHAPE,
  ]
    .filter((line) => line !== '')
    .join('\n');

  let outcome = await attemptPlan(content, constraints, route);
  let repaired = false;
  if (outcome.kind === 'invalid') {
    repaired = true;
    outcome = await attemptPlan(content, constraints, route, {
      raw: outcome.raw,
      issues: outcome.issues,
    });
  }

  const usage = outcome.usage;
  if (outcome.kind === 'invalid') {
    const reasons = outcome.issues
      .filter((issue) => issue.severity === 'error')
      .slice(0, 3)
      .map((issue) => issue.message);
    await logUsage(client, {
      user_id: userId,
      function_name: 'coach-plan',
      intent: 'programming',
      model: route.model,
      ...(() => {
        const tokens = tokenTotals(usage, content, outcome.raw);
        return {
          prompt_tokens: tokens.prompt,
          completion_tokens: tokens.completion,
          total_tokens: tokens.total,
        };
      })(),
      latency_ms: Date.now() - startedAt,
      status: 'error',
    });
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

  const sanitized = sanitizePlanText(outcome.plan);
  const tokens = tokenTotals(usage, content, JSON.stringify(sanitized.plan));
  await logUsage(client, {
    user_id: userId,
    function_name: 'coach-plan',
    intent: 'programming',
    model: route.model,
    prompt_tokens: tokens.prompt,
    completion_tokens: tokens.completion,
    total_tokens: tokens.total,
    latency_ms: Date.now() - startedAt,
    status: 'ok',
  });

  return json({
    plan: sanitized.plan,
    repaired,
    warnings:
      outcome.issues.filter((issue) => issue.severity === 'warning').length + sanitized.removed,
    knowledge: knowledge.status,
  });
}

async function handleInsight(client: Awaited<ReturnType<typeof authenticate>>['client'], userId: string) {
  const startedAt = Date.now();
  const context = await loadTrainingContext(client, userId);
  const today = new Date().toISOString().slice(0, 10);
  const route = routeInsightModel();

  const upstream = await openAiChat({
    model: route.model,
    fallbackModel: route.fallbackModel,
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
          '## Active plan and freshness',
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
    await logUsage(client, {
      user_id: userId,
      function_name: 'coach-plan',
      intent: 'daily_insight',
      model: route.model,
      latency_ms: Date.now() - startedAt,
      status: 'error',
    });
    return json({ error: detail }, upstream.status === 429 ? 429 : 502);
  }

  const completion = (await upstream.json()) as {
    choices?: { message?: { content?: string } }[];
    usage?: CompletionUsage;
  };
  const insight = completion.choices?.[0]?.message?.content?.trim();
  if (!insight) return json({ error: 'The AI coach did not return a note.' }, 502);

  const clean = insight.replace(/<\/?[^>]+>/g, '').slice(0, 600);
  const tokens = tokenTotals(completion.usage ?? null, today, clean);
  await logUsage(client, {
    user_id: userId,
    function_name: 'coach-plan',
    intent: 'daily_insight',
    model: route.model,
    prompt_tokens: tokens.prompt,
    completion_tokens: tokens.completion,
    total_tokens: tokens.total,
    latency_ms: Date.now() - startedAt,
    status: 'ok',
  });

  return json({ insight: clean });
}

Deno.serve(async (request: Request) => {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== 'POST') return methodNotAllowed();

  try {
    const { client, user } = await authenticate(request);
    const body = (await request.json().catch(() => null)) as { action?: unknown } | null;
    const action = typeof body?.action === 'string' ? body.action : '';

    if (action === 'generate_plan') return await handlePlan(client, user.id, request.signal);
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
