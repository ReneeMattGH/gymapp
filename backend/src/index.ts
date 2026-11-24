import { createServer } from 'node:http';
import { Server } from 'socket.io';
import { loadConfig } from './config.js';
import { createLogger } from './logger.js';
import { createPool } from './db/pool.js';
import { runMigrations, verifySchema } from './db/migrate.js';
import { createMailer } from './auth/mailer.js';
import { createAuthService } from './auth/service.js';
import { createCommunityService, noRealtime } from './community/service.js';
import { attachCommunityRealtime } from './community/realtime.js';
import { createApp } from './http/app.js';

const config = loadConfig();
const logger = createLogger(config.logLevel);
const pool = createPool(config.databaseUrl);

if (config.autoMigrate) {
  const applied = await runMigrations(pool, logger);
  logger.info({ applied }, 'database schema up to date');
}

// Refuse to serve traffic against a database this build does not understand,
// instead of failing later with confusing SQL errors.
const schemaProblems = await verifySchema(pool);
if (schemaProblems.length > 0) {
  logger.error({ problems: schemaProblems }, 'database schema is incompatible; run `npm run migrate`');
  await pool.end();
  process.exit(1);
}

const mailer = createMailer({ smtpUrl: config.smtpUrl, from: config.mailFrom });
if (!mailer.configured) {
  logger.warn('SMTP_URL is not set; verification and password reset will answer 503');
}

const auth = createAuthService({ pool, config, mailer, logger });

// The socket server attaches to the HTTP server below, after the express app
// exists. The proxy keeps the community service decoupled from that ordering.
let realtime = noRealtime;
const community = createCommunityService({
  pool,
  config,
  logger,
  realtime: { emitToUser: (userId, event, payload) => realtime.emitToUser(userId, event, payload) },
});

const app = createApp({ config, pool, logger, auth, community });
const server = createServer(app);

const io = new Server(server, {
  serveClient: false,
  cors: config.corsOrigins.length > 0 ? { origin: config.corsOrigins } : undefined,
});
realtime = attachCommunityRealtime({ io, pool, logger });

server.listen(config.port, config.host, () => {
  logger.info({ host: config.host, port: config.port }, 'forma backend listening');
});

async function shutdown(signal: string): Promise<void> {
  logger.info({ signal }, 'shutting down');
  io.close();
  server.close();
  await pool.end();
  process.exit(0);
}

process.on('SIGINT', () => void shutdown('SIGINT'));
process.on('SIGTERM', () => void shutdown('SIGTERM'));
