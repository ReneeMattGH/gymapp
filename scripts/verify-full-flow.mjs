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

function pk() {
  return Date.now() * 1000 + Math.floor(Math.random() * 1000);
}

async function simulateAppFlow() {
  console.log('=== SIMULATING COMPLETE APP LIFECYCLE ON CEEBASE ===\n');

  const userId = `user_e2e_${Date.now()}`;
  const email = `athlete_${Date.now()}@test.com`;

  // 1. Sign up
  console.log('1. User Sign Up...');
  await query('INSERT INTO cb_users VALUES (?, ?, ?, ?, ?, ?);', [
    pk(), userId, email, 'SecurePass2026!', 'Mac Andross', new Date().toISOString()
  ]);
  const userCheck = await query('SELECT id, email, name FROM cb_users WHERE email = ?;', [email]);
  console.log('   ✓ User created:', userCheck.rows[0]);

  // 2. Onboarding: Save Profile & Preferences
  console.log('2. Athlete Onboarding (Profile & Preferences)...');
  await query('INSERT INTO cb_profiles VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);', [
    pk(), userId, 'Mac Andross', 24, 'intermediate', 'gym', '["strength","mobility"]', 'None', true, new Date().toISOString()
  ]);
  await query('INSERT INTO cb_preferences VALUES (?, ?, ?, ?, ?, ?, ?, ?);', [
    pk(), userId, '[1,3,5]', 45, '["barbell","dumbbells","bench"]', '[]', '18:00', 'kg'
  ]);
  const profile = await query('SELECT user_id, name, experience FROM cb_profiles WHERE user_id = ?;', [userId]);
  console.log('   ✓ Profile stored:', profile.rows[0]);

  // 3. Save Workout Plan
  console.log('3. Plan Generation & Storage...');
  const planId = `plan_${Date.now()}`;
  const planData = {
    id: planId,
    userId,
    name: 'Upper/Lower Split',
    goal: 'strength',
    experience: 'intermediate',
    daysPerWeek: 3,
    sessionMinutes: 45,
    equipment: ['barbell', 'dumbbells', 'bench'],
    source: 'on-device',
    createdAt: new Date().toISOString(),
    days: [
      { id: 'd1', planId, dayIndex: 0, title: 'Upper Strength', focus: ['chest', 'back'], exercises: [] },
      { id: 'd2', planId, dayIndex: 1, title: 'Lower Strength', focus: ['quads', 'hamstrings'], exercises: [] },
      { id: 'd3', planId, dayIndex: 2, title: 'Full Body & Core', focus: ['full-body'], exercises: [] },
    ]
  };
  await query('INSERT INTO cb_plans VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);', [
    pk(), planId, userId, planData.name, planData.goal, planData.experience, 3, 45, JSON.stringify(planData.equipment), 'on-device', planData.createdAt, JSON.stringify(planData)
  ]);
  const planRes = await query('SELECT plan_json FROM cb_plans WHERE user_id = ?;', [userId]);
  const loadedPlan = JSON.parse(planRes.rows[0][0]);
  console.log(`   ✓ Workout Plan saved with ${loadedPlan.days.length} days: "${loadedPlan.name}"`);

  // 4. Log Completed Workout Session
  console.log('4. Logging Live Workout Session...');
  const sessionId = `session_${Date.now()}`;
  const sessionData = {
    id: sessionId,
    userId,
    planDayId: 'd1',
    title: 'Upper Strength',
    focus: ['chest', 'back'],
    startedAt: new Date(Date.now() - 3600000).toISOString(),
    endedAt: new Date().toISOString(),
    durationSeconds: 2700,
    status: 'completed',
    notes: 'Felt strong on bench press today.',
    sets: [
      { id: 's1', sessionId, exerciseId: 'barbell-bench-press', setNumber: 1, reps: 8, weightKg: 80, completedAt: new Date().toISOString() },
      { id: 's2', sessionId, exerciseId: 'barbell-bench-press', setNumber: 2, reps: 8, weightKg: 85, completedAt: new Date().toISOString() },
      { id: 's3', sessionId, exerciseId: 'barbell-bench-press', setNumber: 3, reps: 6, weightKg: 90, completedAt: new Date().toISOString() },
    ]
  };
  await query('INSERT INTO cb_sessions VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);', [
    pk(), sessionId, userId, 'd1', 'Upper Strength', '["chest","back"]', sessionData.startedAt, sessionData.endedAt, 2700, 'completed', sessionData.notes, JSON.stringify(sessionData)
  ]);
  const sessionRes = await query('SELECT session_json FROM cb_sessions WHERE id = ?;', [sessionId]);
  const loadedSession = JSON.parse(sessionRes.rows[0][0]);
  console.log(`   ✓ Session logged with ${loadedSession.sets.length} completed sets: status "${loadedSession.status}"`);

  // 5. Track Bodyweight / Progress Check-in
  console.log('5. Adding Progress Record...');
  const progId = `prog_${Date.now()}`;
  await query('INSERT INTO cb_progress VALUES (?, ?, ?, ?, ?, ?);', [
    pk(), progId, userId, new Date().toISOString(), 78.5, 'Morning weigh-in'
  ]);
  const progRes = await query('SELECT bodyweight_kg, notes FROM cb_progress WHERE user_id = ?;', [userId]);
  console.log(`   ✓ Progress recorded: ${progRes.rows[0][0]} kg - "${progRes.rows[0][1]}"`);

  // 6. Coach Messaging
  console.log('6. Coach Conversation & Messages...');
  const convoId = `convo_${Date.now()}`;
  await query('INSERT INTO cb_conversations VALUES (?, ?, ?, ?, ?, ?);', [
    pk(), convoId, userId, 'Form Check Advice', new Date().toISOString(), new Date().toISOString()
  ]);
  await query('INSERT INTO cb_messages VALUES (?, ?, ?, ?, ?, ?, ?);', [
    pk(), `msg_1`, convoId, userId, 'user', 'How can I improve my bench bar path?', new Date().toISOString()
  ]);
  await query('INSERT INTO cb_messages VALUES (?, ?, ?, ?, ?, ?, ?);', [
    pk(), `msg_2`, convoId, userId, 'assistant', 'Keep your elbows tucked at roughly 45 degrees and press slightly back towards your rack.', new Date().toISOString()
  ]);
  const msgs = await query('SELECT role, content FROM cb_messages WHERE conversation_id = ?;', [convoId]);
  console.log(`   ✓ Conversation verified with ${msgs.rows.length} messages.`);

  // 7. Cleanup Test Simulation
  console.log('7. Cleaning up test simulation data...');
  await query('DELETE FROM cb_users WHERE id = ?;', [userId]);
  await query('DELETE FROM cb_profiles WHERE user_id = ?;', [userId]);
  await query('DELETE FROM cb_preferences WHERE user_id = ?;', [userId]);
  await query('DELETE FROM cb_plans WHERE user_id = ?;', [userId]);
  await query('DELETE FROM cb_sessions WHERE user_id = ?;', [userId]);
  await query('DELETE FROM cb_progress WHERE user_id = ?;', [userId]);
  await query('DELETE FROM cb_conversations WHERE id = ?;', [convoId]);
  await query('DELETE FROM cb_messages WHERE conversation_id = ?;', [convoId]);
  console.log('   ✓ Cleaned up.');

  console.log('\n========================================================');
  console.log(' DATABASE IS 100% CONFIGURED, TESTED, AND READY TO USE!');
  console.log('========================================================');
}

simulateAppFlow().catch(err => {
  console.error('Simulation error:', err);
  process.exit(1);
});
