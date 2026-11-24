import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { Logger } from 'pino';
import type { Pool } from './pool.js';

const migrationsDir = path.join(path.dirname(fileURLToPath(import.meta.url)), 'migrations');

/**
 * Applies every pending `.sql` file once, in filename order, inside a single
 * transaction guarded by an advisory lock so two processes cannot race.
 */
const REQUIRED_TABLES = [
  'users',
  'sessions',
  'refresh_tokens',
  'community_profiles',
  'community_preferences',
  'gyms',
  'gym_memberships',
  'community_connections',
  'community_conversations',
  'community_messages',
  'community_posts',
  'community_comments',
  'community_likes',
  'community_notifications',
];

/**
 * Checks that the database matches this build before it starts serving
 * traffic. Returns human-readable problems; an empty array means compatible.
 */
export async function verifySchema(pool: Pool): Promise<string[]> {
  const problems: string[] = [];
  const files = (await readdir(migrationsDir)).filter((file) => file.endsWith('.sql')).sort();

  try {
    const applied = await pool.query<{ name: string }>('SELECT name FROM schema_migrations');
    const names = new Set(applied.rows.map((row) => row.name));
    for (const file of files) {
      if (!names.has(file)) problems.push(`migration ${file} has not been applied`);
    }
  } catch {
    problems.push('the schema_migrations table is missing');
  }

  const missing = await pool.query<{ name: string }>(
    `SELECT t AS name FROM unnest($1::text[]) AS t WHERE to_regclass('public.' || t) IS NULL`,
    [REQUIRED_TABLES],
  );
  for (const row of missing.rows) {
    problems.push(`table ${row.name} is missing`);
  }

  const requiredColumns: Array<[table: string, column: string]> = [
    ['sessions', 'access_expires_at'],
    ['gyms', 'provider_id'],
    ['gym_memberships', 'is_primary'],
    ['community_preferences', 'global_discovery'],
  ];
  const missingColumns = await pool.query<{ table_name: string; column_name: string }>(
    `SELECT t AS table_name, c AS column_name
       FROM unnest($1::text[], $2::text[]) AS pair(t, c)
      WHERE NOT EXISTS (
        SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = t AND column_name = c
      )`,
    [requiredColumns.map(([table]) => table), requiredColumns.map(([, column]) => column)],
  );
  for (const row of missingColumns.rows) {
    problems.push(`column ${row.table_name}.${row.column_name} is missing`);
  }
  return problems;
}

export async function runMigrations(pool: Pool, logger?: Logger): Promise<string[]> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query('SELECT pg_advisory_xact_lock(72430112)');
    await client.query(
      `CREATE TABLE IF NOT EXISTS schema_migrations (
         name text PRIMARY KEY,
         applied_at timestamptz NOT NULL DEFAULT now()
       )`,
    );
    const files = (await readdir(migrationsDir)).filter((file) => file.endsWith('.sql')).sort();
    const appliedResult = await client.query<{ name: string }>('SELECT name FROM schema_migrations');
    const applied = new Set(appliedResult.rows.map((row) => row.name));

    const ran: string[] = [];
    for (const file of files) {
      if (applied.has(file)) continue;
      const sql = await readFile(path.join(migrationsDir, file), 'utf8');
      await client.query(sql);
      await client.query('INSERT INTO schema_migrations (name) VALUES ($1)', [file]);
      ran.push(file);
      logger?.info({ migration: file }, 'applied migration');
    }
    await client.query('COMMIT');
    return ran;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}
