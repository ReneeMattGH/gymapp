// End-to-end integration test for CeeBase integration
const BASE_URL = 'http://127.0.0.1:8080';

async function query(sql, parameters = []) {
  const res = await fetch(`${BASE_URL}/api/v1/query`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ sql, parameters }),
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const json = await res.json();
  if (!json.success) throw new Error(json.error || 'Query failed');
  return json;
}

async function run() {
  console.log('--- 1. Testing CeeBase REST Server Connection ---');
  const tables = await query('SHOW TABLES;');
  console.log('Existing tables in CeeBase:', tables.rows);

  console.log('\n--- 2. Creating cb_ tables if not exist ---');
  const existing = new Set(tables.rows.map(r => String(r[0]).toLowerCase()));

  if (!existing.has('cb_users')) {
    await query(`CREATE TABLE cb_users (
      pk_id INTEGER PRIMARY KEY,
      id TEXT,
      email TEXT,
      password TEXT,
      name TEXT,
      created_at TEXT
    );`);
    console.log('Created cb_users');
  }

  if (!existing.has('cb_profiles')) {
    await query(`CREATE TABLE cb_profiles (
      pk_id INTEGER PRIMARY KEY,
      user_id TEXT,
      name TEXT,
      age INTEGER,
      experience TEXT,
      environment TEXT,
      goals TEXT,
      limitations TEXT,
      onboarding_completed BOOLEAN,
      created_at TEXT
    );`);
    console.log('Created cb_profiles');
  }

  if (!existing.has('cb_plans')) {
    await query(`CREATE TABLE cb_plans (
      pk_id INTEGER PRIMARY KEY,
      id TEXT,
      user_id TEXT,
      name TEXT,
      goal TEXT,
      experience TEXT,
      days_per_week INTEGER,
      session_minutes INTEGER,
      equipment TEXT,
      source TEXT,
      created_at TEXT,
      plan_json TEXT
    );`);
    console.log('Created cb_plans');
  }

  if (!existing.has('cb_sessions')) {
    await query(`CREATE TABLE cb_sessions (
      pk_id INTEGER PRIMARY KEY,
      id TEXT,
      user_id TEXT,
      plan_day_id TEXT,
      title TEXT,
      focus TEXT,
      started_at TEXT,
      ended_at TEXT,
      duration_seconds INTEGER,
      status TEXT,
      notes TEXT,
      session_json TEXT
    );`);
    console.log('Created cb_sessions');
  }

  console.log('\n--- 3. Testing User Registration & Query ---');
  const testUserId = `test_user_${Date.now()}`;
  const testEmail = `test_${Date.now()}@example.com`;
  const pkId = Math.floor(Date.now() % 1000000000);

  await query('INSERT INTO cb_users VALUES (?, ?, ?, ?, ?, ?);', [
    pkId,
    testUserId,
    testEmail,
    'password123',
    'Test Athlete',
    new Date().toISOString()
  ]);
  console.log('Inserted user:', testEmail);

  const userQuery = await query('SELECT id, email, name FROM cb_users WHERE email = ?;', [testEmail]);
  console.log('Retrieved user from CeeBase:', userQuery.rows);

  console.log('\n--- 4. Testing Profile Save & Retrieve ---');
  const profilePk = pkId + 1;
  await query('INSERT INTO cb_profiles VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);', [
    profilePk,
    testUserId,
    'Test Athlete',
    24,
    'intermediate',
    'gym',
    '["strength","mobility"]',
    'none',
    true,
    new Date().toISOString()
  ]);
  const profileQuery = await query('SELECT * FROM cb_profiles WHERE user_id = ?;', [testUserId]);
  console.log('Retrieved profile:', profileQuery.rows);

  console.log('\n--- 5. Testing Workout Plan Save & Retrieve ---');
  const planPk = pkId + 2;
  const mockPlan = {
    id: `plan_${Date.now()}`,
    userId: testUserId,
    name: '4-Day Hypertrophy',
    goal: 'strength',
    experience: 'intermediate',
    daysPerWeek: 4,
    sessionMinutes: 45,
    equipment: ['barbell', 'dumbbells'],
    source: 'on-device',
    createdAt: new Date().toISOString(),
    days: [
      { id: 'd1', planId: `plan_${Date.now()}`, dayIndex: 0, title: 'Upper Body A', exercises: [] }
    ]
  };

  await query('INSERT INTO cb_plans VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);', [
    planPk,
    mockPlan.id,
    testUserId,
    mockPlan.name,
    mockPlan.goal,
    mockPlan.experience,
    mockPlan.daysPerWeek,
    mockPlan.sessionMinutes,
    JSON.stringify(mockPlan.equipment),
    mockPlan.source,
    mockPlan.createdAt,
    JSON.stringify(mockPlan)
  ]);
  const planQuery = await query('SELECT plan_json FROM cb_plans WHERE user_id = ?;', [testUserId]);
  const retrievedPlan = JSON.parse(planQuery.rows[0][0]);
  console.log('Retrieved plan name:', retrievedPlan.name, 'with', retrievedPlan.days.length, 'days');

  console.log('\n--- 6. Cleanup Test Data ---');
  await query('DELETE FROM cb_users WHERE id = ?;', [testUserId]);
  await query('DELETE FROM cb_profiles WHERE user_id = ?;', [testUserId]);
  await query('DELETE FROM cb_plans WHERE user_id = ?;', [testUserId]);
  console.log('Cleaned up test rows.');

  console.log('\n>>> ALL CEEBASE INTEGRATION TESTS PASSED! <<<');
}

run().catch(err => {
  console.error('Test failed:', err);
  process.exit(1);
});
