/**
 * Best-effort safety screening for model text before it is persisted or shown
 * as final. This is intentionally conservative and shallow: the system prompt
 * does the heavy lifting. It blocks clear incitement to unsafe behaviour while
 * ignoring sentences that are already negated ("never train through pain").
 *
 * Retrieved web and knowledge text is untrusted input. It is screened for
 * instruction-injection patterns before it is placed in a prompt.
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
  {
    reason: 'encourages_disordered_eating',
    pattern:
      /\b(skip(ping)? meals?|not eat(ing)?|starve|purge|make yourself (sick|throw up)|earn your food|punish yourself with (cardio|exercise))\b/i,
  },
  {
    reason: 'medication_or_supplement_dosing',
    pattern:
      /\b(take|use|inject|cycle)\s+\d+(\.\d+)?\s*(mg|mcg|iu|ml)\b|\b(dosage|dose)\s+(of|for)\s+(steroids?|clenbuterol|trenbolone|testosterone|insulin|ephedrine)\b/i,
  },
  {
    reason: 'training_through_illness',
    pattern: /\b(train|work out|lift)\s+(through|with)\s+(a\s+)?(fever|flu|illness|concussion)\b/i,
  },
  {
    reason: 'self_harm',
    pattern: /\b(hurt yourself|self[- ]harm|cut yourself|end your life)\b/i,
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

const INJECTION_PATTERNS: RegExp[] = [
  /\b(ignore|disregard|forget)\s+(all\s+)?(previous|prior|above|earlier)\s+(instructions?|prompts?|rules?)\b/i,
  /\byou\s+are\s+now\b[^.]{0,60}\b(assistant|model|system|developer)\b/i,
  /\b(system|developer)\s*(prompt|message)\b/i,
  /\b(reveal|print|show|repeat)\s+(your\s+)?(system|hidden|internal)\s+(prompt|instructions?)\b/i,
  /\bnew\s+instructions?\s*:/i,
  /\boverride\s+(the\s+)?(safety|system)\b/i,
  /<\|(im_start|im_end|system|assistant)\|>/i,
];

export function detectPromptInjection(text: string): boolean {
  return INJECTION_PATTERNS.some((pattern) => pattern.test(text));
}

/**
 * Strips instruction-like lines from retrieved content and caps its length.
 * The caller still wraps the result in an explicit "untrusted data" block.
 */
export function sanitizeRetrievedText(text: string, maxLength = 1800): string {
  const lines = text
    .replace(/\u0000/g, '')
    .split(/\r?\n/)
    .filter((line) => !detectPromptInjection(line))
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim();
  return lines.slice(0, maxLength);
}

/** True when the athlete's message may need a cautious, non-diagnostic reply. */
export function promptNeedsCare(message: string): boolean {
  return /\b(pain|injur\w*|pregnan\w*|eating disorder|anorexia|bulimia|suicid\w*|self[- ]harm|chest pain|numbness|dizz\w*|concussion|surgery|post-?op)\b/i.test(
    message,
  );
}
