import { randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { Logger } from 'pino';
import type { Pool, PoolClient } from 'pg';
import type { Config } from '../config.js';
import { badRequest, forbidden, notFound } from '../errors.js';

/** Every method is called with the authenticated session user, never a client id. */
export interface CommunityViewer {
  userId: string;
  email: string;
}

/** Realtime delivery. Implementations must not expose rows to other users. */
export interface CommunityRealtime {
  emitToUser(userId: string, event: string, payload: unknown): void;
}

export const noRealtime: CommunityRealtime = { emitToUser: () => undefined };

type Row = Record<string, any>;

interface PostSummary {
  sessionId: string;
  title: string;
  startedAt?: string | null;
  durationSeconds: number;
}

function clamp(value: number | undefined, fallback: number, max: number): number {
  if (value === undefined || Number.isNaN(value)) return fallback;
  return Math.min(Math.max(Math.trunc(value), 1), max);
}

function offsetOf(value: number | undefined): number {
  if (value === undefined || Number.isNaN(value)) return 0;
  return Math.max(Math.trunc(value), 0);
}

function clean(value: string | null | undefined): string {
  return (value ?? '').trim();
}

function message(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export function createCommunityService(options: {
  pool: Pool;
  config: Config;
  realtime: CommunityRealtime;
  logger: Logger;
}) {
  const { pool, config, realtime, logger } = options;

  const adminEmailSet = new Set(config.communityAdminEmails.map((email) => email.toLowerCase()));

  function isAdmin(viewer: CommunityViewer): boolean {
    return adminEmailSet.has(viewer.email.trim().toLowerCase());
  }

  function requireAdmin(viewer: CommunityViewer): void {
    if (!isAdmin(viewer)) throw forbidden('Administrator access required.');
  }

  async function suspended(userId: string): Promise<boolean> {
    const result = await pool.query<{ suspended: boolean }>(
      'SELECT community_is_suspended($1) AS suspended',
      [userId],
    );
    return result.rows[0]?.suspended ?? false;
  }

  async function requireActive(userId: string, action = 'do that'): Promise<void> {
    if (await suspended(userId)) {
      throw forbidden(`This account is suspended and cannot ${action} right now.`);
    }
  }

  async function profileName(userId: string): Promise<string> {
    const result = await pool.query<{ display_name: string }>(
      'SELECT display_name FROM community_profiles WHERE user_id = $1',
      [userId],
    );
    return result.rows[0]?.display_name ?? 'A member';
  }

  async function notify(input: {
    userId: string;
    kind: string;
    actorId?: string | null;
    entityId?: string | null;
    postId?: string | null;
    body: string;
    preference?: 'connections' | 'messages' | 'comments' | 'likes';
  }): Promise<void> {
    if (input.userId === input.actorId) return;
    if (input.preference) {
      const column = `notify_${input.preference}`;
      const pref = await pool.query<{ allowed: boolean }>(
        `SELECT coalesce((SELECT ${column} FROM community_preferences WHERE user_id = $1), true) AS allowed`,
        [input.userId],
      );
      if (!pref.rows[0]?.allowed) return;
    }
    const inserted = await pool.query<Row>(
      `INSERT INTO community_notifications (user_id, kind, actor_id, entity_id, post_id, body)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [input.userId, input.kind, input.actorId ?? null, input.entityId ?? null, input.postId ?? null, input.body.slice(0, 160)],
    );
    if (inserted.rows[0]) {
      realtime.emitToUser(input.userId, 'notification', inserted.rows[0]);
    }
  }

  const profileColumns = `
    cp.user_id, cp.username, cp.display_name, cp.bio, cp.avatar_url,
    cp.interests, cp.workout_categories, cp.achievements_opt_in,
    cp.created_at, cp.updated_at`;

  async function discover(
    viewer: CommunityViewer,
    scope: string,
    query: string,
    interest: string,
    limitInput: number | undefined,
    offsetInput: number | undefined,
  ): Promise<Row[]> {
    const limit = clamp(limitInput, 20, 50);
    const offset = offsetOf(offsetInput);
    const result = await pool.query<Row>(
      `WITH eligible AS (
         SELECT cp.user_id, cp.username, cp.display_name, cp.avatar_url, cp.bio,
                cp.interests, cp.workout_categories,
                CASE WHEN pref.show_gym THEN g.name END AS gym_name,
                CASE WHEN pref.show_area THEN pref.area END AS area,
                CASE WHEN pref.show_area THEN pref.city END AS city,
                community_same_gym($1, cp.user_id) AS shares_gym,
                community_area_compatible($1, cp.user_id) AS shares_area
         FROM community_profiles cp
         JOIN community_preferences pref ON pref.user_id = cp.user_id
         LEFT JOIN gym_memberships gm ON gm.user_id = cp.user_id
         LEFT JOIN gyms g ON g.id = gm.gym_id
         WHERE cp.user_id <> $1
           AND pref.discoverable
           AND NOT community_is_suspended(cp.user_id)
           AND NOT community_is_suspended($1)
           AND community_not_blocked($1, cp.user_id)
           AND community_age_compatible($1, cp.user_id)
           AND (
             ($2 = 'gym' AND pref.show_gym AND community_same_gym($1, cp.user_id))
             OR ($2 = 'area' AND pref.show_area AND pref.nearby_discovery
                 AND community_area_compatible($1, cp.user_id))
             OR $2 = 'all'
           )
       )
       SELECT e.user_id, e.username, e.display_name, e.avatar_url, e.bio,
              e.interests, e.workout_categories, e.gym_name, e.area, e.city,
              community_connection_status($1, e.user_id) AS connection_status
       FROM eligible e
       WHERE (
           trim($3) = ''
           OR lower(e.username) LIKE '%' || lower(trim($3)) || '%'
           OR lower(e.display_name) LIKE '%' || lower(trim($3)) || '%'
           OR lower(coalesce(e.gym_name, '')) LIKE '%' || lower(trim($3)) || '%'
           OR lower(coalesce(e.area, '')) LIKE '%' || lower(trim($3)) || '%'
           OR lower(coalesce(e.city, '')) LIKE '%' || lower(trim($3)) || '%'
         )
         AND (
           trim($4) = ''
           OR EXISTS (SELECT 1 FROM unnest(e.interests) i WHERE lower(i) = lower(trim($4)))
           OR EXISTS (SELECT 1 FROM unnest(e.workout_categories) c WHERE lower(c) = lower(trim($4)))
         )
       ORDER BY e.shares_gym DESC, e.shares_area DESC, lower(e.display_name)
       LIMIT $5 OFFSET $6`,
      [viewer.userId, scope.toLowerCase(), query, interest, limit, offset],
    );
    return result.rows;
  }

  async function connectionList(viewer: CommunityViewer): Promise<Row[]> {
    const result = await pool.query<Row>(
      `SELECT c.id AS connection_id, other.user_id, other.username, other.display_name,
              other.avatar_url, c.status,
              CASE WHEN c.requester_id = $1 THEN 'sent' ELSE 'received' END AS direction,
              conv.id AS conversation_id, c.created_at
       FROM community_connections c
       JOIN LATERAL (
         SELECT cp.user_id, cp.username, cp.display_name, cp.avatar_url
         FROM community_profiles cp
         WHERE cp.user_id = CASE WHEN c.requester_id = $1 THEN c.recipient_id ELSE c.requester_id END
       ) other ON true
       LEFT JOIN community_conversations conv ON conv.connection_id = c.id
       WHERE (c.requester_id = $1 OR c.recipient_id = $1)
         AND c.status IN ('pending', 'accepted')
         AND community_not_blocked($1, other.user_id)
       ORDER BY c.status = 'pending' DESC, c.created_at DESC`,
      [viewer.userId],
    );
    return result.rows;
  }

  async function feed(
    viewer: CommunityViewer,
    filter: string,
    limitInput: number | undefined,
    offsetInput: number | undefined,
  ): Promise<Row[]> {
    const limit = clamp(limitInput, 20, 50);
    const offset = offsetOf(offsetInput);
    const admin = isAdmin(viewer);
    const result = await pool.query<Row>(
      `SELECT p.id, p.author_id, cp.username, cp.display_name, cp.avatar_url,
              p.content, p.kind, p.achievement_label, p.like_count, p.comment_count,
              EXISTS (SELECT 1 FROM community_likes l WHERE l.post_id = p.id AND l.user_id = $1) AS liked,
              p.author_id = $1 AS is_own,
              p.shared_session, p.created_at, p.updated_at
       FROM community_posts p
       JOIN community_profiles cp ON cp.user_id = p.author_id
       WHERE (p.moderation_status = 'visible' OR p.author_id = $1 OR $2)
         AND community_can_read_post($1, p.id, $2)
         AND NOT EXISTS (
           SELECT 1 FROM community_hidden_posts h WHERE h.post_id = p.id AND h.user_id = $1
         )
         AND (
           $3 = 'all'
           OR ($3 = 'connections' AND community_connected($1, p.author_id))
           OR ($3 = 'gym' AND community_same_gym($1, p.author_id))
         )
       ORDER BY p.created_at DESC, p.id DESC
       LIMIT $4 OFFSET $5`,
      [viewer.userId, admin, filter.toLowerCase(), limit, offset],
    );
    return result.rows;
  }

  async function conversations(viewer: CommunityViewer): Promise<Row[]> {
    const result = await pool.query<Row>(
      `SELECT conv.id AS conversation_id, c.id AS connection_id, other.user_id,
              other.username, other.display_name, other.avatar_url,
              (SELECT m.body FROM community_messages m
                WHERE m.conversation_id = conv.id ORDER BY m.created_at DESC LIMIT 1) AS last_message,
              (SELECT m.created_at FROM community_messages m
                WHERE m.conversation_id = conv.id ORDER BY m.created_at DESC LIMIT 1) AS last_message_at,
              (SELECT count(*)::int FROM community_messages m
                LEFT JOIN community_conversation_reads r
                  ON r.conversation_id = conv.id AND r.user_id = $1
                WHERE m.conversation_id = conv.id
                  AND m.sender_id <> $1
                  AND m.created_at > coalesce(r.last_read_at, 'epoch'::timestamptz)) AS unread_count,
              EXISTS (SELECT 1 FROM community_conversation_mutes mute
                       WHERE mute.conversation_id = conv.id AND mute.user_id = $1) AS muted
       FROM community_conversations conv
       JOIN community_connections c ON c.id = conv.connection_id
       JOIN LATERAL (
         SELECT cp.user_id, cp.username, cp.display_name, cp.avatar_url
         FROM community_profiles cp
         WHERE cp.user_id = CASE WHEN c.requester_id = $1 THEN c.recipient_id ELSE c.requester_id END
       ) other ON true
       WHERE c.status = 'accepted'
         AND (c.requester_id = $1 OR c.recipient_id = $1)
         AND community_not_blocked($1, other.user_id)
       ORDER BY last_message_at DESC NULLS LAST`,
      [viewer.userId],
    );
    return result.rows;
  }

  async function audit(
    adminId: string,
    action: string,
    targetType: string,
    targetId: string | null,
    note: string | null,
    db: Pool | PoolClient = pool,
  ): Promise<void> {
    await db.query(
      `INSERT INTO community_moderation_actions (admin_id, action, target_type, target_id, note)
       VALUES ($1, $2, $3, $4, $5)`,
      [adminId, action, targetType, targetId, note],
    );
  }

  async function suspendUser(
    admin: CommunityViewer,
    targetId: string,
    isSuspended: boolean,
    reason: string | null,
    recordAction = true,
    db: Pool | PoolClient = pool,
  ): Promise<void> {
    if (targetId === admin.userId) throw forbidden('You cannot suspend your own account.');
    const exists = await db.query('SELECT 1 FROM users WHERE id = $1', [targetId]);
    if (exists.rowCount === 0) throw notFound('That member could not be found.');
    await db.query(
      `INSERT INTO community_account_status (user_id, suspended, suspended_reason, suspended_at, suspended_by)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (user_id) DO UPDATE SET
         suspended = excluded.suspended,
         suspended_reason = excluded.suspended_reason,
         suspended_at = excluded.suspended_at,
         suspended_by = excluded.suspended_by,
         updated_at = now()`,
      [targetId, isSuspended, isSuspended ? reason : null, isSuspended ? new Date() : null, isSuspended ? admin.userId : null],
    );
    if (recordAction) {
      await audit(admin.userId, isSuspended ? 'suspend_user' : 'reinstate_user', 'profile', targetId, reason, db);
    }
  }

  return {
    // MARK: - Bootstrap

    async bootstrap(viewer: CommunityViewer): Promise<Row> {
      const userId = viewer.userId;
      const [
        profileResult,
        preferencesResult,
        membershipResult,
        statusResult,
        countsResult,
        notificationsResult,
        messagesResult,
        incomingResult,
        areasResult,
      ] = await Promise.all([
        pool.query<Row>(`SELECT ${profileColumns} FROM community_profiles cp WHERE cp.user_id = $1`, [userId]),
        pool.query<Row>('SELECT * FROM community_preferences WHERE user_id = $1', [userId]),
        pool.query<Row>(
          `SELECT g.id AS gym_id, g.name AS gym_name, g.address, g.city, g.area, g.verification_status
           FROM gym_memberships gm JOIN gyms g ON g.id = gm.gym_id WHERE gm.user_id = $1`,
          [userId],
        ),
        pool.query<{ suspended: boolean; age_band: string }>(
          `SELECT community_is_suspended($1) AS suspended,
                  community_age_band($1) AS age_band`,
          [userId],
        ),
        pool.query<{ gym_count: number; area_count: number; request_count: number }>(
          `SELECT
             (SELECT count(*)::int
                FROM community_profiles cp
                JOIN community_preferences pref ON pref.user_id = cp.user_id
               WHERE cp.user_id <> $1 AND pref.discoverable AND pref.show_gym
                 AND NOT community_is_suspended(cp.user_id)
                 AND NOT community_is_suspended($1)
                 AND community_not_blocked($1, cp.user_id)
                 AND community_age_compatible($1, cp.user_id)
                 AND community_same_gym($1, cp.user_id)) AS gym_count,
             (SELECT count(*)::int
                FROM community_profiles cp
                JOIN community_preferences pref ON pref.user_id = cp.user_id
               WHERE cp.user_id <> $1 AND pref.discoverable AND pref.show_area AND pref.nearby_discovery
                 AND NOT community_is_suspended(cp.user_id)
                 AND NOT community_is_suspended($1)
                 AND community_not_blocked($1, cp.user_id)
                 AND community_age_compatible($1, cp.user_id)
                 AND community_area_compatible($1, cp.user_id)) AS area_count,
             (SELECT count(*)::int FROM community_connections c
               WHERE c.recipient_id = $1 AND c.status = 'pending') AS request_count`,
          [userId],
        ),
        pool.query<{ count: number }>(
          'SELECT count(*)::int AS count FROM community_notifications WHERE user_id = $1 AND read_at IS NULL',
          [userId],
        ),
        pool.query<{ count: number }>(
          `SELECT count(*)::int AS count
             FROM community_conversations conv
             JOIN community_connections c ON c.id = conv.connection_id
            WHERE (c.requester_id = $1 OR c.recipient_id = $1)
              AND EXISTS (
                SELECT 1 FROM community_messages m
                 WHERE m.conversation_id = conv.id AND m.sender_id <> $1
                   AND m.created_at > coalesce(
                     (SELECT r.last_read_at FROM community_conversation_reads r
                       WHERE r.conversation_id = conv.id AND r.user_id = $1),
                     'epoch'::timestamptz)
              )`,
          [userId],
        ),
        pool.query<Row>(
          `SELECT c.id AS connection_id, c.requester_id AS user_id, cp.username, cp.display_name,
                  cp.avatar_url, c.created_at
             FROM community_connections c
             JOIN community_profiles cp ON cp.user_id = c.requester_id
            WHERE c.recipient_id = $1 AND c.status = 'pending'
              AND NOT community_is_suspended(c.requester_id)
              AND community_not_blocked($1, c.requester_id)
            ORDER BY c.created_at DESC`,
          [userId],
        ),
        pool.query<Row>('SELECT city, area, nearby_group FROM community_areas ORDER BY area'),
      ]);

      const suggestions = await discover(viewer, 'gym', '', '', 5, 0);
      const nearby = await discover(viewer, 'area', '', '', 5, 0);
      const feedRows = await feed(viewer, 'all', 5, 0);
      const connections = (await connectionList(viewer)).filter((row) => row.status === 'accepted').slice(0, 5);
      const counts = countsResult.rows[0];

      return {
        profile: profileResult.rows[0] ?? null,
        preferences: preferencesResult.rows[0] ?? null,
        membership: membershipResult.rows[0] ?? null,
        is_admin: isAdmin(viewer),
        suspended: statusResult.rows[0]?.suspended ?? false,
        members_at_gym: counts?.gym_count ?? 0,
        nearby_members: counts?.area_count ?? 0,
        incoming_request_count: counts?.request_count ?? 0,
        unread_notifications: notificationsResult.rows[0]?.count ?? 0,
        unread_messages: messagesResult.rows[0]?.count ?? 0,
        suggestions,
        nearby,
        incoming_requests: incomingResult.rows,
        connections,
        feed: feedRows,
        areas: areasResult.rows,
      };
    },

    discover,
    feed,
    conversations,

    async searchGyms(viewer: CommunityViewer, query: string, limitInput?: number, offsetInput?: number): Promise<Row[]> {
      const limit = clamp(limitInput, 20, 50);
      const offset = offsetOf(offsetInput);
      const result = await pool.query<Row>(
        `SELECT g.id, g.name, g.address, g.city, g.state, g.country, g.area,
                g.verification_status,
                (SELECT count(*)::int FROM gym_memberships gm WHERE gm.gym_id = g.id) AS member_count
           FROM gyms g
          WHERE (g.verification_status = 'verified' OR g.submitted_by = $1 OR $2)
            AND (
              trim($3) = ''
              OR lower(g.name) LIKE '%' || lower(trim($3)) || '%'
              OR lower(g.city) LIKE '%' || lower(trim($3)) || '%'
              OR lower(coalesce(g.area, '')) LIKE '%' || lower(trim($3)) || '%'
            )
          ORDER BY (g.verification_status = 'verified') DESC, g.name
          LIMIT $4 OFFSET $5`,
        [viewer.userId, isAdmin(viewer), query, limit, offset],
      );
      return result.rows;
    },

    async requestGym(
      viewer: CommunityViewer,
      input: { name: string; city: string; area?: string | null; address?: string | null },
    ): Promise<Row> {
      await requireActive(viewer.userId, 'submit gyms');
      const name = clean(input.name);
      const city = clean(input.city);
      if (name.length < 2 || city.length < 2) throw badRequest('invalid_gym', 'Enter the gym name and city.');
      const existing = await pool.query<Row>(
        `SELECT id, verification_status FROM gyms
          WHERE lower(name) = lower($1)
            AND lower(city) = lower($2)
            AND lower(coalesce(area, '')) = lower($3)`,
        [name, city, clean(input.area)],
      );
      if (existing.rows[0]) {
        return { id: existing.rows[0].id, status: existing.rows[0].verification_status, created: false };
      }
      const created = await pool.query<Row>(
        `INSERT INTO gyms (name, city, area, address, submitted_by)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, verification_status`,
        [name, city, clean(input.area) || null, clean(input.address) || null, viewer.userId],
      );
      return { id: created.rows[0]!.id, status: created.rows[0]!.verification_status, created: true };
    },

    async joinGym(viewer: CommunityViewer, gymId: string): Promise<void> {
      await requireActive(viewer.userId, 'join a gym community');
      const chosen = await pool.query<Row>('SELECT * FROM gyms WHERE id = $1', [gymId]);
      const gym = chosen.rows[0];
      if (!gym) throw notFound('That gym could not be found.');
      if (gym.verification_status !== 'verified' && gym.submitted_by !== viewer.userId) {
        throw forbidden('This gym is still awaiting review.');
      }
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        await client.query(
          `INSERT INTO gym_memberships (user_id, gym_id) VALUES ($1, $2)
           ON CONFLICT (user_id) DO UPDATE SET gym_id = excluded.gym_id, created_at = now()`,
          [viewer.userId, gymId],
        );
        await client.query(
          `INSERT INTO community_preferences (user_id, city, area) VALUES ($1, $2, $3)
           ON CONFLICT (user_id) DO UPDATE SET city = excluded.city, area = excluded.area, updated_at = now()`,
          [viewer.userId, gym.city, gym.area],
        );
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
    },

    async leaveGym(viewer: CommunityViewer): Promise<void> {
      await pool.query('DELETE FROM gym_memberships WHERE user_id = $1', [viewer.userId]);
    },

    async setArea(viewer: CommunityViewer, cityInput: string, areaInput: string): Promise<void> {
      const city = clean(cityInput);
      const area = clean(areaInput);
      if (city.length < 2 || area.length < 2) throw badRequest('invalid_area', 'Enter a city and area.');
      if (city.length > 60 || area.length > 60) throw badRequest('invalid_area', 'That city or area name is too long.');
      await pool.query(
        `INSERT INTO community_preferences (user_id, city, area) VALUES ($1, $2, $3)
         ON CONFLICT (user_id) DO UPDATE SET city = excluded.city, area = excluded.area, updated_at = now()`,
        [viewer.userId, city, area],
      );
    },

    async saveProfile(
      viewer: CommunityViewer,
      input: {
        username: string;
        displayName: string;
        bio?: string | null;
        interests: string[];
        categories: string[];
        avatarURL?: string | null;
        age?: number | null;
      },
    ): Promise<Row> {
      await requireActive(viewer.userId, 'change its community profile');
      let base = clean(input.username).toLowerCase().replace(/[^a-z0-9_]/g, '');
      if (base === '') base = `member_${viewer.userId.replace(/-/g, '').slice(0, 8)}`;
      if (base.length < 3) throw badRequest('invalid_username', 'Usernames need at least three letters or numbers.');
      let candidate = base.slice(0, 24);
      const taken = async (name: string) => {
        const found = await pool.query(
          'SELECT 1 FROM community_profiles WHERE lower(username) = lower($1) AND user_id <> $2',
          [name, viewer.userId],
        );
        return (found.rowCount ?? 0) > 0;
      };
      if (await taken(candidate)) {
        candidate = `${base.slice(0, 17)}_${viewer.userId.replace(/-/g, '').slice(0, 6)}`;
      }
      if (await taken(candidate)) throw badRequest('username_taken', 'That username is already taken.');
      if (clean(input.displayName).length < 2) throw badRequest('invalid_display_name', 'Add a display name.');
      const avatar = clean(input.avatarURL);
      if (avatar !== '') {
        let parsed: URL;
        try {
          parsed = new URL(avatar);
        } catch {
          throw badRequest('invalid_avatar', 'The photo address is not a valid URL.');
        }
        if (!['http:', 'https:'].includes(parsed.protocol)) {
          throw badRequest('invalid_avatar', 'The photo address must use HTTP or HTTPS.');
        }
      }

      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const saved = await client.query<Row>(
          `INSERT INTO community_profiles
             (user_id, username, display_name, bio, avatar_url, interests, workout_categories)
           VALUES ($1, $2, $3, $4, $5, $6, $7)
           ON CONFLICT (user_id) DO UPDATE SET
             username = excluded.username,
             display_name = excluded.display_name,
             bio = excluded.bio,
             avatar_url = excluded.avatar_url,
             interests = excluded.interests,
             workout_categories = excluded.workout_categories,
             updated_at = now()
           RETURNING ${profileColumns.replaceAll('cp.', '')}`,
          [
            viewer.userId,
            candidate,
            clean(input.displayName),
            clean(input.bio) || null,
            avatar || null,
            input.interests.slice(0, 8),
            input.categories.slice(0, 8),
          ],
        );
        await client.query(
          'INSERT INTO community_preferences (user_id) VALUES ($1) ON CONFLICT (user_id) DO NOTHING',
          [viewer.userId],
        );
        const age = input.age;
        const ageBand = age == null ? 'unknown' : age < 18 ? 'minor' : 'adult';
        await client.query(
          `INSERT INTO community_account_status (user_id, age_band) VALUES ($1, $2)
           ON CONFLICT (user_id) DO UPDATE SET age_band = excluded.age_band, updated_at = now()`,
          [viewer.userId, ageBand],
        );
        await client.query('COMMIT');
        return saved.rows[0]!;
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
    },

    async savePreferences(
      viewer: CommunityViewer,
      input: {
        discoverable: boolean;
        showGym: boolean;
        showArea: boolean;
        nearbyDiscovery: boolean;
        allowConnectionRequests: boolean;
        allowMessages: boolean;
        notifyConnections: boolean;
        notifyMessages: boolean;
        notifyComments: boolean;
        notifyLikes: boolean;
      },
    ): Promise<Row> {
      await requireActive(viewer.userId, 'change community settings');
      const saved = await pool.query<Row>(
        `INSERT INTO community_preferences
           (user_id, discoverable, show_gym, show_area, nearby_discovery,
            allow_connection_requests, allow_messages,
            notify_connections, notify_messages, notify_comments, notify_likes)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
         ON CONFLICT (user_id) DO UPDATE SET
           discoverable = excluded.discoverable,
           show_gym = excluded.show_gym,
           show_area = excluded.show_area,
           nearby_discovery = excluded.nearby_discovery,
           allow_connection_requests = excluded.allow_connection_requests,
           allow_messages = excluded.allow_messages,
           notify_connections = excluded.notify_connections,
           notify_messages = excluded.notify_messages,
           notify_comments = excluded.notify_comments,
           notify_likes = excluded.notify_likes,
           updated_at = now()
         RETURNING *`,
        [
          viewer.userId,
          input.discoverable,
          input.showGym,
          input.showArea,
          input.nearbyDiscovery,
          input.allowConnectionRequests,
          input.allowMessages,
          input.notifyConnections,
          input.notifyMessages,
          input.notifyComments,
          input.notifyLikes,
        ],
      );
      return saved.rows[0]!;
    },

    async uploadAvatar(viewer: CommunityViewer, data: Buffer, contentType: string): Promise<string> {
      await requireActive(viewer.userId, 'change its community profile');
      const extension = contentType === 'image/png' ? 'png' : 'jpg';
      const fileName = `${viewer.userId}-${randomUUID()}.${extension}`;
      await mkdir(config.uploadDir, { recursive: true });
      await writeFile(path.join(config.uploadDir, fileName), data);
      const base = config.publicBaseUrl ?? '';
      return base ? `${base}/uploads/${fileName}` : `/uploads/${fileName}`;
    },

    // MARK: - Connections and blocks

    async sendConnectionRequest(viewer: CommunityViewer, target: string): Promise<Row> {
      if (target === viewer.userId) throw badRequest('invalid_target', 'Choose another member to connect with.');
      if (await suspended(viewer.userId)) throw forbidden('This connection cannot be requested right now.');
      const targetStatus = await pool.query<{ suspended: boolean }>(
        'SELECT community_is_suspended($1) AS suspended', [target],
      );
      if (targetStatus.rows[0]?.suspended !== false) throw forbidden('This connection cannot be requested right now.');
      if ((await pool.query('SELECT community_not_blocked($1, $2) AS ok', [viewer.userId, target])).rows[0]?.ok !== true) {
        throw forbidden('This member is not available.');
      }
      if ((await pool.query('SELECT community_age_compatible($1, $2) AS ok', [viewer.userId, target])).rows[0]?.ok !== true) {
        throw forbidden('Connections are limited to members in the same age group.');
      }
      if ((await pool.query('SELECT community_can_view_profile($1, $2, $3) AS ok', [viewer.userId, target, isAdmin(viewer)])).rows[0]?.ok !== true) {
        throw forbidden('This member is not discoverable right now.');
      }
      const targetPref = await pool.query<{ allow_connection_requests: boolean }>(
        'SELECT allow_connection_requests FROM community_preferences WHERE user_id = $1', [target],
      );
      if (!targetPref.rows[0] || !targetPref.rows[0].allow_connection_requests) {
        throw forbidden('This member is not accepting connection requests right now.');
      }
      const existing = await pool.query<Row>(
        `SELECT id, status FROM community_connections
          WHERE status IN ('pending', 'accepted')
            AND ((requester_id = $1 AND recipient_id = $2) OR (requester_id = $2 AND recipient_id = $1))
          LIMIT 1`,
        [viewer.userId, target],
      );
      if (existing.rows[0]) {
        return { connection_id: existing.rows[0].id, status: existing.rows[0].status };
      }
      const recent = await pool.query<{ count: number }>(
        `SELECT count(*)::int AS count FROM community_connections
          WHERE requester_id = $1 AND created_at > now() - interval '24 hours'`,
        [viewer.userId],
      );
      if ((recent.rows[0]?.count ?? 0) >= 20) {
        throw forbidden('Too many connection requests today. Try again tomorrow.');
      }
      const created = await pool.query<Row>(
        `INSERT INTO community_connections (requester_id, recipient_id, status)
         VALUES ($1, $2, 'pending') RETURNING *`,
        [viewer.userId, target],
      );
      const connection = created.rows[0]!;
      const name = await profileName(viewer.userId);
      await notify({
        userId: target,
        kind: 'connection_request',
        actorId: viewer.userId,
        entityId: connection.id,
        body: `${name} wants to connect.`,
        preference: 'connections',
      });
      realtime.emitToUser(target, 'activity', { kind: 'connection_request', entity_id: connection.id });
      return { connection_id: connection.id, status: connection.status };
    },

    async respondToConnection(viewer: CommunityViewer, id: string, accept: boolean): Promise<Row> {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const found = await client.query<Row>(
          `SELECT * FROM community_connections
            WHERE id = $1 AND recipient_id = $2 AND status = 'pending' FOR UPDATE`,
          [id, viewer.userId],
        );
        const connection = found.rows[0];
        if (!connection) throw notFound('This request is no longer available.');
        const allowed = await client.query<{ ok: boolean }>(
          'SELECT community_not_blocked($1, $2) AS ok', [viewer.userId, connection.requester_id],
        );
        if (!allowed.rows[0]?.ok) throw forbidden('This request is not available.');
        const updated = await client.query<Row>(
          `UPDATE community_connections SET status = $2, responded_at = now()
            WHERE id = $1 RETURNING *`,
          [connection.id, accept ? 'accepted' : 'declined'],
        );
        let conversationId: string | null = null;
        if (accept) {
          const conversation = await client.query<Row>(
            `INSERT INTO community_conversations (connection_id) VALUES ($1)
             ON CONFLICT (connection_id) DO UPDATE SET connection_id = excluded.connection_id
             RETURNING id`,
            [connection.id],
          );
          conversationId = conversation.rows[0]!.id;
          await client.query(
            `INSERT INTO community_conversation_reads (conversation_id, user_id) VALUES ($1, $2)
             ON CONFLICT (conversation_id, user_id) DO NOTHING`,
            [conversationId, viewer.userId],
          );
          await client.query(
            `INSERT INTO community_conversation_reads (conversation_id, user_id) VALUES ($1, $2)
             ON CONFLICT (conversation_id, user_id) DO NOTHING`,
            [conversationId, connection.requester_id],
          );
        }
        await client.query('COMMIT');
        if (accept) {
          const name = await profileName(viewer.userId);
          await notify({
            userId: connection.requester_id,
            kind: 'connection_accepted',
            actorId: viewer.userId,
            entityId: connection.id,
            body: `${name} accepted your connection request.`,
            preference: 'connections',
          });
        }
        realtime.emitToUser(connection.requester_id, 'activity', { kind: 'connection_response', entity_id: connection.id });
        return {
          connection_id: updated.rows[0]!.id,
          status: updated.rows[0]!.status,
          conversation_id: conversationId,
        };
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
    },

    async removeConnection(viewer: CommunityViewer, id: string): Promise<void> {
      const found = await pool.query<Row>(
        'SELECT requester_id, recipient_id FROM community_connections WHERE id = $1',
        [id],
      );
      const connection = found.rows[0];
      if (!connection || (connection.requester_id !== viewer.userId && connection.recipient_id !== viewer.userId)) {
        throw notFound('That connection could not be found.');
      }
      await pool.query('DELETE FROM community_connections WHERE id = $1', [id]);
      const other = connection.requester_id === viewer.userId ? connection.recipient_id : connection.requester_id;
      realtime.emitToUser(other, 'activity', { kind: 'connection_removed', entity_id: id });
    },

    async block(viewer: CommunityViewer, target: string, blocked: boolean): Promise<void> {
      if (target === viewer.userId) throw badRequest('invalid_target', 'Choose another member.');
      if (blocked) {
        await pool.query(
          `INSERT INTO community_blocks (blocker_id, blocked_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
          [viewer.userId, target],
        );
        await pool.query(
          `DELETE FROM community_connections
            WHERE status = 'pending'
              AND ((requester_id = $1 AND recipient_id = $2) OR (requester_id = $2 AND recipient_id = $1))`,
          [viewer.userId, target],
        );
      } else {
        await pool.query(
          'DELETE FROM community_blocks WHERE blocker_id = $1 AND blocked_id = $2',
          [viewer.userId, target],
        );
      }
      realtime.emitToUser(viewer.userId, 'activity', { kind: 'blocks_changed' });
    },

    async connections(viewer: CommunityViewer): Promise<Row[]> {
      return connectionList(viewer);
    },

    async blockedMembers(viewer: CommunityViewer): Promise<Row[]> {
      const result = await pool.query<Row>(
        `SELECT b.blocked_id AS user_id, cp.username, cp.display_name, cp.avatar_url,
                b.created_at AS blocked_at
           FROM community_blocks b
           LEFT JOIN community_profiles cp ON cp.user_id = b.blocked_id
          WHERE b.blocker_id = $1
          ORDER BY b.created_at DESC`,
        [viewer.userId],
      );
      return result.rows;
    },

    async publicProfile(viewer: CommunityViewer, targetUserId: string): Promise<Row | null> {
      const allowed = await pool.query<{ ok: boolean }>(
        'SELECT community_can_view_profile($1, $2, $3) AS ok',
        [viewer.userId, targetUserId, isAdmin(viewer)],
      );
      if (!allowed.rows[0]?.ok) return null;
      const result = await pool.query<Row>(
        `SELECT cp.user_id, cp.username, cp.display_name, cp.bio, cp.avatar_url,
                cp.interests, cp.workout_categories, cp.created_at AS joined_at,
                cp.achievements_opt_in,
                CASE WHEN pref.show_gym THEN g.name END AS gym_name,
                CASE WHEN pref.show_area THEN pref.city END AS city,
                CASE WHEN pref.show_area THEN pref.area END AS area,
                community_connection_status($1, cp.user_id) AS connection_status,
                community_same_gym($1, cp.user_id) AS shared_gym,
                community_area_compatible($1, cp.user_id) AS shared_area
           FROM community_profiles cp
           JOIN community_preferences pref ON pref.user_id = cp.user_id
           LEFT JOIN gym_memberships gm ON gm.user_id = cp.user_id
           LEFT JOIN gyms g ON g.id = gm.gym_id
          WHERE cp.user_id = $2`,
        [viewer.userId, targetUserId],
      );
      return result.rows[0] ?? null;
    },

    // MARK: - Feed

    async createPost(
      viewer: CommunityViewer,
      input: {
        id: string;
        content: string;
        kind: string;
        sessionID?: string | null;
        achievementLabel?: string | null;
        session?: PostSummary | null;
      },
    ): Promise<Row> {
      await requireActive(viewer.userId, 'post');
      const content = clean(input.content);
      if (content.length < 1 || content.length > 2000) {
        throw badRequest('invalid_post', 'Posts need between 1 and 2000 characters.');
      }
      const kind = input.kind.toLowerCase();
      if (!['workout', 'milestone', 'achievement', 'update', 'motivation'].includes(kind)) {
        throw badRequest('invalid_post', 'Choose a supported post type.');
      }
      const recent = await pool.query<{ count: number }>(
        `SELECT count(*)::int AS count FROM community_posts
          WHERE author_id = $1 AND created_at > now() - interval '24 hours'`,
        [viewer.userId],
      );
      if ((recent.rows[0]?.count ?? 0) >= 20) {
        throw forbidden("You have reached today's posting limit.");
      }
      const sharedSession = input.session
        ? {
            session_id: input.session.sessionId,
            title: input.session.title,
            started_at: input.session.startedAt ?? null,
            duration_seconds: input.session.durationSeconds,
          }
        : null;
      const created = await pool.query<Row>(
        `INSERT INTO community_posts (id, author_id, content, kind, shared_session, achievement_label)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (id) DO NOTHING
         RETURNING id, created_at`,
        [
          input.id,
          viewer.userId,
          content,
          kind,
          sharedSession,
          clean(input.achievementLabel) || null,
        ],
      );
      if (!created.rows[0]) {
        const existing = await pool.query<Row>('SELECT author_id, created_at FROM community_posts WHERE id = $1', [input.id]);
        if (existing.rows[0]?.author_id !== viewer.userId) {
          throw badRequest('invalid_post', 'That post id is already in use.');
        }
        return { id: input.id, created_at: existing.rows[0].created_at };
      }
      realtime.emitToUser(viewer.userId, 'activity', { kind: 'post_created', entity_id: input.id });
      return created.rows[0];
    },

    async updatePost(viewer: CommunityViewer, id: string, contentInput: string): Promise<void> {
      const content = clean(contentInput);
      if (content.length < 1 || content.length > 2000) {
        throw badRequest('invalid_post', 'Posts need between 1 and 2000 characters.');
      }
      const updated = await pool.query(
        `UPDATE community_posts SET content = $2, updated_at = now()
          WHERE id = $1 AND author_id = $3`,
        [id, content, viewer.userId],
      );
      if (updated.rowCount === 0) throw notFound('That post could not be edited.');
    },

    async deletePost(viewer: CommunityViewer, id: string): Promise<void> {
      const deleted = await pool.query(
        'DELETE FROM community_posts WHERE id = $1 AND author_id = $2',
        [id, viewer.userId],
      );
      if (deleted.rowCount === 0) throw notFound('That post could not be deleted.');
    },

    async toggleLike(viewer: CommunityViewer, postId: string, liked: boolean): Promise<Row> {
      const readable = await pool.query<{ ok: boolean }>(
        'SELECT community_can_read_post($1, $2, $3) AS ok',
        [viewer.userId, postId, isAdmin(viewer)],
      );
      if (!readable.rows[0]?.ok) throw notFound('That post is not available.');
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        let inserted = false;
        if (liked) {
          const result = await client.query(
            `INSERT INTO community_likes (post_id, user_id) VALUES ($1, $2)
             ON CONFLICT DO NOTHING`,
            [postId, viewer.userId],
          );
          inserted = (result.rowCount ?? 0) > 0;
        } else {
          await client.query('DELETE FROM community_likes WHERE post_id = $1 AND user_id = $2', [postId, viewer.userId]);
        }
        const counts = await client.query<Row>(
          `UPDATE community_posts p
              SET like_count = (SELECT count(*)::int FROM community_likes l WHERE l.post_id = p.id)
            WHERE p.id = $1
            RETURNING like_count, comment_count, author_id`,
          [postId],
        );
        await client.query('COMMIT');
        const post = counts.rows[0]!;
        if (inserted && post.author_id !== viewer.userId) {
          const name = await profileName(viewer.userId);
          await notify({
            userId: post.author_id,
            kind: 'post_like',
            actorId: viewer.userId,
            entityId: postId,
            postId,
            body: `${name} liked your post.`,
            preference: 'likes',
          });
          realtime.emitToUser(post.author_id, 'activity', { kind: 'post_liked', entity_id: postId });
        }
        return {
          liked: liked,
          like_count: post.like_count,
          comment_count: post.comment_count,
        };
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
    },

    async comments(viewer: CommunityViewer, postId: string, limitInput?: number, offsetInput?: number): Promise<Row[]> {
      const readable = await pool.query<{ ok: boolean }>(
        'SELECT community_can_read_post($1, $2, $3) AS ok',
        [viewer.userId, postId, isAdmin(viewer)],
      );
      if (!readable.rows[0]?.ok) throw notFound('That post is not available.');
      const result = await pool.query<Row>(
        `SELECT c.id, c.post_id, c.author_id, cp.username, cp.display_name, cp.avatar_url,
                c.content, c.author_id = $1 AS is_own, c.created_at
           FROM community_comments c
           JOIN community_profiles cp ON cp.user_id = c.author_id
          WHERE c.post_id = $2
            AND (c.moderation_status = 'visible' OR c.author_id = $1 OR $3)
          ORDER BY c.created_at ASC
          LIMIT $4 OFFSET $5`,
        [viewer.userId, postId, isAdmin(viewer), clamp(limitInput, 30, 50), offsetOf(offsetInput)],
      );
      return result.rows;
    },

    async addComment(viewer: CommunityViewer, input: { id: string; postID: string; content: string }): Promise<Row> {
      await requireActive(viewer.userId, 'comment');
      const content = clean(input.content);
      if (content.length < 1 || content.length > 1000) {
        throw badRequest('invalid_comment', 'Comments need between 1 and 1000 characters.');
      }
      const readable = await pool.query<{ ok: boolean }>(
        'SELECT community_can_read_post($1, $2, $3) AS ok',
        [viewer.userId, input.postID, isAdmin(viewer)],
      );
      if (!readable.rows[0]?.ok) throw notFound('That post is not available.');
      const recent = await pool.query<{ count: number }>(
        `SELECT count(*)::int AS count FROM community_comments
          WHERE author_id = $1 AND created_at > now() - interval '24 hours'`,
        [viewer.userId],
      );
      if ((recent.rows[0]?.count ?? 0) >= 100) {
        throw forbidden("You have reached today's comment limit.");
      }
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const created = await client.query<Row>(
          `INSERT INTO community_comments (id, post_id, author_id, content)
           VALUES ($1, $2, $3, $4)
           ON CONFLICT (id) DO NOTHING
           RETURNING id, created_at`,
          [input.id, input.postID, viewer.userId, content],
        );
        if (!created.rows[0]) {
          const existing = await client.query<Row>(
            'SELECT author_id, created_at FROM community_comments WHERE id = $1', [input.id],
          );
          if (existing.rows[0]?.author_id !== viewer.userId) {
            throw badRequest('invalid_comment', 'That comment id is already in use.');
          }
          await client.query('COMMIT');
          return { id: input.id, created_at: existing.rows[0].created_at };
        }
        const post = await client.query<Row>(
          `UPDATE community_posts p
              SET comment_count = (SELECT count(*)::int FROM community_comments c
                                    WHERE c.post_id = p.id AND c.moderation_status = 'visible')
            WHERE p.id = $1
            RETURNING author_id`,
          [input.postID],
        );
        await client.query('COMMIT');
        const authorId = post.rows[0]?.author_id;
        if (authorId && authorId !== viewer.userId) {
          const name = await profileName(viewer.userId);
          await notify({
            userId: authorId,
            kind: 'post_comment',
            actorId: viewer.userId,
            entityId: input.id,
            postId: input.postID,
            body: `${name} commented on your post.`,
            preference: 'comments',
          });
          realtime.emitToUser(authorId, 'activity', { kind: 'post_commented', entity_id: input.postID });
        }
        return created.rows[0];
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
    },

    async deleteComment(viewer: CommunityViewer, id: string): Promise<void> {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const deleted = await client.query<{ post_id: string }>(
          'DELETE FROM community_comments WHERE id = $1 AND author_id = $2 RETURNING post_id',
          [id, viewer.userId],
        );
        if (!deleted.rows[0]) throw notFound('That comment could not be deleted.');
        await client.query(
          `UPDATE community_posts p
              SET comment_count = (SELECT count(*)::int FROM community_comments c
                                    WHERE c.post_id = p.id AND c.moderation_status = 'visible')
            WHERE p.id = $1`,
          [deleted.rows[0].post_id],
        );
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
    },

    async hidePost(viewer: CommunityViewer, postId: string, hidden: boolean): Promise<void> {
      if (hidden) {
        await pool.query(
          `INSERT INTO community_hidden_posts (user_id, post_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`,
          [viewer.userId, postId],
        );
      } else {
        await pool.query(
          'DELETE FROM community_hidden_posts WHERE user_id = $1 AND post_id = $2',
          [viewer.userId, postId],
        );
      }
    },

    // MARK: - Messaging

    async messages(viewer: CommunityViewer, conversationId: string, before?: string | null, limitInput?: number): Promise<Row[]> {
      const participant = await pool.query<{ ok: boolean }>(
        'SELECT community_conversation_participant($1, $2) AS ok',
        [conversationId, viewer.userId],
      );
      if (!participant.rows[0]?.ok) throw notFound('That conversation is not available.');
      const result = await pool.query<Row>(
        `SELECT id, conversation_id, sender_id, body, created_at
           FROM community_messages
          WHERE conversation_id = $1
            AND ($2::timestamptz IS NULL OR created_at < $2::timestamptz)
          ORDER BY created_at DESC
          LIMIT $3`,
        [conversationId, before ?? null, clamp(limitInput, 30, 50)],
      );
      return result.rows;
    },

    async sendMessage(
      viewer: CommunityViewer,
      input: { id: string; conversationID: string; body: string },
    ): Promise<Row> {
      const participant = await pool.query<Row>(
        `SELECT c.requester_id, c.recipient_id
           FROM community_conversations conv
           JOIN community_connections c ON c.id = conv.connection_id
          WHERE conv.id = $1`,
        [input.conversationID],
      );
      const connection = participant.rows[0];
      if (!connection || (connection.requester_id !== viewer.userId && connection.recipient_id !== viewer.userId)) {
        throw notFound('That conversation is not available.');
      }
      const otherId = connection.requester_id === viewer.userId ? connection.recipient_id : connection.requester_id;
      const allowed = await pool.query<{ ok: boolean }>(
        'SELECT community_can_message($1, $2) AS ok', [viewer.userId, otherId],
      );
      if (!allowed.rows[0]?.ok) throw forbidden('Messaging is not available for this connection.');
      const body = clean(input.body);
      if (body.length < 1 || body.length > 2000) {
        throw badRequest('invalid_message', 'Messages need between 1 and 2000 characters.');
      }
      if (/(https?:\/\/|www\.|[a-z0-9-]+\.(com|net|org|io|co|ly|me)\b)/i.test(body)) {
        throw badRequest('links_not_supported', 'Links are not supported in messages yet.');
      }
      const existing = await pool.query<Row>('SELECT sender_id, conversation_id, created_at FROM community_messages WHERE id = $1', [input.id]);
      if (existing.rows[0]) {
        if (existing.rows[0].sender_id !== viewer.userId || existing.rows[0].conversation_id !== input.conversationID) {
          throw badRequest('message_id_taken', 'That message id is already in use.');
        }
        return { id: input.id, created_at: existing.rows[0].created_at, duplicate: true };
      }
      const recent = await pool.query<{ count: number }>(
        `SELECT count(*)::int AS count FROM community_messages
          WHERE sender_id = $1 AND created_at > now() - interval '1 minute'`,
        [viewer.userId],
      );
      if ((recent.rows[0]?.count ?? 0) >= 20) {
        throw forbidden('Slow down a moment before sending another message.');
      }
      const daily = await pool.query<{ count: number }>(
        `SELECT count(*)::int AS count FROM community_messages
          WHERE sender_id = $1 AND created_at > now() - interval '24 hours'`,
        [viewer.userId],
      );
      if ((daily.rows[0]?.count ?? 0) >= 500) {
        throw forbidden("You have reached today's message limit.");
      }
      const created = await pool.query<Row>(
        `INSERT INTO community_messages (id, conversation_id, sender_id, body)
         VALUES ($1, $2, $3, $4) RETURNING id, conversation_id, sender_id, body, created_at`,
        [input.id, input.conversationID, viewer.userId, body],
      );
      const row = created.rows[0]!;
      // Persisted before broadcast: if the insert throws, nothing is emitted.
      realtime.emitToUser(otherId, 'message', row);
      realtime.emitToUser(viewer.userId, 'message', row);
      const name = await profileName(viewer.userId);
      await notify({
        userId: otherId,
        kind: 'message',
        actorId: viewer.userId,
        entityId: row.id,
        body: `${name} sent you a message.`,
        preference: 'messages',
      });
      return { id: row.id, created_at: row.created_at, duplicate: false };
    },

    async markConversationRead(viewer: CommunityViewer, conversationId: string): Promise<void> {
      const participant = await pool.query<{ ok: boolean }>(
        'SELECT community_conversation_participant($1, $2) AS ok', [conversationId, viewer.userId],
      );
      if (!participant.rows[0]?.ok) throw notFound('That conversation is not available.');
      await pool.query(
        `INSERT INTO community_conversation_reads (conversation_id, user_id, last_read_at)
         VALUES ($1, $2, now())
         ON CONFLICT (conversation_id, user_id) DO UPDATE SET last_read_at = now()`,
        [conversationId, viewer.userId],
      );
    },

    async muteConversation(viewer: CommunityViewer, conversationId: string, muted: boolean): Promise<void> {
      const participant = await pool.query<{ ok: boolean }>(
        'SELECT community_conversation_participant($1, $2) AS ok', [conversationId, viewer.userId],
      );
      if (!participant.rows[0]?.ok) throw notFound('That conversation is not available.');
      if (muted) {
        await pool.query(
          `INSERT INTO community_conversation_mutes (conversation_id, user_id) VALUES ($1, $2)
           ON CONFLICT DO NOTHING`,
          [conversationId, viewer.userId],
        );
      } else {
        await pool.query(
          'DELETE FROM community_conversation_mutes WHERE conversation_id = $1 AND user_id = $2',
          [conversationId, viewer.userId],
        );
      }
    },

    // MARK: - Reports and notifications

    async report(
      viewer: CommunityViewer,
      input: { targetType: string; targetID: string; reason: string; details?: string | null },
    ): Promise<Row> {
      const targetType = input.targetType.toLowerCase();
      const reason = input.reason.toLowerCase();
      if (!['harassment', 'spam', 'inappropriate', 'impersonation', 'suspicious', 'other'].includes(reason)) {
        throw badRequest('invalid_reason', 'Choose a reason for the report.');
      }
      let targetOk = false;
      if (targetType === 'profile') {
        const result = await pool.query(
          'SELECT 1 FROM community_profiles WHERE user_id = $1 AND user_id <> $2',
          [input.targetID, viewer.userId],
        );
        targetOk = (result.rowCount ?? 0) > 0;
      } else if (targetType === 'post') {
        const result = await pool.query<{ ok: boolean }>(
          'SELECT community_can_read_post($1, $2, $3) AS ok', [viewer.userId, input.targetID, isAdmin(viewer)],
        );
        targetOk = result.rows[0]?.ok ?? false;
      } else if (targetType === 'comment') {
        const result = await pool.query(
          `SELECT 1 FROM community_comments c
            WHERE c.id = $1 AND c.author_id <> $2 AND community_can_read_post($3, c.post_id, $4)`,
          [input.targetID, viewer.userId, viewer.userId, isAdmin(viewer)],
        );
        targetOk = (result.rowCount ?? 0) > 0;
      } else if (targetType === 'message') {
        const result = await pool.query(
          `SELECT 1 FROM community_messages m
            WHERE m.id = $1 AND m.sender_id <> $2 AND community_conversation_participant(m.conversation_id, $3)`,
          [input.targetID, viewer.userId, viewer.userId],
        );
        targetOk = (result.rowCount ?? 0) > 0;
      } else {
        throw badRequest('invalid_target_type', 'Unsupported report type.');
      }
      if (!targetOk) throw notFound('That content is not available to report.');
      const recent = await pool.query<{ count: number }>(
        `SELECT count(*)::int AS count FROM community_reports
          WHERE reporter_id = $1 AND created_at > now() - interval '24 hours'`,
        [viewer.userId],
      );
      if ((recent.rows[0]?.count ?? 0) >= 10) {
        throw forbidden("You have reached today's report limit.");
      }
      const created = await pool.query<Row>(
        `INSERT INTO community_reports (reporter_id, target_type, target_id, reason, details)
         VALUES ($1, $2, $3, $4, $5) RETURNING id, status`,
        [viewer.userId, targetType, input.targetID, reason, clean(input.details) || null],
      );
      return created.rows[0]!;
    },

    async notifications(viewer: CommunityViewer, limitInput?: number, offsetInput?: number): Promise<Row[]> {
      const result = await pool.query<Row>(
        `SELECT n.id, n.kind, n.actor_id, cp.username AS actor_username,
                cp.display_name AS actor_display_name, cp.avatar_url AS actor_avatar_url,
                n.entity_id, n.post_id, n.body, n.read_at, n.created_at
           FROM community_notifications n
           LEFT JOIN community_profiles cp ON cp.user_id = n.actor_id
          WHERE n.user_id = $1
          ORDER BY n.created_at DESC
          LIMIT $2 OFFSET $3`,
        [viewer.userId, clamp(limitInput, 30, 50), offsetOf(offsetInput)],
      );
      return result.rows;
    },

    async markNotificationsRead(viewer: CommunityViewer, ids?: string[] | null): Promise<void> {
      await pool.query(
        `UPDATE community_notifications SET read_at = now()
          WHERE user_id = $1 AND read_at IS NULL
            AND ($2::uuid[] IS NULL OR id = ANY($2::uuid[]))`,
        [viewer.userId, ids && ids.length > 0 ? ids : null],
      );
    },

    // MARK: - Admin

    async adminReports(viewer: CommunityViewer): Promise<Row[]> {
      requireAdmin(viewer);
      const result = await pool.query<Row>(
        `SELECT r.id, r.reporter_id, cp.username AS reporter_username,
                r.target_type, r.target_id, r.reason, r.details, r.status, r.created_at
           FROM community_reports r
           LEFT JOIN community_profiles cp ON cp.user_id = r.reporter_id
          ORDER BY r.status = 'open' DESC, r.created_at DESC
          LIMIT 200`,
      );
      return result.rows;
    },

    async adminSetSuspension(viewer: CommunityViewer, target: string, isSuspended: boolean, reason?: string | null): Promise<void> {
      requireAdmin(viewer);
      await suspendUser(viewer, target, isSuspended, clean(reason) || null);
    },

    async adminResolveReport(viewer: CommunityViewer, id: string, action: string, note?: string | null): Promise<void> {
      requireAdmin(viewer);
      const normalized = action.toLowerCase();
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const found = await client.query<Row>('SELECT * FROM community_reports WHERE id = $1 FOR UPDATE', [id]);
        const report = found.rows[0];
        if (!report) throw notFound('That report was not found.');
        if (normalized === 'remove_content') {
          if (report.target_type === 'post') {
            await client.query("UPDATE community_posts SET moderation_status = 'removed' WHERE id = $1", [report.target_id]);
          } else if (report.target_type === 'comment') {
            await client.query("UPDATE community_comments SET moderation_status = 'removed' WHERE id = $1", [report.target_id]);
          } else {
            throw badRequest('invalid_action', 'Only posts and comments can be removed from a report.');
          }
        } else if (normalized === 'suspend_user') {
          let targetAuthor: string | null = null;
          if (report.target_type === 'profile') {
            targetAuthor = report.target_id;
          } else if (report.target_type === 'post') {
            const row = await client.query<{ author_id: string }>('SELECT author_id FROM community_posts WHERE id = $1', [report.target_id]);
            targetAuthor = row.rows[0]?.author_id ?? null;
          } else if (report.target_type === 'comment') {
            const row = await client.query<{ author_id: string }>('SELECT author_id FROM community_comments WHERE id = $1', [report.target_id]);
            targetAuthor = row.rows[0]?.author_id ?? null;
          } else if (report.target_type === 'message') {
            const row = await client.query<{ sender_id: string }>('SELECT sender_id FROM community_messages WHERE id = $1', [report.target_id]);
            targetAuthor = row.rows[0]?.sender_id ?? null;
          }
          if (!targetAuthor) throw notFound('The reported account could not be determined.');
          await suspendUser(viewer, targetAuthor, true, clean(note) || null, false, client);
        } else if (!['dismiss', 'no_action'].includes(normalized)) {
          throw badRequest('invalid_action', 'Unsupported moderation action.');
        }
        await client.query(
          `UPDATE community_reports SET status = $2, reviewed_at = now(), reviewed_by = $3, resolution_note = $4
            WHERE id = $1`,
          [
            id,
            ['dismiss', 'no_action'].includes(normalized) ? 'dismissed' : 'resolved',
            viewer.userId,
            clean(note) || null,
          ],
        );
        await audit(viewer.userId, normalized, report.target_type, report.target_id, clean(note) || null, client);
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
    },

    async adminGyms(viewer: CommunityViewer): Promise<Row[]> {
      requireAdmin(viewer);
      const result = await pool.query<Row>(
        `SELECT id, name, city, area, address, verification_status, submitted_by, created_at
           FROM gyms
          ORDER BY verification_status = 'pending' DESC, created_at DESC
          LIMIT 200`,
      );
      return result.rows;
    },

    async adminReviewGym(viewer: CommunityViewer, gymId: string, approve: boolean, note?: string | null): Promise<void> {
      requireAdmin(viewer);
      const updated = await pool.query(
        `UPDATE gyms SET verification_status = $2, verified_at = now(), verified_by = $3
          WHERE id = $1`,
        [gymId, approve ? 'verified' : 'rejected', viewer.userId],
      );
      if (updated.rowCount === 0) throw notFound('That gym could not be found.');
      await audit(viewer.userId, approve ? 'verify_gym' : 'reject_gym', 'gym', gymId, clean(note) || null);
    },

    async adminAudit(viewer: CommunityViewer): Promise<Row[]> {
      requireAdmin(viewer);
      const result = await pool.query<Row>(
        `SELECT id, admin_id, action, target_type, target_id, note, created_at
           FROM community_moderation_actions
          ORDER BY created_at DESC
          LIMIT 200`,
      );
      return result.rows;
    },

    /** The socket layer calls this to confirm a session can open a stream. */
    async assertViewer(viewer: CommunityViewer): Promise<void> {
      const exists = await pool.query('SELECT 1 FROM users WHERE id = $1', [viewer.userId]);
      if (exists.rowCount === 0) throw notFound('That account could not be found.');
    },

    logError(error: unknown, context: string): void {
      logger.error({ err: message(error), context }, 'community operation failed');
    },
  };
}

export type CommunityService = ReturnType<typeof createCommunityService>;
