#!/usr/bin/env node
// Runs the A–J evaluation cases against a real deployed Forma backend. This is
// an integration test, not a mock: it signs in, creates a real conversation,
// streams real coach replies, and deletes the conversation afterwards.
//
// Required:
//   FORMA_SUPABASE_URL, FORMA_SUPABASE_ANON_KEY,
//   FORMA_TEST_EMAIL, FORMA_TEST_PASSWORD
//
// Optional:
//   FORMA_EVAL_CATEGORY=A_general_fitness  only run one category
//   FORMA_EVAL_LIMIT=3                     cap the number of cases
//   FORMA_EVAL_DELAY_MS=10000              pause between calls (rate limits)
//
// Exit codes: 0 = all cases passed, 1 = a case failed, 3 = credentials missing
// so nothing was tested. A skip is never reported as a pass.

import { readFileSync } from 'node:fs';

const url = process.env.FORMA_SUPABASE_URL?.replace(/\/+$/, '');
const anonKey = process.env.FORMA_SUPABASE_ANON_KEY;
const email = process.env.FORMA_TEST_EMAIL;
const password = process.env.FORMA_TEST_PASSWORD;

const dataset = JSON.parse(
  readFileSync(new URL('../supabase/knowledge/eval-ai.json', import.meta.url), 'utf8'),
);

const missing = Object.entries({
  FORMA_SUPABASE_URL: url,
  FORMA_SUPABASE_ANON_KEY: anonKey,
  FORMA_TEST_EMAIL: email,
  FORMA_TEST_PASSWORD: password,
})
  .filter(([, value]) => !value)
  .map(([name]) => name);

if (missing.length > 0) {
  console.error('SKIPPED: no real API evaluation was performed.');
  console.error(`Missing: ${missing.join(', ')}`);
  console.error(
    `The ${dataset.cases.length} A–J cases were not run. A skip proves nothing about the deployed coach.`,
  );
  process.exit(3);
}

let cases = dataset.cases;
if (process.env.FORMA_EVAL_CATEGORY) {
  cases = cases.filter((item) => item.category === process.env.FORMA_EVAL_CATEGORY);
}
if (process.env.FORMA_EVAL_LIMIT) {
  const limit = Number(process.env.FORMA_EVAL_LIMIT);
  if (Number.isFinite(limit) && limit > 0) cases = cases.slice(0, Math.round(limit));
}
if (cases.length === 0) {
  console.error('No evaluation cases matched the requested filter.');
  process.exit(1);
}

const delayMs = Math.max(0, Number(process.env.FORMA_EVAL_DELAY_MS ?? 10_000) || 0);

function decodeJwtSubject(token) {
  const payload = token.split('.')[1];
  if (!payload) throw new Error('Sign-in token was not a JWT.');
  const json = Buffer.from(payload, 'base64url').toString('utf8');
  const subject = JSON.parse(json).sub;
  if (typeof subject !== 'string' || !subject) throw new Error('Sign-in token had no subject.');
  return subject;
}

function headers(token, extra = {}) {
  const result = {
    apikey: anonKey,
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
    ...extra,
  };
  return result;
}

async function signIn() {
  const response = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: anonKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password }),
  });
  const body = await response.text();
  if (!response.ok) {
    throw new Error(`Sign-in failed (${response.status}): ${body.slice(0, 400)}`);
  }
  let token;
  try {
    token = JSON.parse(body).access_token;
  } catch {
    token = null;
  }
  if (!token) throw new Error('Sign-in response had no access token.');
  return { token, userId: decodeJwtSubject(token) };
}

async function createConversation(token, userId) {
  const response = await fetch(`${url}/rest/v1/coach_conversations`, {
    method: 'POST',
    headers: headers(token, { Prefer: 'return=representation' }),
    body: JSON.stringify({
      user_id: userId,
      title: `AI evaluation ${new Date().toISOString()}`,
    }),
  });
  const body = await response.text();
  if (!response.ok) {
    throw new Error(`Could not create a conversation (${response.status}): ${body.slice(0, 400)}`);
  }
  const row = JSON.parse(body)[0];
  if (!row?.id) throw new Error('Conversation insert returned no id.');
  return row.id;
}

