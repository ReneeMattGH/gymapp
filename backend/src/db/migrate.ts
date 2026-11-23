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
