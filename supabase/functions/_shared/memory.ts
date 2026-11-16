import type { SupabaseClient } from 'npm:@supabase/supabase-js@2';
import { openAiChat } from './openai.ts';

const SUMMARY_PROMPT = `You maintain a compact memory of a fitness coaching conversation.
Write a factual summary in the third person of at most 140 words.
Include: the athlete's stated goals and constraints, injuries or limitations they mentioned, exercises they asked about, decisions or plans agreed, and open questions.
Do not add advice, diagnoses, or information that was not in the conversation.
Do not invent workout history or numbers. Return plain text only.`;

const KEEP_RECENT = 16;
const MIN_NEW_MESSAGES = 8;
const MIN_TOTAL_MESSAGES = 26;

type MessageRow = { role: string; content: string; created_at: string };

type RuntimeWithWaitUntil = {
  EdgeRuntime?: { waitUntil?: (promise: Promise<unknown>) => void };
};

export function runInBackground(task: Promise<unknown>): void {
  const runtime = (globalThis as RuntimeWithWaitUntil).EdgeRuntime;
  if (runtime?.waitUntil) {
    runtime.waitUntil(task);
  } else {
    task.catch(() => {});
  }
}

/**
 * Regenerates the saved conversation summary when enough new messages have
 * accumulated. Only older messages are summarised; the recent window is sent
 * to the model verbatim on every request.
 */
export async function refreshConversationSummary(
  client: SupabaseClient,
  conversationId: string,
  previousSummary: string | null,
  previousCount: number,
): Promise<void> {
  const { count, error: countError } = await client
    .from('coach_messages')
    .select('id', { count: 'exact', head: true })
    .eq('conversation_id', conversationId);

  if (countError || typeof count !== 'number') return;
  if (count < MIN_TOTAL_MESSAGES) return;
  if (count - previousCount < MIN_NEW_MESSAGES) return;

  const { data, error } = await client
    .from('coach_messages')
    .select('role, content, created_at')
    .eq('conversation_id', conversationId)
    .order('created_at', { ascending: true })
    .limit(140);

  if (error) return;
  const messages = (data ?? []) as MessageRow[];
  const older = messages.slice(0, Math.max(0, messages.length - KEEP_RECENT));
  if (older.length < 10) return;

  const transcript = older
    .map((message) => `${message.role === 'user' ? 'Athlete' : 'Coach'}: ${message.content.slice(0, 500)}`)
    .join('\n');

  const response = await openAiChat({
    json: false,
    temperature: 0.2,
    maxTokens: 260,
    retries: 1,
    timeoutMs: 30_000,
    messages: [
      { role: 'system', content: SUMMARY_PROMPT },
      {
        role: 'user',
        content: [
          previousSummary ? `## Existing summary\n${previousSummary}` : '',
          `## Conversation so far\n${transcript.slice(0, 9000)}`,
          'Update the summary so it covers this conversation. Return plain text only.',
        ]
          .filter(Boolean)
          .join('\n\n'),
      },
    ],
  });

  if (!response.ok) {
    await response.body?.cancel().catch(() => {});
    return;
  }

  const completion = (await response.json()) as { choices?: { message?: { content?: string } }[] };
  const summary = completion.choices?.[0]?.message?.content
    ?.replace(/<\/?[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .trim()
    .slice(0, 1400);
  if (!summary) return;

  await client
    .from('coach_conversations')
    .update({ summary, summary_message_count: count })
    .eq('id', conversationId);
}
