import { loadConfig } from '../config.js';
import { createLogger } from '../logger.js';
import { createPool } from './pool.js';
import { runMigrations } from './migrate.js';

const config = loadConfig();
const logger = createLogger(config.logLevel);
const pool = createPool(config.databaseUrl);

try {
  const applied = await runMigrations(pool, logger);
  logger.info({ applied }, applied.length ? 'migrations applied' : 'no pending migrations');
} finally {
  await pool.end();
}
