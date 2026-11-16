/**
 * Central configuration for the Forma AI pipeline. Every model name, limit,
 * and provider is read from Edge Function secrets with conservative defaults.
 * No secret value is ever embedded here.
 */

export type ModelTier = 'fast' | 'standard' | 'reasoning';

export const DEFAULT_MODELS: Record<ModelTier, string> = {
  fast: 'gpt-4o-mini',
  standard: 'gpt-4o-mini',
  reasoning: 'gpt-4o',
};

export function envValue(name: string): string | undefined {
  const deno = (globalThis as {
    Deno?: { env?: { get(name: string): string | undefined } };
  }).Deno;
  try {
    const value = deno?.env?.get(name)?.trim();
    return value ? value : undefined;
  } catch {
    return undefined;
  }
}

export function envFlag(name: string, fallback: boolean): boolean {
  const value = envValue(name)?.toLowerCase();
  if (!value) return fallback;
  if (['1', 'true', 'yes', 'on'].includes(value)) return true;
  if (['0', 'false', 'no', 'off'].includes(value)) return false;
  return fallback;
}

export function envInt(name: string, fallback: number, min: number, max: number): number {
  const parsed = Number(envValue(name));
  if (!Number.isFinite(parsed)) return fallback;
  return Math.max(min, Math.min(max, Math.round(parsed)));
}

/**
 * Tier-specific keys, then the Phase 2 `OPENAI_MODEL` compatibility key, then
 * the default. Reasoning is deliberately a separate key so a small model can
 * stay the default for ordinary questions.
 */
export function modelForTier(tier: ModelTier): string {
  const specific =
    tier === 'fast'
      ? envValue('OPENAI_MODEL_FAST')
      : tier === 'standard'
        ? envValue('OPENAI_MODEL_STANDARD')
        : envValue('OPENAI_MODEL_REASONING');
  if (specific) return specific;
  if (tier !== 'reasoning') {
    const legacy = envValue('OPENAI_MODEL');
    if (legacy) return legacy;
  }
  return DEFAULT_MODELS[tier];
}

export function embeddingModel(): string {
  return envValue('OPENAI_EMBEDDING_MODEL') ?? 'text-embedding-3-small';
}

export function embeddingDimensions(): number {
  return envInt('OPENAI_EMBEDDING_DIMENSIONS', 1536, 256, 3072);
}

export function webSearchProvider(): 'tavily' | 'brave' | 'none' {
  const value = envValue('WEB_SEARCH_PROVIDER')?.toLowerCase();
  if (value === 'brave') return 'brave';
  if (value === 'none' || value === 'off') return 'none';
  return 'tavily';
}

export function webSearchKey(provider: 'tavily' | 'brave' | 'none'): string | undefined {
  if (provider === 'tavily') return envValue('TAVILY_API_KEY');
  if (provider === 'brave') return envValue('BRAVE_API_KEY');
  return undefined;
}

export const LIMITS = {
  chatPerMinute: envInt('AI_CHAT_PER_MINUTE', 8, 1, 60),
  chatPerDay: envInt('AI_CHAT_PER_DAY', 150, 1, 5000),
  planPerDay: envInt('AI_PLAN_PER_DAY', 12, 1, 200),
  knowledgeTopK: envInt('KNOWLEDGE_TOP_K', 5, 1, 10),
  knowledgeMinSimilarity: envInt('KNOWLEDGE_MIN_SIMILARITY_PCT', 22, 0, 90) / 100,
  webResults: envInt('WEB_SEARCH_RESULTS', 4, 1, 8),
  webCacheMinutes: envInt('WEB_SEARCH_CACHE_MINUTES', 180, 5, 1440),
  webTimeoutMs: envInt('WEB_SEARCH_TIMEOUT_MS', 8000, 1000, 20000),
  knowledgeTimeoutMs: envInt('KNOWLEDGE_TIMEOUT_MS', 9000, 1000, 20000),
  contextCharBudget: envInt('AI_CONTEXT_CHAR_BUDGET', 16000, 4000, 40000),
  historyMessages: envInt('AI_HISTORY_MESSAGES', 16, 6, 30),
  maxOutputTokens: envInt('AI_MAX_OUTPUT_TOKENS', 800, 200, 2000),
  /** Plan freshness: older plans are disclosed to the model and the athlete. */
  planStaleDays: envInt('AI_PLAN_STALE_DAYS', 42, 7, 365),
};

export function ingestionSecret(): string | undefined {
  return envValue('KNOWLEDGE_INGEST_SECRET');
}
