import type { RequestHandler } from 'express';
import type { Pool } from '../db/pool.js';
import { unauthorized } from '../errors.js';
import { hashToken } from './tokens.js';

export interface AuthContext {
  userId: string;
  sessionId: string;
  email: string;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      auth?: AuthContext;
    }
  }
}

const LAST_SEEN_REFRESH_MS = 5 * 60 * 1000;

/** Rejects requests without a live session; attaches `req.auth` when valid. */
export function createRequireAuth(pool: Pool): RequestHandler {
  return (req, _res, next) => {
    void (async () => {
      const header = req.header('authorization') ?? '';
      const [scheme, token] = header.split(' ');
      if (scheme?.toLowerCase() !== 'bearer' || !token) throw unauthorized();

      const result = await pool.query<{
        session_id: string;
        user_id: string;
        email: string;
        last_seen_at: Date | null;
      }>(
        `SELECT s.id AS session_id, s.last_seen_at, u.id AS user_id, u.email
         FROM sessions s
         JOIN users u ON u.id = s.user_id
         WHERE s.access_token_hash = $1
           AND s.revoked_at IS NULL
           AND s.expires_at > now()`,
        [hashToken(token)],
      );
      const session = result.rows[0];
      if (!session) throw unauthorized('Your session expired. Sign in again.');

      req.auth = {
        userId: session.user_id,
        sessionId: session.session_id,
        email: session.email,
      };

      if (!session.last_seen_at || Date.now() - session.last_seen_at.getTime() > LAST_SEEN_REFRESH_MS) {
        void pool
          .query('UPDATE sessions SET last_seen_at = now() WHERE id = $1', [session.session_id])
          .catch(() => undefined);
      }
      next();
    })().catch(next);
  };
}
