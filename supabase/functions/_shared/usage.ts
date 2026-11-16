import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';

import { LIMITS } from './config.ts';

export type UsageScope = 'chat' | 'plan';

export type RateLimitResult =
  | { ok: true; enforced: boolean }
  | { ok: false; enforced: true; retryAfterSeconds: number; message: string };

const FUNCTION_NAME: Record<UsageScope, string> = {
  chat: 'coach-chat',
  plan: 'coach-plan',
};

/**
 * Counts recent usage rows for the caller. This is a soft, race-tolerant limit
 * (no transaction), which is acceptable for protecting a personal coach from
 * accidental loops. If the usage table is unavailable the request is allowed
 * but marked `enforced: false` so the caller can log the degraded state.
 */
export async function checkRateLimit(
  client: SupabaseClient,
  userId: string,
  scope: UsageScope,
): Promise<RateLimitResult> {
  const now = Date.now();
  const minuteAgo = new Date(now - 60_000).toISOString();
  const dayAgo = new Date(now - 86_400_000).toISOString();
  const name = FUNCTION_NAME[scope];

  const minuteLimit = scope === 'chat' ? LIMITS.chatPerMinute : Number.POSITIVE_INFINITY;
  const dayLimit = scope === 'chat' ? LIMITS.chatPerDay : LIMITS.planPerDay;

  const minuteQuery = client
    .from('ai_usage')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .eq('function_name', name)
    .gte('created_at', minuteAgo);

  const dayQuery = client
    .from('ai_usage')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
    .eq('function_name', name)
    .gte('created_at', dayAgo);

  const [minute, day] = await Promise.all([minuteQuery, dayQuery]);
  if (minute.error || day.error) {
    console.warn('ai_usage rate-limit lookup unavailable', minute.error?.message ?? day.error?.message);
    return { ok: true, enforced: false };
  }

  if ((minute.count ?? 0) >= minuteLimit) {
    return {
      ok: false,
      enforced: true,
      retryAfterSeconds: 60,
      message: 'You are sending messages faster than the coach can answer. Wait a minute and try again.',
    };
  }
  if ((day.count ?? 0) >= dayLimit) {
    return {
      ok: false,
      enforced: true,
      retryAfterSeconds: 3600,
      message:
        scope === 'plan'
          ? 'You have generated the maximum number of AI plans for today. Try again tomorrow or use the on-device plan.'
          : 'You have reached today’s coach message limit. Try again tomorrow.',
    };
  }
  return { ok: true, enforced: true };
}

export type UsageRow = {
  user_id: string;
  function_name: string;
  intent?: string | null;
  model?: string | null;
  prompt_tokens?: number;
  completion_tokens?: number;
  total_tokens?: number;
  latency_ms?: number;
  status?: 'ok' | 'blocked' | 'error' | 'cancelled';
};

function safeCount(value: unknown): number {
  const number = Number(value);
  return Number.isFinite(number) && number > 0 ? Math.round(number) : 0;
}

export function estimateTokens(text: string): number {
  return Math.max(1, Math.ceil(text.length / 4));
}

export function tokenTotals(
  usage: { prompt_tokens?: unknown; completion_tokens?: unknown; total_tokens?: unknown } | null,
  fallbackPrompt: string,
  fallbackReply: string,
): { prompt: number; completion: number; total: number } {
  const prompt = safeCount(usage?.prompt_tokens) || estimateTokens(fallbackPrompt);
  const completion = safeCount(usage?.completion_tokens) || estimateTokens(fallbackReply);
  const total = safeCount(usage?.total_tokens) || prompt + completion;
  return { prompt, completion, total };
}

/** Writes one accounting row. Failures are logged, never surfaced to the athlete. */
export async function logUsage(
  client: SupabaseClient,
  row: UsageRow,
): Promise<void> {
  const { error } = await client.from('ai_usage').insert({
    user_id: row.user_id,
    function_name: row.function_name,
    intent: row.intent ?? null,
    model: row.model ?? null,
    prompt_tokens: safeCount(row.prompt_tokens),
    completion_tokens: safeCount(row.completion_tokens),
    total_tokens: safeCount(row.total_tokens),
    latency_ms: Math.max(0, Math.round(row.latency_ms ?? 0)),
    status: row.status ?? 'ok',
  });
  if (error) console.warn('ai_usage insert failed', error.message);
}
