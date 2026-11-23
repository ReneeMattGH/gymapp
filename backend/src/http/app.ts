import { randomUUID } from 'node:crypto';
import path from 'node:path';
import cors from 'cors';
import express, { type Express } from 'express';
import helmet from 'helmet';
import { pinoHttp } from 'pino-http';
import type { Logger } from 'pino';
import type { Config } from '../config.js';
import type { Pool } from '../db/pool.js';
import { createAuthRouter } from '../auth/routes.js';
import { createRequireAuth } from '../auth/middleware.js';
import type { AuthService } from '../auth/service.js';
import { createCommunityRouter } from '../community/routes.js';
import type { CommunityService } from '../community/service.js';
import { createErrorHandler, notFoundHandler } from '../errors.js';
import { createGeneralLimiter, createSensitiveLimiter } from './rateLimit.js';

export interface AppDependencies {
  config: Config;
  pool: Pool;
  logger: Logger;
  auth: AuthService;
  community: CommunityService;
}

export function createApp({ config, pool, logger, auth, community }: AppDependencies): Express {
  const app = express();
  app.disable('x-powered-by');
  app.set('trust proxy', config.trustProxy);

  app.use(helmet());
  if (config.corsOrigins.length > 0) {
    app.use(
      cors({
        origin: config.corsOrigins,
        methods: ['GET', 'POST', 'PATCH', 'DELETE'],
        allowedHeaders: ['content-type', 'authorization'],
        maxAge: 600,
      }),
    );
  }

  app.use(
    pinoHttp({
      logger,
      genReqId: (req, res) => {
        const id = randomUUID();
        res.setHeader('x-request-id', id);
        return id;
      },
      serializers: {
        req: (req) => ({ id: req.id, method: req.method, path: req.url?.split('?')[0] }),
      },
      customLogLevel: (_req, res, error) => {
        if (error || res.statusCode >= 500) return 'error';
        if (res.statusCode >= 400) return 'warn';
        return 'info';
      },
      autoLogging: { ignore: (req) => req.url === '/health' },
    }),
  );

  app.use(express.json({ limit: '64kb' }));
  app.use('/uploads', express.static(path.resolve(config.uploadDir), { index: false, maxAge: '1h' }));

  app.get('/health', async (_req, res) => {
    try {
      await pool.query('SELECT 1');
      res.json({ status: 'ok', database: 'up', time: new Date().toISOString() });
    } catch (error) {
      logger.error({ err: error }, 'health check: database unavailable');
      res.status(503).json({ status: 'degraded', database: 'down', time: new Date().toISOString() });
    }
  });

  const limitsEnabled = config.nodeEnv !== 'test';
  const generalLimiter = createGeneralLimiter(limitsEnabled);
  const sensitiveLimiter = createSensitiveLimiter(limitsEnabled);

  app.use('/api/v1', generalLimiter);
  const requireAuth = createRequireAuth(pool);
  app.use(
    '/api/v1/auth',
    createAuthRouter({
      service: auth,
      requireAuth,
      sensitiveLimiter,
    }),
  );
  app.use(
    '/api/v1/community',
    createCommunityRouter({
      service: community,
      requireAuth,
    }),
  );

  app.use(notFoundHandler);
  app.use(createErrorHandler(logger));

  return app;
}
