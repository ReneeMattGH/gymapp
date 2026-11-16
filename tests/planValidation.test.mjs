// Runs the real Supabase plan validator under Node by transpiling the TypeScript
// with the repository's own `typescript` package. No mocks: the same source that
// ships to the Edge Function is executed.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';

const require = createRequire(import.meta.url);
const ts = require('typescript');

const source = readFileSync(new URL('../supabase/functions/_shared/planValidation.ts', import.meta.url), 'utf8');
const compiled = ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;

const module = { exports: {} };
vm.runInNewContext(compiled, { module, exports: module.exports, console, Set, Map, Math, Number, Array, Object });
const { validateAndNormalizePlan } = module.exports;

const allowedIds = new Set(['squat', 'push-up', 'row', 'plank']);
const constraints = {
  allowedIds,
  preferredWeekdays: [1, 3, 5],
  sessionMinutes: 45,
  experience: 'beginner',
};

function exercise(id, overrides = {}) {
  return { exerciseId: id, sets: 3, repsMin: 8, repsMax: 12, restSeconds: 60, notes: null, ...overrides };
}

function trainingDay(weekday, extras = {}) {
  return {
    weekday,
    title: 'Full body',
    focus: ['full-body'],
    estimatedMinutes: 45,
    isRestDay: false,
    restNote: null,
    warmup: ['Five minutes easy cardio'],
    cooldown: ['Walk until calm'],
    exercises: [exercise('squat'), exercise('push-up')],
    ...extras,
  };
}

function restDay(weekday) {
  return {
    weekday,
    title: 'Rest',
    focus: [],
    estimatedMinutes: 0,
    isRestDay: true,
    restNote: 'Easy day',
    warmup: [],
    cooldown: [],
    exercises: [],
  };
}

function fullPlan(overrides = {}) {
  return {
    name: 'Test plan',
    days: [1, 2, 3, 4, 5, 6, 7].map((weekday) =>
      [1, 3, 5].includes(weekday) ? trainingDay(weekday, overrides[weekday]) : restDay(weekday),
    ),
  };
}

let passed = 0;
function test(name, fn) {
  try {
    fn();
    passed += 1;
    console.log(`ok - ${name}`);
  } catch (error) {
    console.error(`not ok - ${name}`);
    throw error;
  }
}

test('valid plan is accepted with all seven days and exact schedule', () => {
  const { plan, issues } = validateAndNormalizePlan(fullPlan(), constraints);
  assert.ok(plan, `expected a plan, got issues: ${JSON.stringify(issues)}`);
  assert.equal(plan.days.length, 7);
  assert.equal(
    JSON.stringify(plan.days.filter((day) => !day.isRestDay).map((day) => day.weekday)),
    JSON.stringify([1, 3, 5]),
  );
});

test('unknown exercise id is rejected', () => {
  const raw = fullPlan({ 1: { exercises: [exercise('squat'), exercise('invented-movement')] } });
  const { plan, issues } = validateAndNormalizePlan(raw, constraints);
  assert.equal(plan, null);
  assert.ok(issues.some((issue) => issue.code === 'exercise_not_allowed'));
});

test('duplicate exercise on one day is rejected', () => {
  const raw = fullPlan({ 1: { exercises: [exercise('squat'), exercise('squat')] } });
  const { plan, issues } = validateAndNormalizePlan(raw, constraints);
  assert.equal(plan, null);
  assert.ok(issues.some((issue) => issue.code === 'duplicate_exercise'));
});

test('a missing training day is rejected', () => {
  const raw = fullPlan();
  raw.days[2] = restDay(3);
  const { plan, issues } = validateAndNormalizePlan(raw, constraints);
  assert.equal(plan, null);
  assert.ok(issues.some((issue) => issue.code === 'missing_training_day'));
});

test('an unexpected training day is rejected', () => {
  const raw = fullPlan();
  raw.days[1] = trainingDay(2);
  const { plan, issues } = validateAndNormalizePlan(raw, constraints);
  assert.equal(plan, null);
  assert.ok(issues.some((issue) => issue.code === 'unexpected_training_day'));
});

test('duration far from the selected window is rejected', () => {
  const raw = fullPlan({ 1: { estimatedMinutes: 90 } });
  const { plan, issues } = validateAndNormalizePlan(raw, constraints);
  assert.equal(plan, null);
  assert.ok(issues.some((issue) => issue.code === 'duration_mismatch'));
});

test('too few exercises on a day is rejected', () => {
  const raw = fullPlan({ 1: { exercises: [exercise('squat')] } });
  const { plan, issues } = validateAndNormalizePlan(raw, constraints);
  assert.equal(plan, null);
  assert.ok(issues.some((issue) => issue.code === 'insufficient_exercises'));
});

test('beginner volume is clamped and reported as a warning', () => {
  const raw = fullPlan({ 1: { exercises: [exercise('squat', { sets: 6 }), exercise('push-up')] } });
  const { plan, issues } = validateAndNormalizePlan(raw, constraints);
  assert.ok(plan);
  assert.equal(plan.days[0].exercises[0].sets, 3);
  assert.ok(issues.some((issue) => issue.code === 'sets_clamped'));
});

test('unusable JSON is rejected without throwing', () => {
  const { plan, issues } = validateAndNormalizePlan('not a plan', constraints);
  assert.equal(plan, null);
  assert.ok(issues.some((issue) => issue.code === 'invalid_json'));
});

console.log(`\n${passed} plan validator checks passed against the shipped TypeScript.`);