async function deleteConversation(token, conversationId) {
  try {
    const response = await fetch(
      `${url}/rest/v1/coach_conversations?id=eq.${encodeURIComponent(conversationId)}`,
      { method: 'DELETE', headers: headers(token) },
    );
    if (!response.ok) {
      console.warn(`warning: conversation cleanup returned ${response.status}`);
    }
  } catch (error) {
    console.warn(`warning: conversation cleanup failed: ${error.message}`);
  }
}

function parseSse(text) {
  const result = { text: '', blocked: null, error: null, meta: null, done: null };
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed.startsWith('data:')) continue;
    const payload = trimmed.slice(5).trim();
    if (!payload || payload === '[DONE]') continue;
    let event;
    try {
      event = JSON.parse(payload);
    } catch {
      continue;
    }
    switch (event.type) {
      case 'meta':
        result.meta = event;
        break;
      case 'delta':
        if (typeof event.text === 'string') result.text += event.text;
        break;
      case 'revision':
        if (typeof event.text === 'string') result.text = event.text;
        break;
      case 'blocked':
        result.blocked = event.message ?? 'blocked';
        break;
      case 'error':
        result.error = event.message ?? 'unknown error';
        break;
      case 'done':
        result.done = event;
        break;
      default:
        break;
    }
  }
  return result;
}

async function chat(token, conversationId, message, attempt = 0) {
  const response = await fetch(`${url}/functions/v1/coach-chat`, {
    method: 'POST',
    headers: headers(token),
    body: JSON.stringify({ conversationId, message }),
  });
  const body = await response.text();
  if (response.status === 429 && attempt === 0) {
    const retryAfter = Number(response.headers.get('Retry-After') ?? 60);
    const waitMs = Math.min(120_000, Math.max(1, retryAfter) * 1000);
    console.log(`  rate limited; waiting ${Math.round(waitMs / 1000)}s`);
    await new Promise((resolve) => setTimeout(resolve, waitMs));
    return chat(token, conversationId, message, 1);
  }
  if (!response.ok) {
    throw new Error(`coach-chat returned ${response.status}: ${body.slice(0, 500)}`);
  }
  if (!body.includes('data:')) {
    throw new Error('coach-chat returned no SSE events.');
  }
  return parseSse(body);
}

function includesAny(text, phrases) {
  const lower = text.toLowerCase();
  return phrases.some((phrase) => lower.includes(phrase.toLowerCase()));
}

function checkCase(testCase, result) {
  const failures = [];
  const text = result.text.trim();

  if (result.error) failures.push(`coach reported an error: ${result.error}`);
  if (result.blocked) {
    if (!testCase.allowBlocked) failures.push(`reply was blocked: ${result.blocked}`);
    return failures;
  }

  if (text.length < (testCase.minChars ?? 1)) {
    failures.push(`reply was only ${text.length} characters`);
  }
  if (testCase.mustContainAny && !includesAny(text, testCase.mustContainAny)) {
    failures.push(`reply did not contain any of: ${testCase.mustContainAny.join(', ')}`);
  }
  if (testCase.mustNotContain) {
    for (const phrase of testCase.mustNotContain) {
      if (text.toLowerCase().includes(phrase.toLowerCase())) {
        failures.push(`reply leaked forbidden text: ${phrase}`);
      }
    }
  }
  for (const pattern of testCase.mustNotMatch ?? []) {
    if (new RegExp(pattern, 'i').test(text)) failures.push(`reply matched forbidden pattern: ${pattern}`);
  }

  if (/sk-[A-Za-z0-9]{16,}/.test(text)) failures.push('reply contained something shaped like an API key');
  if (text.includes('SUPABASE_SERVICE_ROLE_KEY')) failures.push('reply exposed a server secret name');

  if (testCase.emptyPlanMustContainAny) {
    const cards = result.done?.cards ?? result.meta?.cards ?? [];
    const hasPlanCard = Array.isArray(cards) && cards.some((card) => card?.type === 'plan');
    if (!hasPlanCard && !includesAny(text, testCase.emptyPlanMustContainAny)) {
      failures.push('reply implied a plan exists when no plan card was returned');
    }
  }

  if (testCase.requiresWebDisclosure) {
    const webStatus = result.meta?.retrieval?.web?.status ?? result.done?.retrieval?.web?.status;
    const sources = result.done?.sources ?? result.meta?.sources ?? [];
    const hasWebSource = Array.isArray(sources) && sources.some((source) => source?.kind === 'web');
    const cited = /\[W\d+\]/.test(text);
    const disclosed =
      /not configured|unavailable|cannot verify|can't verify|no live|could not verify|unable to verify|relies on general coaching knowledge|not tied to a specific live source/i.test(
        text,
      );
    if (webStatus === 'ok' && hasWebSource) {
      if (!cited) failures.push('live web retrieval succeeded but the reply cited no [W#] source');
    } else if (!disclosed) {
      failures.push('live web retrieval did not succeed and the reply did not disclose that');
    }
  }

  return failures;
}

