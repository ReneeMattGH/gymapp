import { adminClient } from '../_shared/auth.ts';
import { embeddingDimensions, ingestionSecret } from '../_shared/config.ts';
import { json, methodNotAllowed, preflight } from '../_shared/http.ts';
import { chunkDocument, embedTexts } from '../_shared/knowledge.ts';
import { detectPromptInjection } from '../_shared/safety.ts';

type IncomingDocument = {
  slug?: unknown;
  title?: unknown;
  publisher?: unknown;
  url?: unknown;
  publishedAt?: unknown;
  license?: unknown;
  trust?: unknown;
  topic?: unknown;
  summary?: unknown;
  content?: unknown;
};

const TRUST_TIERS = new Set(['official', 'peer_reviewed', 'reputable', 'community']);

function text(value: unknown, max: number): string {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}

function optionalUrl(value: unknown): string | null {
  const raw = text(value, 500);
  if (!raw) return null;
  try {
    const parsed = new URL(raw);
    return parsed.protocol === 'https:' ? parsed.toString() : null;
  } catch {
    return null;
  }
}

function evaluate(document: IncomingDocument): { ok: true; value: Record<string, unknown> } | { ok: false; reason: string } {
  const slug = text(document.slug, 80).toLowerCase();
  const title = text(document.title, 200);
  const publisher = text(document.publisher, 160);
  const content = text(document.content, 20_000);
  const topic = text(document.topic, 80);
  const trust = text(document.trust, 30) || 'reputable';

  if (!/^[a-z0-9][a-z0-9-]{1,80}$/.test(slug)) return { ok: false, reason: 'slug must be kebab-case' };
  if (title.length < 3) return { ok: false, reason: 'title is required' };
  if (!publisher) return { ok: false, reason: 'publisher is required' };
  if (content.length < 200) return { ok: false, reason: 'content is too short to be a useful source' };
  if (!topic) return { ok: false, reason: 'topic is required' };
  if (!TRUST_TIERS.has(trust)) return { ok: false, reason: 'trust must be official, peer_reviewed, reputable, or community' };
  if (detectPromptInjection(content) || detectPromptInjection(title)) {
    return { ok: false, reason: 'content contains instruction-injection patterns' };
  }

  const url = optionalUrl(document.url);
  if (text(document.url, 500) && !url) {
    return { ok: false, reason: 'url must be a valid https URL when provided' };
  }
  const publishedAtRaw = text(document.publishedAt, 10);
  const publishedAt = /^\d{4}-\d{2}-\d{2}$/.test(publishedAtRaw) ? publishedAtRaw : null;

  return {
    ok: true,
    value: {
      slug,
      title,
      publisher,
      url,
      published_at: publishedAt,
      license: text(document.license, 200) || null,
      trust,
      topic,
      summary: text(document.summary, 500) || null,
      content,
    },
  };
}

Deno.serve(async (request: Request) => {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== 'POST') return methodNotAllowed();

  const secret = ingestionSecret();
  if (!secret) {
    return json({ error: 'KNOWLEDGE_INGEST_SECRET is not configured on the server.' }, 503);
  }
  const provided =
    request.headers.get('x-ingest-secret') ??
    request.headers.get('authorization')?.replace(/^Bearer\s+/i, '');
  if (!provided || provided !== secret) {
    return json({ error: 'Invalid ingestion credentials.' }, 401);
  }

  const body = (await request.json().catch(() => null)) as
    | { documents?: IncomingDocument[]; allowLexical?: boolean }
    | null;
  const documents = Array.isArray(body?.documents) ? body!.documents : [];
  if (documents.length === 0) return json({ error: 'No documents were supplied.' }, 400);
  if (documents.length > 30) return json({ error: 'Send at most 30 documents per request.' }, 400);

  const allowLexical = body?.allowLexical === true;
  const hasEmbeddingKey = Boolean((globalThis as { Deno?: { env?: { get(name: string): string | undefined } } }).Deno?.env?.get('OPENAI_API_KEY'));
  if (!hasEmbeddingKey && !allowLexical) {
    return json(
      {
        error:
          'OPENAI_API_KEY is not configured, so real embeddings cannot be generated. Set allowLexical to ingest with lexical-only retrieval.',
      },
      503,
    );
  }
  if (hasEmbeddingKey && embeddingDimensions() !== 1536) {
    return json(
      {
        error:
          'OPENAI_EMBEDDING_DIMENSIONS must be 1536 because the knowledge_chunks column and match_knowledge_chunks use vector(1536). Change both in a migration before changing this setting.',
      },
      500,
    );
  }

  let admin;
  try {
    admin = adminClient();
  } catch (error) {
    return json(
      { error: error instanceof Error ? error.message : 'Service role is not configured.' },
      503,
    );
  }

  const results: Record<string, unknown>[] = [];
  const rejected: { slug: string; reason: string }[] = [];
  let documentsUpserted = 0;
  let chunksStored = 0;
  let chunksEmbedded = 0;

  for (const candidate of documents) {
    const evaluated = evaluate(candidate);
    if (!evaluated.ok) {
      rejected.push({ slug: text(candidate.slug, 80) || '(missing)', reason: evaluated.reason });
      continue;
    }
    const value = evaluated.value;

    const chunks = chunkDocument(String(value.content));
    if (chunks.length === 0) {
      rejected.push({ slug: String(value.slug), reason: 'content could not be chunked' });
      continue;
    }
    const embeddings = await embedTexts(chunks);

    const { data: document, error: documentError } = await admin
      .from('knowledge_documents')
      .upsert(
        {
          slug: value.slug,
          title: value.title,
          publisher: value.publisher,
          url: value.url,
          published_at: value.published_at,
          license: value.license,
          trust: value.trust,
          topic: value.topic,
          summary: value.summary,
          updated_at: new Date().toISOString(),
        },
        { onConflict: 'slug' },
      )
      .select('id')
      .single();

    if (documentError || !document) {
      rejected.push({
        slug: String(value.slug),
        reason: documentError?.message ?? 'document upsert failed',
      });
      continue;
    }

    const { error: deleteError } = await admin
      .from('knowledge_chunks')
      .delete()
      .eq('document_id', document.id);
    if (deleteError) {
      rejected.push({ slug: String(value.slug), reason: `could not replace chunks: ${deleteError.message}` });
      continue;
    }

    const rows = chunks.map((content, index) => ({
      document_id: document.id,
      chunk_index: index,
      content,
      token_count: Math.max(1, Math.ceil(content.length / 4)),
      embedding: embeddings[index] ?? null,
    }));
    const { error: insertError } = await admin.from('knowledge_chunks').insert(rows);
    if (insertError) {
      rejected.push({ slug: String(value.slug), reason: insertError.message });
      continue;
    }

    documentsUpserted += 1;
    chunksStored += rows.length;
    chunksEmbedded += embeddings.filter(Boolean).length;
    results.push({
      slug: value.slug,
      chunks: rows.length,
      embedded: embeddings.filter(Boolean).length,
      vectorReady: embeddings.every(Boolean),
    });
  }

  return json({
    documentsUpserted,
    chunksStored,
    chunksEmbedded,
    vectorReady: chunksEmbedded === chunksStored && chunksStored > 0,
    results,
    rejected,
  });
});
