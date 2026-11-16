#!/usr/bin/env node
// Ingests curated knowledge documents into Supabase through the protected
// knowledge-ingest Edge Function. Real embeddings are generated server-side by
// OpenAI; this script never fabricates vectors or citations.
//
// Required environment:
//   FORMA_SUPABASE_URL    e.g. https://<project>.supabase.co
//   FORMA_SUPABASE_ANON_KEY
//   FORMA_INGEST_SECRET  must match KNOWLEDGE_INGEST_SECRET on the function
//
// Usage:
//   node scripts/ingest-knowledge.mjs [path-to-json] [--allow-lexical]

import { readFile } from 'node:fs/promises';
import process from 'node:process';

const args = process.argv.slice(2);
const allowLexical = args.includes('--allow-lexical');
const file = args.find((arg) => !arg.startsWith('--')) ?? 'supabase/knowledge/forma-coaching-notes.json';

const url = process.env.FORMA_SUPABASE_URL?.replace(/\/+$/, '');
const anonKey = process.env.FORMA_SUPABASE_ANON_KEY;
const secret = process.env.FORMA_INGEST_SECRET;

if (!url || !anonKey || !secret) {
  console.error('Set FORMA_SUPABASE_URL, FORMA_SUPABASE_ANON_KEY, and FORMA_INGEST_SECRET.');
  process.exit(1);
}

const payload = JSON.parse(await readFile(file, 'utf8'));
const documents = Array.isArray(payload) ? payload : payload.documents;
if (!Array.isArray(documents) || documents.length === 0) {
  console.error(`${file} does not contain a documents array.`);
  process.exit(1);
}

const response = await fetch(`${url}/functions/v1/knowledge-ingest`, {
  method: 'POST',
  headers: {
    Authorization: `Bearer ${anonKey}`,
    apikey: anonKey,
    'Content-Type': 'application/json',
    'x-ingest-secret': secret,
  },
  body: JSON.stringify({ documents, allowLexical }),
});

const body = await response.json().catch(() => ({}));
if (!response.ok) {
  console.error(`Ingestion failed (${response.status}):`, body.error ?? body);
  process.exit(1);
}

console.log(`Documents upserted: ${body.documentsUpserted}`);
console.log(`Chunks stored: ${body.chunksStored}`);
console.log(`Chunks with real embeddings: ${body.chunksEmbedded}`);
console.log(`Vector retrieval ready: ${body.vectorReady ? 'yes' : 'no (lexical fallback only)'}`);
for (const entry of body.results ?? []) {
  console.log(`- ${entry.slug}: ${entry.chunks} chunk(s), ${entry.embedded} embedded`);
}
for (const entry of body.rejected ?? []) {
  console.warn(`Rejected ${entry.slug}: ${entry.reason}`);
}
if ((body.rejected ?? []).length > 0) process.exitCode = 2;
