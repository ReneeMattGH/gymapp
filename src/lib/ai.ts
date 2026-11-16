import type { AiPlanPayload } from '@/lib/plan';
import { supabaseConfig } from '@/lib/env';
import { requireSupabase } from '@/lib/supabase';

async function authHeaders(): Promise<Record<string, string>> {
  const { data } = await requireSupabase().auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error('Your session has expired. Sign in again to use the AI coach.');
  return {
    Authorization: `Bearer ${token}`,
    apikey: supabaseConfig.anonKey,
    'Content-Type': 'application/json',
  };
}

async function readError(response: Response): Promise<string> {
  const text = await response.text().catch(() => '');
  try {
    const parsed = JSON.parse(text) as { error?: string; message?: string };
    return parsed.error ?? parsed.message ?? `Request failed with status ${response.status}.`;
  } catch {
    return text.trim() || `Request failed with status ${response.status}.`;
  }
}

export type CoachStreamEvent = { type: 'delta'; text: string } | { type: 'done' } | { type: 'error'; message: string };

export async function streamCoachReply(params: {
  conversationId: string;
  message: string;
  onDelta: (text: string) => void;
  signal?: AbortSignal;
}): Promise<string> {
  const headers = await authHeaders();
  const response = await fetch(`${supabaseConfig.url}/functions/v1/coach-chat`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ conversationId: params.conversationId, message: params.message }),
    signal: params.signal,
  });

  if (!response.ok) {
    throw new Error(await readError(response));
  }

  const contentType = response.headers.get('content-type') ?? '';
  if (!response.body || contentType.includes('application/json')) {
    const json = (await response.json()) as { reply?: string; error?: string };
    if (json.error) throw new Error(json.error);
    const reply = json.reply ?? '';
    if (reply) params.onDelta(reply);
    return reply;
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let full = '';
  let finished = false;

  while (!finished) {
    const { value, done } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    const lines = buffer.split('\n');
    buffer = lines.pop() ?? '';

    for (const rawLine of lines) {
      const line = rawLine.trim();
      if (!line.startsWith('data:')) continue;
      const payload = line.slice(5).trim();
      if (!payload || payload === '[DONE]') {
        finished = true;
        break;
      }
      try {
        const event = JSON.parse(payload) as CoachStreamEvent;
        if (event.type === 'delta' && event.text) {
          full += event.text;
          params.onDelta(event.text);
        } else if (event.type === 'error') {
          throw new Error(event.message || 'The coach ran into a problem.');
        } else if (event.type === 'done') {
          finished = true;
        }
      } catch (error) {
        if (error instanceof Error && error.message !== 'Unexpected end of JSON input') {
          throw error;
        }
      }
    }
  }

  return full;
}

export async function requestAiPlan(): Promise<AiPlanPayload> {
  const headers = await authHeaders();
  const response = await fetch(`${supabaseConfig.url}/functions/v1/coach-plan`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ action: 'generate_plan' }),
  });
  if (!response.ok) throw new Error(await readError(response));
  const json = (await response.json()) as { plan?: AiPlanPayload; error?: string };
  if (json.error) throw new Error(json.error);
  if (!json.plan) throw new Error('The AI coach did not return a plan.');
  return json.plan;
}

export async function requestDailyInsight(): Promise<string> {
  const headers = await authHeaders();
  const response = await fetch(`${supabaseConfig.url}/functions/v1/coach-plan`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ action: 'daily_insight' }),
  });
  if (!response.ok) throw new Error(await readError(response));
  const json = (await response.json()) as { insight?: string; error?: string };
  if (json.error) throw new Error(json.error);
  if (!json.insight) throw new Error('The AI coach did not return an insight.');
  return json.insight;
}

export const aiConfigured = supabaseConfig.isConfigured;
