import { requireEnv } from './http.ts';

const OPENAI_URL = 'https://api.openai.com/v1/chat/completions';
const RETRYABLE_STATUS = new Set([408, 409, 425, 429, 500, 502, 503, 504]);

export type ChatMessage = { role: 'system' | 'user' | 'assistant'; content: string };

export function openAiModel(): string {
  return Deno.env.get('OPENAI_MODEL')?.trim() || 'gpt-4o-mini';
}

/** Signal that aborts when either the caller cancels or the deadline passes. */
function withTimeout(timeoutMs: number, external?: AbortSignal): AbortSignal {
  const timeout = AbortSignal.timeout(timeoutMs);
  if (!external) return timeout;
  const anySignal = (AbortSignal as unknown as { any?: (signals: AbortSignal[]) => AbortSignal }).any;
  return anySignal ? anySignal([external, timeout]) : timeout;
}

function delay(ms: number, signal?: AbortSignal): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(new DOMException('Aborted', 'AbortError'));
      return;
    }
    const timer = setTimeout(resolve, ms);
    signal?.addEventListener(
      'abort',
      () => {
        clearTimeout(timer);
        reject(new DOMException('Aborted', 'AbortError'));
      },
      { once: true },
    );
  });
}

async function requestOnce(params: Parameters<typeof openAiChat>[0]): Promise<Response> {
  const key = requireEnv('OPENAI_API_KEY');
  const timeoutMs = params.timeoutMs ?? (params.stream ? 60_000 : 45_000);
  return await fetch(OPENAI_URL, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: params.model ?? openAiModel(),
      messages: params.messages,
      temperature: params.temperature ?? 0.6,
      max_tokens: params.maxTokens ?? 700,
      stream: Boolean(params.stream),
      ...(params.stream ? { stream_options: { include_usage: true } } : {}),
      ...(params.json ? { response_format: { type: 'json_object' } } : {}),
    }),
    signal: withTimeout(timeoutMs, params.signal),
  });
}

export async function openAiChat(params: {
  messages: ChatMessage[];
  json?: boolean;
  temperature?: number;
  maxTokens?: number;
  stream?: boolean;
  signal?: AbortSignal;
  timeoutMs?: number;
  retries?: number;
  /** Explicit model from the router. Falls back to OPENAI_MODEL. */
  model?: string;
  /** Tried once if the provider says the configured model does not exist. */
  fallbackModel?: string;
}): Promise<Response> {
  const retries = Math.max(0, Math.min(params.retries ?? 2, 3));
  let model = params.model ?? openAiModel();
  let usedFallback = false;
  let attempt = 0;
  let lastError: unknown = null;

  while (attempt <= retries) {
    if (params.signal?.aborted) throw new DOMException('Aborted', 'AbortError');
    try {
      const response = await requestOnce({ ...params, model });

      if (response.status === 404 && !usedFallback && params.fallbackModel && params.fallbackModel !== model) {
        await response.body?.cancel().catch(() => {});
        console.warn('configured model unavailable; retrying once with the fallback model');
        model = params.fallbackModel;
        usedFallback = true;
        continue;
      }
      if (response.status === 404) {
        return response;
      }
      if (!RETRYABLE_STATUS.has(response.status) || attempt === retries) return response;

      // Drain the failed body so the connection can be reused.
      await response.body?.cancel().catch(() => {});
      const retryAfter = Number(response.headers.get('retry-after'));
      const backoff = Number.isFinite(retryAfter) && retryAfter > 0
        ? retryAfter * 1000
        : 600 * 2 ** attempt + Math.floor(Math.random() * 250);
      await delay(Math.min(backoff, 8_000), params.signal);
      attempt += 1;
    } catch (error) {
      if (params.signal?.aborted) throw new DOMException('Aborted', 'AbortError');
      lastError = error;
      if (attempt === retries) throw error;
      await delay(600 * 2 ** attempt + Math.floor(Math.random() * 250), params.signal);
      attempt += 1;
    }
  }

  throw lastError instanceof Error ? lastError : new Error('The AI service could not be reached.');
}

/** Maps an upstream failure to a safe, actionable message (never the raw body). */
export function openAiErrorMessage(status: number): string {
  if (status === 429) return 'The AI coach is busy right now. Please try again in a moment.';
  if (status === 401 || status === 403) {
    return 'The AI service credentials are not configured correctly on the server.';
  }
  if (status === 408 || status === 504) return 'The AI coach took too long to respond. Please try again.';
  if (status === 400) return 'The AI service rejected that request. Try a shorter or simpler message.';
  if (status >= 500) return 'The AI service is temporarily unavailable. Please try again shortly.';
  return 'The AI service could not complete the request. Please try again.';
}

export async function openAiError(response: Response): Promise<string> {
  // Read and discard the body; it may contain provider details we do not surface.
  await response.text().catch(() => '');
  return openAiErrorMessage(response.status);
}

/** Strips an accidental markdown fence before JSON.parse. */
export function stripCodeFence(value: string): string {
  const trimmed = value.trim();
  if (!trimmed.startsWith('```')) return trimmed;
  return trimmed.replace(/^```(?:json)?\s*/i, '').replace(/```\s*$/, '').trim();
}
