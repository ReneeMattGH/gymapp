import type { Logger } from 'pino';
import type { Pool, PoolClient } from 'pg';
import type { Config } from '../config.js';
import { conflict, serviceUnavailable, unauthorized } from '../errors.js';
import type { Mailer } from './mailer.js';
import { hashPassword, verifyAgainstDummy, verifyPassword } from './passwords.js';
import { generateToken, hashToken } from './tokens.js';

export interface PublicUser {
  id: string;
  email: string;
  displayName: string | null;
  emailVerified: boolean;
}

export interface AuthTokens {
  accessToken: string;
  accessTokenExpiresAt: string;
  refreshToken: string;
  refreshTokenExpiresAt: string;
}

export interface AuthResult {
  user: PublicUser;
  tokens: AuthTokens;
}

interface UserRow {
  id: string;
  email: string;
  password_hash: string;
  display_name: string | null;
  email_verified_at: Date | null;
}

const VERIFICATION_TTL_MS = 24 * 60 * 60 * 1000;
const RESET_TTL_MS = 60 * 60 * 1000;

function toPublicUser(row: UserRow): PublicUser {
  return {
    id: row.id,
    email: row.email,
    displayName: row.display_name,
    emailVerified: row.email_verified_at !== null,
  };
}

function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

function isUniqueViolation(error: unknown): boolean {
  return typeof error === 'object' && error !== null && 'code' in error && error.code === '23505';
}

