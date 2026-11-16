// Retrieval quality evaluation over the real Forma corpus. This measures the
// lexical fallback deterministically in Node; it does not pretend to exercise
// pgvector. A live vector run needs an ingested database and credentials and is
// a separate, explicitly reported step.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadTsModule } from './loadTsModule.mjs';

const root = new URL('../', import.meta.url).pathname;
const corpus = JSON.parse(
  readFileSync(`${root}supabase/knowledge/forma-coaching-notes.json`, 'utf8'),
);
const evaluation = JSON.parse(
  readFileSync(`${root}supabase/knowledge/eval-retrieval.json`, 'utf8'),
);
const knowledge = loadTsModule(`${root}supabase/functions/_shared/knowledge.ts`);

// Mirror the shipped pipeline: documents are chunked before they are stored and
// lexical retrieval searches chunk content. Concatenating the chunks keeps the
// same vocabulary without inventing text that is not in the corpus.
const documents = corpus.documents.map((doc) => {
  const chunks = knowledge.chunkDocument(doc.content);
  assert.ok(chunks.length > 0, `corpus document ${doc.slug} has no chunks`);
  return {
    slug: doc.slug,
    title: doc.title,
    text: chunks.join(' ').toLowerCase(),
  };
});

function documentFrequency(term) {
  return documents.filter((doc) => doc.text.includes(term)).length;
}

function score(document, terms) {
  const total = documents.length;
  let rank = 0;
  for (const term of terms) {
    const occurrences = document.text.split(term).length - 1;
    if (occurrences === 0) continue;
    const df = documentFrequency(term);
    const idf = Math.log((total + 1) / (df + 0.5));
    rank += (1 + Math.log(occurrences)) * idf;
    if (document.title.toLowerCase().includes(term)) rank += idf * 2;
  }
  return rank;
}

let hitsAt3 = 0;
let reciprocalRank = 0;
const rows = [];

for (const item of evaluation.queries) {
  const terms = knowledge.queryTerms(item.query);
  assert.ok(terms.length > 0, `query ${item.id} produced no search terms`);
  const ranked = documents
    .map((document) => ({ slug: document.slug, score: score(document, terms) }))
    .filter((entry) => entry.score > 0)
    .sort((a, b) => b.score - a.score);
  const index = ranked.findIndex((entry) => entry.slug === item.expectedSlug);
  const rank = index >= 0 ? index + 1 : null;
  if (rank !== null && rank <= 3) hitsAt3 += 1;
  if (rank !== null) reciprocalRank += 1 / rank;
  rows.push({ id: item.id, query: item.query, expected: item.expectedSlug, rank, terms });
}

const count = evaluation.queries.length;
const recallAt3 = hitsAt3 / count;
const mrr = reciprocalRank / count;

console.log('Lexical retrieval evaluation over the shipped corpus');
console.log(`Queries: ${count}`);
for (const row of rows) {
  const status = row.rank === null ? 'MISS' : row.rank <= 3 ? `rank ${row.rank}` : `rank ${row.rank} (outside top 3)`;
  console.log(`  ${row.id} ${status.padEnd(22)} ${row.expected}`);
  if (row.rank === null || row.rank > 3) {
    console.log(`      terms: ${row.terms.join(', ')}`);
  }
}
console.log(`Recall@3: ${(recallAt3 * 100).toFixed(1)}% (${hitsAt3}/${count})`);
console.log(`MRR: ${mrr.toFixed(3)}`);

assert.ok(
  recallAt3 >= 0.8,
  `lexical fallback recall@3 fell below 80%: ${(recallAt3 * 100).toFixed(1)}%`,
);
assert.ok(mrr >= 0.7, `lexical fallback MRR fell below 0.70: ${mrr.toFixed(3)}`);

console.log('\nOffline retrieval evaluation passed. Live pgvector retrieval was not measured.');