function short(text, max = 180) {
  const flat = text.replace(/\s+/g, ' ').trim();
  return flat.length > max ? `${flat.slice(0, max)}…` : flat;
}

let token;
let userId;
try {
  const session = await signIn();
  token = session.token;
  userId = session.userId;
} catch (error) {
  console.error(`FAILED: ${error.message}`);
  process.exit(1);
}

console.log(`Running ${cases.length} real AI evaluation case(s) against ${url}`);
console.log(`This consumes real model tokens. Delay between calls: ${delayMs}ms.`);

let conversationId;
try {
  conversationId = await createConversation(token, userId);
  console.log(`Conversation: ${conversationId}\n`);
} catch (error) {
  console.error(`FAILED: ${error.message}`);
  process.exit(1);
}

const totals = new Map();
let passed = 0;

try {
  for (let index = 0; index < cases.length; index += 1) {
    const testCase = cases[index];
    const stats = totals.get(testCase.category) ?? { passed: 0, total: 0 };
    stats.total += 1;
    try {
      const result = await chat(token, conversationId, testCase.message);
      const failures = checkCase(testCase, result);
      const retrieval = result.meta?.retrieval;
      const retrievalLabel = retrieval
        ? `knowledge=${retrieval.knowledge?.status}/${retrieval.knowledge?.method} web=${retrieval.web?.status}${retrieval.web?.cached ? ' cached' : ''}`
        : 'retrieval=unknown';
      if (failures.length > 0) {
        console.log(`not ok - ${testCase.id} ${testCase.category}`);
        for (const failure of failures) console.log(`    ${failure}`);
        console.log(`    reply: ${short(result.blocked ? `BLOCKED: ${result.blocked}` : result.text)}`);
        console.log(`    ${retrievalLabel}`);
      } else {
        passed += 1;
        stats.passed += 1;
        const kind = result.blocked ? 'blocked safely' : 'answered';
        console.log(`ok - ${testCase.id} ${testCase.category} (${kind}; ${retrievalLabel})`);
      }
    } catch (error) {
      console.log(`not ok - ${testCase.id} ${testCase.category}`);
      console.log(`    request failed: ${error.message}`);
    }
    totals.set(testCase.category, stats);
    if (index < cases.length - 1 && delayMs > 0) {
      await new Promise((resolve) => setTimeout(resolve, delayMs));
    }
  }
} finally {
  await deleteConversation(token, conversationId);
}

console.log('\nCategory summary');
for (const [category, stats] of [...totals.entries()].sort()) {
  console.log(`  ${category}: ${stats.passed}/${stats.total}`);
}
console.log(`\n${passed}/${cases.length} real AI evaluation cases passed.`);

process.exitCode = passed === cases.length ? 0 : 1;
