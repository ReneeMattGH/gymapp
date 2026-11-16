import { envValue, modelForTier, type ModelTier } from './config.ts';
import type { Intent } from './intent.ts';

export type ModelRoute = {
  tier: ModelTier;
  model: string;
  /** Stable, non-sensitive label the client can display. */
  label: 'fast' | 'standard' | 'reasoning';
  /** Used once when the provider reports the chosen model is unavailable. */
  fallbackModel: string;
  why: string;
};

function fallbackTier(tier: ModelTier): ModelTier {
  return tier === 'standard' ? 'fast' : 'standard';
}

/**
 * Picks the smallest model that can handle the request. Live research, injury
 * questions, and multi-part reasoning get the reasoning tier; greetings and
 * simple app-data lookups stay on the fast tier.
 */
export function routeModel(intent: Intent): ModelRoute {
  let tier: ModelTier = 'standard';

  if (intent.category === 'greeting' || intent.complexity === 'low') {
    tier = 'fast';
  } else if (
    intent.complexity === 'high' ||
    intent.needsWeb ||
    intent.requiresCare ||
    intent.category === 'current_information'
  ) {
    tier = 'reasoning';
  }

  const tierEnabled = envValue('AI_MODEL_ROUTING')?.toLowerCase() !== 'off';
  if (!tierEnabled) tier = 'standard';

  return {
    tier,
    model: modelForTier(tier),
    label: tier,
    fallbackModel: modelForTier(fallbackTier(tier)),
    why: tierEnabled
      ? `intent=${intent.category}; complexity=${intent.complexity}; retrieval=${intent.needsWeb ? 'live+knowledge' : 'knowledge'}`
      : 'model routing disabled; standard tier',
  };
}

/** Plan generation is a structured, high-stakes task: reasoning tier by default. */
export function routePlanModel(): ModelRoute {
  const tier: ModelTier = envValue('AI_MODEL_ROUTING')?.toLowerCase() === 'off' ? 'standard' : 'reasoning';
  return {
    tier,
    model: modelForTier(tier),
    label: tier,
    fallbackModel: modelForTier(fallbackTier(tier)),
    why: 'structured plan generation with deterministic validation',
  };
}

/** Short daily notes do not need a reasoning model. */
export function routeInsightModel(): ModelRoute {
  const tier: ModelTier = envValue('AI_MODEL_ROUTING')?.toLowerCase() === 'off' ? 'standard' : 'fast';
  return {
    tier,
    model: modelForTier(tier),
    label: tier,
    fallbackModel: modelForTier(fallbackTier(tier)),
    why: 'short note from already-loaded context',
  };
}