export function createAuthService(options: {
  pool: Pool;
  config: Config;
  mailer: Mailer;
  logger: Logger;
}) {
  const { pool, config, mailer, logger } = options;

  async function issueSession(client: PoolClient, userId: string): Promise<AuthTokens> {
    const accessToken = generateToken();
    const refreshToken = generateToken();
    const accessExpires = new Date(Date.now() + config.accessTokenTtlMinutes * 60_000);
    const refreshExpires = new Date(Date.now() + config.refreshTokenTtlDays * 86_400_000);

    const session = await client.query<{ id: string }>(
      `INSERT INTO sessions (user_id, access_token_hash, access_expires_at, expires_at)
       VALUES ($1, $2, $3, $4) RETURNING id`,
      [userId, hashToken(accessToken), accessExpires, refreshExpires],
    );
    const sessionId = session.rows[0]!.id;
    await client.query(
      `INSERT INTO refresh_tokens (session_id, user_id, token_hash, expires_at)
       VALUES ($1, $2, $3, $4)`,
      [sessionId, userId, hashToken(refreshToken), refreshExpires],
    );

    return {
      accessToken,
      accessTokenExpiresAt: accessExpires.toISOString(),
      refreshToken,
      refreshTokenExpiresAt: refreshExpires.toISOString(),
    };
  }

  async function sendVerification(user: UserRow): Promise<boolean> {
    if (!mailer.configured) return false;
    const token = generateToken();
    await pool.query(
      `INSERT INTO email_verifications (user_id, token_hash, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, hashToken(token), new Date(Date.now() + VERIFICATION_TTL_MS)],
    );
    await mailer.send({
      to: user.email,
      subject: 'Confirm your Forma email',
      text: [
        'Open this link in Forma to confirm your email address:',
        `${config.appLinkBase}/verify-email?token=${token}`,
        '',
        'The link expires in 24 hours. If you did not create a Forma account, ignore this message.',
      ].join('\n'),
    });
    return true;
  }

  return {
    async register(input: {
      email: string;
      password: string;
      displayName?: string | undefined;
    }): Promise<AuthResult & { emailVerificationSent: boolean }> {
      const email = normalizeEmail(input.email);
      const passwordHash = await hashPassword(input.password);
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const inserted = await client.query<UserRow>(
          `INSERT INTO users (email, password_hash, display_name)
           VALUES ($1, $2, $3)
           RETURNING id, email, password_hash, display_name, email_verified_at`,
          [email, passwordHash, input.displayName?.trim() || null],
        );
        const user = inserted.rows[0]!;
        const tokens = await issueSession(client, user.id);
        await client.query('COMMIT');

        let emailVerificationSent = false;
        try {
          emailVerificationSent = await sendVerification(user);
        } catch (error) {
          logger.warn({ err: error, userId: user.id }, 'verification email could not be sent');
        }
        return { user: toPublicUser(user), tokens, emailVerificationSent };
      } catch (error) {
        await client.query('ROLLBACK');
        if (isUniqueViolation(error)) {
          throw conflict('email_taken', 'An account with that email already exists.');
        }
        throw error;
      } finally {
        client.release();
      }
    },

    async login(input: { email: string; password: string }): Promise<AuthResult> {
      const email = normalizeEmail(input.email);
      const found = await pool.query<UserRow>(
        `SELECT id, email, password_hash, display_name, email_verified_at
         FROM users WHERE lower(email) = $1`,
        [email],
      );
      const user = found.rows[0];
      if (!user) {
        await verifyAgainstDummy(input.password);
        throw unauthorized('Incorrect email or password.');
      }
      if (!(await verifyPassword(user.password_hash, input.password))) {
        throw unauthorized('Incorrect email or password.');
      }
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const tokens = await issueSession(client, user.id);
        await client.query('COMMIT');
        return { user: toPublicUser(user), tokens };
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    },

    async refresh(refreshToken: string): Promise<AuthTokens> {
      const invalid = unauthorized('Your session expired. Sign in again.');
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const tokenResult = await client.query<{
          id: string;
          session_id: string;
          user_id: string;
          expires_at: Date;
          rotated_at: Date | null;
          revoked_at: Date | null;
        }>(
          `SELECT id, session_id, user_id, expires_at, rotated_at, revoked_at
           FROM refresh_tokens WHERE token_hash = $1 FOR UPDATE`,
          [hashToken(refreshToken)],
        );
        const stored = tokenResult.rows[0];
        if (!stored) {
          await client.query('ROLLBACK');
          throw invalid;
        }
        if (stored.revoked_at || stored.expires_at.getTime() <= Date.now()) {
          await client.query('ROLLBACK');
          throw invalid;
        }
        if (stored.rotated_at) {
          // A rotated token being presented again means it leaked. Kill the session.
          await client.query('UPDATE sessions SET revoked_at = now() WHERE id = $1', [
            stored.session_id,
          ]);
          await client.query(
            `UPDATE refresh_tokens SET revoked_at = now()
             WHERE session_id = $1 AND revoked_at IS NULL`,
            [stored.session_id],
          );
          await client.query('COMMIT');
          logger.warn({ sessionId: stored.session_id }, 'refresh token reuse detected');
          throw invalid;
        }

        const sessionResult = await client.query<{ id: string; expires_at: Date; revoked_at: Date | null }>(
          'SELECT id, expires_at, revoked_at FROM sessions WHERE id = $1 FOR UPDATE',
          [stored.session_id],
        );
        const session = sessionResult.rows[0];
        if (!session || session.revoked_at || session.expires_at.getTime() <= Date.now()) {
          await client.query('ROLLBACK');
          throw invalid;
        }

        const accessToken = generateToken();
        const nextRefresh = generateToken();
        const accessExpires = new Date(Date.now() + config.accessTokenTtlMinutes * 60_000);
        const refreshExpires = new Date(Date.now() + config.refreshTokenTtlDays * 86_400_000);

        const inserted = await client.query<{ id: string }>(
          `INSERT INTO refresh_tokens (session_id, user_id, token_hash, expires_at)
           VALUES ($1, $2, $3, $4) RETURNING id`,
          [stored.session_id, stored.user_id, hashToken(nextRefresh), refreshExpires],
        );
        await client.query(
          `UPDATE refresh_tokens SET rotated_at = now(), replaced_by = $2 WHERE id = $1`,
          [stored.id, inserted.rows[0]!.id],
        );
        // Rotation replaces the access token and slides the session and the
        // new refresh token to the same 30-day deadline.
        await client.query(
          `UPDATE sessions
              SET access_token_hash = $2, access_expires_at = $3, expires_at = $4
            WHERE id = $1`,
          [stored.session_id, hashToken(accessToken), accessExpires, refreshExpires],
        );
        await client.query('COMMIT');

        return {
          accessToken,
          accessTokenExpiresAt: accessExpires.toISOString(),
          refreshToken: nextRefresh,
          refreshTokenExpiresAt: refreshExpires.toISOString(),
        };
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
    },

    async logout(accessToken: string): Promise<void> {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const session = await client.query<{ id: string }>(
          `UPDATE sessions SET revoked_at = now()
           WHERE access_token_hash = $1 AND revoked_at IS NULL RETURNING id`,
          [hashToken(accessToken)],
        );
        const sessionId = session.rows[0]?.id;
        if (sessionId) {
          await client.query(
            `UPDATE refresh_tokens SET revoked_at = now()
             WHERE session_id = $1 AND revoked_at IS NULL`,
            [sessionId],
          );
        }
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    },

    async me(userId: string): Promise<PublicUser> {
      const result = await pool.query<UserRow>(
        `SELECT id, email, password_hash, display_name, email_verified_at
         FROM users WHERE id = $1`,
        [userId],
      );
      const user = result.rows[0];
      if (!user) throw unauthorized();
      return toPublicUser(user);
    },

    async deleteAccount(userId: string, password: string): Promise<void> {
      const result = await pool.query<UserRow>(
        'SELECT id, email, password_hash, display_name, email_verified_at FROM users WHERE id = $1',
        [userId],
      );
      const user = result.rows[0];
      if (!user || !(await verifyPassword(user.password_hash, password))) {
        throw unauthorized('Password is incorrect.');
      }
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        // Pending user-submitted gyms are only visible to their submitter. Left
        // behind they become rows nobody can see or re-submit, because dedupe
        // still treats them as existing. Joined gyms stay put.
        await client.query(
          `DELETE FROM gyms g
            WHERE g.submitted_by = $1
              AND g.verification_status = 'pending'
              AND NOT EXISTS (
                SELECT 1 FROM gym_memberships m WHERE m.gym_id = g.id AND m.user_id <> $1
              )`,
          [userId],
        );
        await client.query('DELETE FROM users WHERE id = $1', [userId]);
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK');
        throw error;
      } finally {
        client.release();
      }
    },

    async changePassword(
      userId: string,
      currentSessionId: string,
      currentPassword: string,
      newPassword: string,
    ): Promise<void> {
      const result = await pool.query<UserRow>(
        'SELECT id, email, password_hash, display_name, email_verified_at FROM users WHERE id = $1',
        [userId],
      );
      const user = result.rows[0];
      if (!user || !(await verifyPassword(user.password_hash, currentPassword))) {
        throw unauthorized('Current password is incorrect.');
      }
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        await client.query('UPDATE users SET password_hash = $2, updated_at = now() WHERE id = $1', [
          userId,
          await hashPassword(newPassword),
        ]);
        // Other devices must sign in again; this session keeps working.
        await client.query(
          'UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND id <> $2 AND revoked_at IS NULL',
          [userId, currentSessionId],
        );
        await client.query(
          `UPDATE refresh_tokens SET revoked_at = now()
           WHERE user_id = $1 AND session_id <> $2 AND revoked_at IS NULL`,
          [userId, currentSessionId],
        );
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
    },

    async requestPasswordReset(email: string): Promise<void> {
      if (!mailer.configured) {
        throw serviceUnavailable(
          'email_delivery_unconfigured',
          'Password reset needs email delivery, which is not configured on this server.',
        );
      }
      const found = await pool.query<UserRow>(
        `SELECT id, email, password_hash, display_name, email_verified_at
         FROM users WHERE lower(email) = $1`,
        [normalizeEmail(email)],
      );
      const user = found.rows[0];
      if (!user) return;
      const token = generateToken();
      await pool.query(
        `INSERT INTO password_resets (user_id, token_hash, expires_at)
         VALUES ($1, $2, $3)`,
        [user.id, hashToken(token), new Date(Date.now() + RESET_TTL_MS)],
      );
      await mailer.send({
        to: user.email,
        subject: 'Reset your Forma password',
        text: [
          'Open this link in Forma to choose a new password:',
          `${config.appLinkBase}/reset-password?token=${token}`,
          '',
          'The link expires in one hour. If you did not request this, ignore this message.',
        ].join('\n'),
      });
    },

    async resetPassword(token: string, newPassword: string): Promise<void> {
      const invalid = unauthorized('This reset link is invalid or has expired.');
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const found = await client.query<{ id: string; user_id: string; expires_at: Date; consumed_at: Date | null }>(
          `SELECT id, user_id, expires_at, consumed_at FROM password_resets
           WHERE token_hash = $1 FOR UPDATE`,
          [hashToken(token)],
        );
        const reset = found.rows[0];
        if (!reset || reset.consumed_at || reset.expires_at.getTime() <= Date.now()) {
          await client.query('ROLLBACK');
          throw invalid;
        }
        await client.query('UPDATE password_resets SET consumed_at = now() WHERE id = $1', [
          reset.id,
        ]);
        await client.query('UPDATE users SET password_hash = $2, updated_at = now() WHERE id = $1', [
          reset.user_id,
          await hashPassword(newPassword),
        ]);
        await client.query('UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [
          reset.user_id,
        ]);
        await client.query(
          `UPDATE refresh_tokens SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL`,
          [reset.user_id],
        );
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
    },

    async verifyEmail(token: string): Promise<void> {
      const invalid = unauthorized('This confirmation link is invalid or has expired.');
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const found = await client.query<{ id: string; user_id: string; expires_at: Date; consumed_at: Date | null }>(
          `SELECT id, user_id, expires_at, consumed_at FROM email_verifications
           WHERE token_hash = $1 FOR UPDATE`,
          [hashToken(token)],
        );
        const verification = found.rows[0];
        if (!verification || verification.consumed_at || verification.expires_at.getTime() <= Date.now()) {
          await client.query('ROLLBACK');
          throw invalid;
        }
        await client.query('UPDATE email_verifications SET consumed_at = now() WHERE id = $1', [
          verification.id,
        ]);
        await client.query(
          'UPDATE users SET email_verified_at = now(), updated_at = now() WHERE id = $1',
          [verification.user_id],
        );
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
    },

    async resendVerification(userId: string): Promise<{ sent: boolean }> {
      if (!mailer.configured) {
        throw serviceUnavailable(
          'email_delivery_unconfigured',
          'Email delivery is not configured on this server, so no message was sent.',
        );
      }
      const result = await pool.query<UserRow>(
        'SELECT id, email, password_hash, display_name, email_verified_at FROM users WHERE id = $1',
        [userId],
      );
      const user = result.rows[0];
      if (!user) throw unauthorized();
      if (user.email_verified_at) return { sent: false };
      return { sent: await sendVerification(user) };
    },
  };
}

export type AuthService = ReturnType<typeof createAuthService>;
