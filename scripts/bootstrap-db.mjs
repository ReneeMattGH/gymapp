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

async function checkAndBootstrap() {
  const tablesRes = await query('SHOW TABLES;');
  const existing = new Set(tablesRes.rows.map(r => String(r[0]).toLowerCase()));
  console.log('Current tables in CeeBase:', Array.from(existing));

  const schemas = [
    {
      name: 'cb_users',
      sql: `CREATE TABLE cb_users (
        pk_id INTEGER PRIMARY KEY,
        id TEXT,
        email TEXT,
        password TEXT,
        name TEXT,
        created_at TEXT
      );`
    },
    {
      name: 'cb_profiles',
      sql: `CREATE TABLE cb_profiles (
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
      );`
    },
    {
      name: 'cb_preferences',
      sql: `CREATE TABLE cb_preferences (
        pk_id INTEGER PRIMARY KEY,
        user_id TEXT,
        workout_days TEXT,
        session_minutes INTEGER,
        equipment TEXT,
        avoid_exercises TEXT,
        reminder_time TEXT,
        units TEXT
      );`
    },
    {
      name: 'cb_plans',
      sql: `CREATE TABLE cb_plans (
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
      );`
    },
    {
      name: 'cb_sessions',
      sql: `CREATE TABLE cb_sessions (
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
      );`
    },
    {
      name: 'cb_reminders',
      sql: `CREATE TABLE cb_reminders (
        pk_id INTEGER PRIMARY KEY,
        user_id TEXT,
        enabled BOOLEAN,
        workout_time TEXT,
        days TEXT,
        rest_day_reminders BOOLEAN,
        hydration_reminders BOOLEAN,
        weekly_progress_reminder BOOLEAN,
        scheduled_ids TEXT
      );`
    },
    {
      name: 'cb_conversations',
      sql: `CREATE TABLE cb_conversations (
        pk_id INTEGER PRIMARY KEY,
        id TEXT,
        user_id TEXT,
        title TEXT,
        created_at TEXT,
        updated_at TEXT
      );`
    },
    {
      name: 'cb_messages',
      sql: `CREATE TABLE cb_messages (
        pk_id INTEGER PRIMARY KEY,
        id TEXT,
        conversation_id TEXT,
        user_id TEXT,
        role TEXT,
        content TEXT,
        created_at TEXT
      );`
    },
    {
      name: 'cb_progress',
      sql: `CREATE TABLE cb_progress (
        pk_id INTEGER PRIMARY KEY,
        id TEXT,
        user_id TEXT,
        recorded_at TEXT,
        bodyweight_kg DOUBLE,
        notes TEXT
      );`
    }
  ];

  for (const table of schemas) {
    if (!existing.has(table.name)) {
      console.log(`Creating table ${table.name}...`);
      await query(table.sql);
      console.log(`  -> ${table.name} created!`);
    } else {
      console.log(`Table ${table.name} already exists.`);
    }
  }

  const finalTables = await query('SHOW TABLES;');
  console.log('\nFinal CeeBase Database Tables:');
  for (const t of finalTables.rows) {
    const countRes = await query(`SELECT COUNT(*) FROM ${t[0]};`);
    console.log(`  - ${t[0]} (rows: ${countRes.rows[0][0]})`);
  }
}

checkAndBootstrap().catch(err => {
  console.error('Bootstrap failed:', err);
  process.exit(1);
});
