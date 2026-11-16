/**
 * Deterministic post-generation checks. The model never grades itself here:
 * URLs, citation markers, and exercise identifiers are compared against the
 * exact records that were retrieved for this request.
 */

export type CitedSource = {
  id: string;
  kind: 'web' | 'knowledge' | 'exercise';
  title?: string;
  url?: string | null;
  publishedAt?: string | null;
  trust?: string | null;
};

export type AccuracyIssue = {
  code:
    | 'unverified_url'
    | 'invalid_citation'
    | 'unknown_exercise_id'
    | 'missing_citation'
    | 'unverified_claim';
  severity: 'warning' | 'error';
  message: string;
};

export type AccuracyReport = {
  ok: boolean;
  issues: AccuracyIssue[];
  unverified: boolean;
  /** Text with fabricated URLs and invalid markers removed. */
  sanitized: string;
  urlsChecked: number;
};

export type AccuracyOptions = {
  webSources?: CitedSource[];
  knowledgeSources?: CitedSource[];
  exerciseIds?: string[];
  /** True when the athlete asked for current information. */
  expectsCurrentEvidence?: boolean;
};

const URL_PATTERN = /https?:\/\/[^\s<>"'`)\]}]+/gi;
const MARKDOWN_LINK = /\[([^\]]{1,140})\]\((https?:\/\/[^)\s]+)\)/gi;
const CITATION = /\[(K|W|E)(\d{1,2})\]/g;
const EXERCISE_ID_CLAIM =
  /\b(?:exercise\s*id|exerciseId|exercise\s+#|exercise\s+number)\s*[:=]?\s*`?([a-z0-9][a-z0-9-]{2,60})`?/gi;
const BACKTICKED_ID = /`([a-z][a-z0-9]*(?:-[a-z0-9]+){1,6})`/g;

function trimUrl(value: string): string {
  return value.replace(/[.,;:!?]+$/g, '');
}

export function normalizeUrl(value: string): string {
  try {
    const url = new URL(trimUrl(value.trim()));
    const host = url.hostname.toLowerCase().replace(/^www\./, '');
    const path = url.pathname.replace(/\/+$/, '');
    const params = new URLSearchParams(url.search);
    for (const key of [...params.keys()]) {
      if (/^(utm_.*|fbclid|gclid|ref|source)$/i.test(key)) params.delete(key);
    }
    params.sort();
    const query = params.toString();
    return `${host}${path}${query ? `?${query}` : ''}`;
  } catch {
    return '';
  }
}

function extractUrls(text: string): string[] {
  return (text.match(URL_PATTERN) ?? []).map(trimUrl).filter(Boolean);
}

export function verifyReply(text: string, options: AccuracyOptions): AccuracyReport {
  const issues: AccuracyIssue[] = [];
  const web = options.webSources ?? [];
  const knowledge = options.knowledgeSources ?? [];
  const exerciseIds = new Set(options.exerciseIds ?? []);

  const allowed = new Set<string>();
  for (const source of [...web, ...knowledge]) {
    if (source.url) {
      const normalized = normalizeUrl(source.url);
      if (normalized) allowed.add(normalized);
    }
  }

  const urls = extractUrls(text);
  for (const url of urls) {
    const normalized = normalizeUrl(url);
    if (!normalized || !allowed.has(normalized)) {
      issues.push({
        code: 'unverified_url',
        severity: 'error',
        message: `The reply linked to a URL that was not among the retrieved sources: ${url}`,
      });
    }
  }

  const markers = [...text.matchAll(CITATION)];
  for (const marker of markers) {
    const kind = marker[1];
    const index = Number(marker[2]);
    const limit =
      kind === 'K' ? knowledge.length : kind === 'W' ? web.length : exerciseIds.size;
    if (!Number.isFinite(index) || index < 1 || index > limit) {
      issues.push({
        code: 'invalid_citation',
        severity: 'error',
        message: `The reply used citation [${marker[1]}${marker[2]}] but that source was not retrieved.`,
      });
    }
  }

  const claimedIds = new Set<string>();
  for (const match of text.matchAll(EXERCISE_ID_CLAIM)) claimedIds.add(match[1]);
  for (const match of text.matchAll(BACKTICKED_ID)) {
    if (exerciseIds.has(match[1])) continue;
    // Backticked values that look like library slugs are only treated as
    // exercise claims when the surrounding sentence mentions the library.
    const index = match.index ?? 0;
    const window = text.slice(Math.max(0, index - 120), index + 120).toLowerCase();
    if (/(library|verified|exercise|movement|record)/.test(window)) claimedIds.add(match[1]);
  }
  for (const id of claimedIds) {
    if (exerciseIds.size > 0 && !exerciseIds.has(id)) {
      issues.push({
        code: 'unknown_exercise_id',
        severity: 'error',
        message: `The reply referenced "${id}", which is not in the verified Forma library.`,
      });
    }
  }

  const expectsCurrent = options.expectsCurrentEvidence === true;
  const hasVerifiedSource = web.length > 0 || knowledge.length > 0;
  if (expectsCurrent && !hasVerifiedSource && urls.length > 0) {
    issues.push({
      code: 'unverified_claim',
      severity: 'error',
      message: 'The reply cited a web link although live retrieval returned no verified source.',
    });
  }

  const sanitized = sanitizeReply(text, { allowed, knowledgeCount: knowledge.length, webCount: web.length, exerciseCount: exerciseIds.size });
  const errors = issues.filter((issue) => issue.severity === 'error');
  return {
    ok: errors.length === 0,
    issues,
    unverified: errors.length > 0,
    sanitized,
    urlsChecked: urls.length,
  };
}

function sanitizeReply(
  text: string,
  counts: { allowed: Set<string>; knowledgeCount: number; webCount: number; exerciseCount: number },
): string {
  let output = text.replace(MARKDOWN_LINK, (whole, label: string, url: string) => {
    const normalized = normalizeUrl(url);
    return normalized && counts.allowed.has(normalized) ? whole : label;
  });

  output = output.replace(URL_PATTERN, (url) => {
    const normalized = normalizeUrl(url);
    return normalized && counts.allowed.has(normalized) ? url : '';
  });

  output = output.replace(CITATION, (whole, kind: string, rawIndex: string) => {
    const index = Number(rawIndex);
    const limit =
      kind === 'K' ? counts.knowledgeCount : kind === 'W' ? counts.webCount : counts.exerciseCount;
    return index >= 1 && index <= limit ? whole : '';
  });

  return output.replace(/[ \t]{2,}/g, ' ').replace(/\n{3,}/g, '\n\n').trim();
}

export function uncertaintyNote(reasons: string[]): string {
  const unique = [...new Set(reasons.filter(Boolean))];
  if (unique.length === 0) return '';
  return `\n\n_Uncertainty: ${unique.join(' ')} Treat this as general guidance rather than a verified finding._`;
}
