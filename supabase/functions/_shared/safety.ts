/**
 * Best-effort safety screening for model text before it is persisted or shown
 * as final. This is intentionally conservative and shallow: the system prompt
 * does the heavy lifting. It blocks clear incitement to unsafe behaviour while
 * ignoring sentences that are already negated ("never train through pain").
 */

export type SafetyVerdict = { ok: true } | { ok: false; reason: string };

const NEGATIONS = [
  'not', "don't", 'do not', 'never', 'avoid', 'stop', "shouldn't", 'should not',
  'must not', 'no ', 'without', "can't", 'cannot',
];

const RULES: { reason: string; pattern: RegExp }[] = [
  {
    reason: 'encourages_training_through_pain',
    pattern: /\b(ignore|push through|train through|work through|fight through)\s+(the\s+)?pain\b/i,
  },
  {
    reason: 'diagnosis_or_treatment',
    pattern:
      /\b(you (likely )?have|this (is|looks like)|you are suffering from)\s+(a |an )?(tendinitis|tendonitis|hernia|tear|fracture|stress fracture|impingement|arthritis|sciatica|diagnosis)\b/i,
  },
  {
    reason: 'guaranteed_results',
    pattern: /\b(guaranteed|guarantees|will definitely)\b[^.]{0,80}\b(lose|gain|drop|add)\b/i,
  },
  {
    reason: 'rapid_extreme_weight_loss',
    pattern:
      /\b(lose|drop|shed)\s+\d+(\.\d+)?\s*(kg|kgs|lb|lbs|pounds)\s+(in|within)\s+\d+\s*(day|days|week|weeks)\b/i,
  },
  {
    reason: 'extreme_calorie_restriction',
    pattern:
      /\b(eat|consume|limit yourself to)\s+(fewer than|under|less than|only)\s+\d{3,4}\s*(calories|kcal)\b/i,
  },
  {
    reason: 'dangerous_volume',
    pattern: /\b\d{2,}\s*sets\s+(per|of|each)\s+(muscle|exercise|day)\b/i,
  },
  {
    reason: 'ignore_professional_advice',
    pattern: /\b(ignore|disregard)\s+(your\s+)?(doctor|physician|physio|physical therapist|clinician)\b/i,
  },
];

function sentenceIsNegated(sentence: string): boolean {
  const lower = sentence.toLowerCase();
  return NEGATIONS.some((token) => lower.includes(token));
}

export function screenReply(text: string): SafetyVerdict {
  const sentences = text.split(/(?<=[.!?])\s+/);
  for (const sentence of sentences) {
    if (!sentence.trim() || sentenceIsNegated(sentence)) continue;
    for (const rule of RULES) {
      if (rule.pattern.test(sentence)) return { ok: false, reason: rule.reason };
    }
  }
  return { ok: true };
}

const BLOCKED_MESSAGE =
  'That draft response did not meet Forma safety standards, so it was withheld. Try asking in a different way.';

export function safetyMessage(): string {
  return BLOCKED_MESSAGE;
}
