import { randomUUID } from 'node:crypto';
import type { Server } from 'socket.io';
import type { Pool } from 'pg';
import type { Logger } from 'pino';
import { hashToken } from '../auth/tokens.js';
import type { CommunityRealtime } from './service.js';

export function userRoom(userId: string): string {
  return `user:${userId}`;
}

/**
 * Authenticated Socket.IO. A connection only joins its own user room, so a
 * client can never subscribe to another member's stream. The token is checked
 * against the live session table on every (re)connect; revocation ends the
 * stream on the next reconnect attempt.
 */
export function attachCommunityRealtime(options: {
  io: Server;
  pool: Pool;
  logger: Logger;
}): CommunityRealtime {
  const { io, pool, logger } = options;

  io.use((socket, next) => {
    void (async () => {
      const rawToken =
        (typeof socket.handshake.auth?.token === 'string' && socket.handshake.auth.token) ||
        (typeof socket.handshake.query?.token === 'string' && socket.handshake.query.token) ||
        '';
      if (rawToken.length < 20) {
        next(new Error('Authentication required.'));
        return;
      }
      const result = await pool.query<{ user_id: string }>(
        `SELECT s.user_id
           FROM sessions s
          WHERE s.access_token_hash = $1
            AND s.revoked_at IS NULL
            AND s.expires_at > now()`,
        [hashToken(rawToken)],
      );
      const userId = result.rows[0]?.user_id;
      if (!userId) {
        next(new Error('Authentication required.'));
        return;
      }
      socket.data.userId = userId;
      socket.data.streamId = randomUUID();
      next();
    })().catch((error: unknown) => {
      logger.warn({ err: error }, 'community socket authentication failed');
      next(new Error('Authentication required.'));
    });
  });

  io.on('connection', (socket) => {
    const userId = socket.data.userId as string;
    socket.join(userRoom(userId));
    socket.emit('ready', { user_id: userId, stream_id: socket.data.streamId });
    socket.on('disconnect', () => {
      logger.debug({ userId, socketId: socket.id }, 'community socket disconnected');
    });
  });

  return {
    emitToUser(userId: string, event: string, payload: unknown): void {
      io.to(userRoom(userId)).emit(event, payload);
    },
  };
}
