/**
 * Deterministic intent classification. This is a transparent rule-based
 * router, not a trained classifier: it only decides which retrieval sources,
 * context sections, and model tier a request needs. The answer itself is
 * always produced by the language model.
 */

export type IntentCategory =
  | 'greeting'
  | 'app_data'
  | 'exercise_technique'
  | 'programming'
  | 'nutrition'
  | 'recovery'
  | 'injury'
  | 'current_information'
  | 'general_fitness';

export type Intent = {
  category: IntentCategory;
  complexity: 'low' | 'medium' | 'high';
  needsWeb: boolean;
  needsKnowledge: boolean;
  needsExercise: boolean;
  needsHistory: boolean;
  requiresCare: boolean;
  /** Short, user-facing explanation of why retrieval was used. */
  reason: string;
};

type Rule = {
  category: Exclude<IntentCategory, 'general_fitness'>;
  pattern: RegExp;
};

const RULES: Rule[] = [
  {
    category: 'injury',
    pattern:
      /\b(pain|painful|hurt|hurts|injur\w*|strain\w*|sprain\w*|tendon\w*|rehab\w*|physio\w*|sore knee|bad shoulder|lower back|sciatica|hernia|imping\w*|mri|x-ray)\b/i,
  },
  {
    category: 'current_information',
    pattern:
      /\b(latest|newest|recent|research|stud(y|ies)|evidence|guideline[s]?|consensus|meta-analysis|systematic review|paper[s]?|journal|published|sources?|citation[s]?|cite|news|20(2[4-9]|3[0-9]))\b/i,
  },
  {
    category: 'nutrition',
    pattern:
      /\b(nutrition|diet|calorie[s]?|kcal|protein|carb[s]?|fat intake|macros?|supplement[s]?|creatine|weight loss|lose (weight|fat)|bulk\w*|cut\w*|eat(s|ing)?|meal[s]?|fasted|hydrat\w*)\b/i,
  },
  {
    category: 'recovery',
    pattern:
      /\b(recover\w*|sleep|rest day|deload|sore(ness)?|fatigue[d]?|stress|overtrain\w*|mobility work|stretch\w*|massage|foam roll\w*)\b/i,
  },
  {
    category: 'exercise_technique',
    pattern:
      /\b(form|technique|how (do|should) i|how to|perform\w*|cue[s]?|tempo|range of motion|grip|stance|brace|hinge|squat|deadlift|bench|press|row|pull-?up|push-?up|lunge|plank|curl|dip|carry|clean|snatch|thruster|muscle[s]?\b)/i,
  },
  {
    category: 'programming',
    pattern:
      /\b(program\w*|routine[s]?|split|sets?|reps?|reps? range|frequency|volume|intensity|progressive overload|periodi[sz]\w*|deload|mesocycle|workout plan|train(ing)? (day|week|schedule)|schedule|full body|upper.?lower|push.?pull|accessor\w*)\b/i,
  },
  {
    category: 'app_data',
    pattern:
      /\b(my (plan|workout|session|progress|history|schedule|goal[s]?|training)|today'?s? (workout|session|plan)|what should i (do|train)|next workout|this week|last (workout|session)|logged|personal record|pr\b|streak)\b/i,
  },
  {
    category: 'greeting',
    pattern: /^(hi|hey|hello|yo|good (morning|afternoon|evening)|thanks|thank you|who are you|what can you do)\b/i,
  },
];

const WEB_HINTS =
  /\b(latest|newest|recent|research|stud(y|ies)|evidence|guideline[s]?|consensus|meta-analysis|systematic review|paper[s]?|journal|published|sources?|citation[s]?|cite|news|updated|20(2[4-9]|3[0-9]))\b/i;

const HIGH_COMPLEXITY_HINTS =
  /\b(compare|trade-?off|why|explain|evidence|research|program design|periodi[sz]\w*|injur\w*|rehab\w*|pain|nutrition|diet|calorie[s]?|macro[s]?|deload|plateau)\b/i;

function hasAny(text: string, words: string[]): boolean {
  return words.some((word) => text.includes(word));
}

export function classifyIntent(message: string): Intent {
  const text = message.toLowerCase().trim();
  const category = RULES.find((rule) => rule.pattern.test(text))?.category ?? 'general_fitness';

  const words = text.split(/\s+/).filter(Boolean).length;
  const high =
    category === 'injury' ||
    category === 'current_information' ||
    (category === 'nutrition' && HIGH_COMPLEXITY_HINTS.test(text)) ||
    (category === 'programming' && HIGH_COMPLEXITY_HINTS.test(text)) ||
    words >= 70 ||
    (text.match(/\?/g)?.length ?? 0) >= 2;

  const complexity: Intent['complexity'] =
    category === 'greeting' || (category === 'app_data' && words <= 12)
      ? 'low'
      : high
        ? 'high'
        : 'medium';

  const needsWeb =
    category === 'current_information' ||
    WEB_HINTS.test(text) ||
    (category === 'nutrition' && /\b(evidence|research|guideline|study|latest)\b/i.test(text));

  const needsKnowledge = category !== 'greeting';
  const needsExercise =
    category === 'exercise_technique' || category === 'programming' || category === 'app_data';
  const needsHistory =
    category === 'app_data' ||
    category === 'programming' ||
    category === 'recovery' ||
    hasAny(text, ['my plan', 'my workout', 'my progress', 'my history', 'my training']);

  const reason = needsWeb
    ? 'May require current external evidence; live retrieval is attempted and cited.'
    : needsKnowledge
      ? 'Answered from the curated Forma knowledge base and verified exercise library.'
      : 'Conversational reply; no retrieval required.';

  return {
    category,
    complexity,
    needsWeb,
    needsKnowledge,
    needsExercise,
    needsHistory,
    requiresCare: category === 'injury' || category === 'nutrition',
    reason,
  };
}

const FOLLOW_UP_START =
  /^(and|also|so|but|what about|how about|why|how|does (that|it|this)|is (that|it|this)|can i|should i|what if|then|ok(ay)?[, ]|more)\b/i;

/**
 * Resolves short elliptical follow-ups ("what about the knees?") by anchoring
 * them to the previous athlete message. This is a lexical heuristic used for
 * retrieval only; the stored conversation is never rewritten.
 */
export function resolveFollowUp(
  message: string,
  previousUserMessages: string[],
): { query: string; resolved: boolean } {
  const trimmed = message.trim();
  const words = trimmed.split(/\s+/).filter(Boolean).length;
  const previous = [...previousUserMessages].reverse().find((item) => item.trim().length > 0);
  if (!previous) return { query: trimmed, resolved: false };
  if (words > 8 || !FOLLOW_UP_START.test(trimmed)) return { query: trimmed, resolved: false };
  if (/^(hi|hey|hello|thanks|thank you)\b/i.test(trimmed)) return { query: trimmed, resolved: false };
  return {
    query: `${previous.trim().slice(0, 240)}\nFollow-up: ${trimmed}`.slice(0, 500),
    resolved: true,
  };
}
