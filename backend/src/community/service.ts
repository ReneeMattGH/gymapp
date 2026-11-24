import { createHash, randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import type { Logger } from 'pino';
import type { Pool, PoolClient } from 'pg';
import type { Config } from '../config.js';
import { badRequest, forbidden, notFound, serviceUnavailable } from '../errors.js';
import { normalizeCountry } from './countries.js';
import { createGymProvider, providerStatus, type GymProvider, type ProviderGym } from './gymProvider.js';

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

/** Mirrors the SQL gym_normalize() helper so query and column agree. */
function normalizeGymName(value: string | null | undefined): string {
  return (value ?? '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function searchTokens(query: string): string[] {
  return normalizeGymName(query)
    .split(' ')
    .filter((token) => token.length > 0)
    .slice(0, 6);
}

const RADIUS_KM = new Set([2, 5, 10, 25, 50]);

function radiusKm(value: number | undefined): number {
  const rounded = Math.round(value ?? 5);
  return RADIUS_KM.has(rounded) ? rounded : Math.min(Math.max(rounded, 1), 100);
}

function coordinate(value: number | undefined, limit: number): number {
  if (value === undefined || !Number.isFinite(value) || Math.abs(value) > limit) {
    throw badRequest('invalid_location', 'The search location is not valid.');
  }
  return value;
}

function message(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export function createCommunityService(options: {
  pool: Pool;
  config: Config;
  realtime: CommunityRealtime;
  logger: Logger;
  /** Injected in tests; otherwise created from configuration. */
  gymProvider?: GymProvider | null;
}) {
  const { pool, config, realtime, logger } = options;
  const gymProvider = options.gymProvider === undefined ? createGymProvider(config) : options.gymProvider;
  const gymProviderInfo = providerStatus(config, gymProvider);

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

  interface DiscoverOptions {
    scope: string;
    query?: string;
    interest?: string;
    country?: string;
    city?: string;
    gymId?: string | null;
    limit?: number;
    offset?: number;
  }

  function normalizedCountryFilter(value: string | undefined): string {
    const raw = clean(value);
    if (raw === '') return '';
    return normalizeCountry(raw).code ?? raw;
  }

  function validGymId(value: string | null | undefined): string | null {
    const raw = clean(value);
    if (raw === '') return null;
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(raw)) {
      throw badRequest('invalid_gym', 'That gym was not recognized.');
    }
    return raw;
  }

  async function discover(viewer: CommunityViewer, options: DiscoverOptions): Promise<Row[]> {
    const limit = clamp(options.limit, 20, 50);
    const offset = offsetOf(options.offset);
    const scope = (clean(options.scope) || 'gym').toLowerCase();
    const result = await pool.query<Row>(
      `WITH me AS (
         SELECT coalesce((SELECT city FROM community_preferences WHERE user_id = $1), '') AS my_city,
                coalesce((SELECT country_code FROM community_preferences WHERE user_id = $1), '') AS my_country,
                coalesce((SELECT g.state
                            FROM gym_memberships gm
                            JOIN gyms g ON g.id = gm.gym_id
                           WHERE gm.user_id = $1 AND coalesce(g.state, '') <> ''
                           ORDER BY gm.is_primary DESC, gm.created_at
                           LIMIT 1), '') AS my_state
       ),
       eligible AS (
         SELECT cp.user_id, cp.username, cp.display_name, cp.avatar_url, cp.bio,
                cp.interests, cp.workout_categories,
                CASE WHEN pref.show_gym AND coalesce(mem.visibility, 'members') <> 'private'
                     THEN g.name END AS gym_name,
                CASE WHEN pref.show_area THEN pref.area END AS area,
                CASE WHEN pref.show_city THEN pref.city END AS city,
                CASE WHEN pref.show_gym AND coalesce(mem.visibility, 'members') <> 'private'
                     THEN g.state END AS region,
                CASE WHEN pref.show_country THEN coalesce(pref.country, g.country) END AS country,
                CASE WHEN pref.show_country THEN coalesce(pref.country_code, g.country_code) END AS country_code,
                (pref.show_gym AND EXISTS (
                   SELECT 1 FROM gym_memberships mine
                   JOIN gym_memberships theirs ON theirs.gym_id = mine.gym_id
                   WHERE mine.user_id = $1 AND theirs.user_id = cp.user_id
                     AND theirs.visibility <> 'private'
                 )) AS shares_gym,
                community_area_compatible($1, cp.user_id) AS shares_area,
                (coalesce(pref.city, '') <> ''
                  AND lower(pref.city) = lower((SELECT my_city FROM me))) AS shares_city,
                (pref.show_gym AND coalesce(mem.visibility, 'members') <> 'private'
                  AND coalesce(g.state, '') <> ''
                  AND (SELECT my_state FROM me) <> ''
                  AND lower(g.state) = lower((SELECT my_state FROM me))) AS shares_region,
                (coalesce(pref.country_code, '') <> ''
                  AND upper(pref.country_code) = upper((SELECT my_country FROM me))) AS shares_country,
                pref.show_gym AS shows_gym
         FROM community_profiles cp
         JOIN community_preferences pref ON pref.user_id = cp.user_id
         LEFT JOIN LATERAL (
           SELECT gm.gym_id, gm.visibility
             FROM gym_memberships gm
            WHERE gm.user_id = cp.user_id
            ORDER BY gm.is_primary DESC, gm.created_at
            LIMIT 1
         ) mem ON true
         LEFT JOIN gyms g ON g.id = mem.gym_id
         WHERE cp.user_id <> $1
           AND pref.discoverable
           AND NOT community_is_suspended(cp.user_id)
           AND NOT community_is_suspended($1)
           AND community_not_blocked($1, cp.user_id)
           AND community_age_compatible($1, cp.user_id)
           AND (
             ($2 = 'gym' AND pref.show_gym AND EXISTS (
                SELECT 1 FROM gym_memberships mine
                JOIN gym_memberships theirs ON theirs.gym_id = mine.gym_id
                WHERE mine.user_id = $1 AND theirs.user_id = cp.user_id
                  AND theirs.visibility <> 'private'
              ))
             OR ($2 = 'area' AND pref.show_area AND pref.nearby_discovery
                 AND community_area_compatible($1, cp.user_id))
             OR ($2 = 'city' AND pref.show_city AND coalesce(pref.city, '') <> ''
                 AND lower(pref.city) = lower((SELECT my_city FROM me)))
             OR ($2 = 'region' AND pref.show_gym
                 AND coalesce(mem.visibility, 'members') <> 'private'
                 AND coalesce(g.state, '') <> ''
                 AND (SELECT my_state FROM me) <> ''
                 AND lower(g.state) = lower((SELECT my_state FROM me)))
             OR ($2 = 'country' AND pref.show_country AND coalesce(pref.country_code, '') <> ''
                 AND upper(pref.country_code) = upper((SELECT my_country FROM me)))
             OR ($2 IN ('global', 'all') AND pref.global_discovery)
           )
       )
       SELECT e.user_id, e.username, e.display_name, e.avatar_url, e.bio,
              e.interests, e.workout_categories, e.gym_name, e.area, e.city,
              e.region, e.country, e.country_code,
              community_connection_status($1, e.user_id) AS connection_status
       FROM eligible e
       WHERE (
           $3::text[] = '{}' OR NOT EXISTS (
             SELECT 1 FROM unnest($3::text[]) AS token
             WHERE NOT (
               lower(e.username) LIKE '%' || token || '%'
               OR lower(e.display_name) LIKE '%' || token || '%'
               OR lower(coalesce(e.gym_name, '')) LIKE '%' || token || '%'
               OR lower(coalesce(e.area, '')) LIKE '%' || token || '%'
               OR lower(coalesce(e.city, '')) LIKE '%' || token || '%'
               OR lower(coalesce(e.region, '')) LIKE '%' || token || '%'
               OR lower(coalesce(e.country, '')) LIKE '%' || token || '%'
             )
           )
         )
         AND (
           trim($4) = ''
           OR EXISTS (SELECT 1 FROM unnest(e.interests) i WHERE lower(i) = lower(trim($4)))
           OR EXISTS (SELECT 1 FROM unnest(e.workout_categories) c WHERE lower(c) = lower(trim($4)))
         )
         AND (
           trim($5) = '' OR
           (length(trim($5)) = 2 AND upper(coalesce(e.country_code, '')) = upper(trim($5)))
           OR (length(trim($5)) <> 2 AND lower(coalesce(e.country, '')) = lower(trim($5)))
         )
         AND (trim($6) = '' OR lower(coalesce(e.city, '')) = lower(trim($6)))
         AND (
           $7::uuid IS NULL OR (
             e.shows_gym AND EXISTS (
               SELECT 1 FROM gym_memberships gm
               WHERE gm.user_id = e.user_id AND gm.gym_id = $7::uuid
             )
           )
         )
       ORDER BY e.shares_gym DESC, e.shares_area DESC, e.shares_city DESC,
                e.shares_region DESC, e.shares_country DESC, lower(e.display_name)
       LIMIT $8 OFFSET $9`,
      [
        viewer.userId,
        scope,
        searchTokens(options.query ?? ''),
        clean(options.interest),
        normalizedCountryFilter(options.country),
        clean(options.city),
        validGymId(options.gymId),
        limit,
        offset,
      ],
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

  // MARK: - Gym directory helpers

  const gymColumns = `
    g.id, g.name, g.address, g.city, g.state, g.country, g.country_code, g.area,
    g.postal_code, g.latitude, g.longitude, g.website, g.phone, g.source,
    g.provider_name, g.verification_status, g.last_verified_at,
    (SELECT count(*)::int FROM gym_memberships gm WHERE gm.gym_id = g.id) AS member_count`;

  async function providerCacheGet(key: string): Promise<ProviderGym[] | null> {
    const cached = await pool.query<{ payload: ProviderGym[] }>(
      'SELECT payload FROM gym_provider_cache WHERE cache_key = $1 AND expires_at > now()',
      [key],
    );
    return cached.rows[0]?.payload ?? null;
  }

  async function providerCachePut(provider: string, key: string, payload: ProviderGym[]): Promise<void> {
    await pool.query(
      `INSERT INTO gym_provider_cache (cache_key, provider, payload, expires_at)
       VALUES ($1, $2, $3, now() + make_interval(hours => $4))
       ON CONFLICT (cache_key) DO UPDATE
         SET payload = excluded.payload, expires_at = excluded.expires_at, created_at = now()`,
      [key, provider, JSON.stringify(payload), config.gymProviderCacheTtlHours],
    );
  }

  /**
   * Stores provider results in the directory. Rows are matched first by the
   * provider's own identifier, then by a normalized name plus either a nearby
   * coordinate (<250m) or the same city and country, so the same gym seen from
   * two sources does not become two records.
   */
  async function ingestProviderGyms(rows: ProviderGym[]): Promise<void> {
    for (const row of rows.slice(0, 20)) {
      if (!Number.isFinite(row.latitude) || !Number.isFinite(row.longitude)) continue;
      const name = row.name.trim().slice(0, 120);
      const normalized = normalizeGymName(name);
      if (normalized.length < 2) continue;
      const country = normalizeCountry(row.countryCode ?? row.country);
      const city = row.city?.trim().slice(0, 80) || null;
      const area = row.neighborhood?.trim().slice(0, 80) || null;
      const state = row.region?.trim().slice(0, 80) || null;
      const countryName = country.name ?? row.country?.trim().slice(0, 80) ?? null;
      const countryCode = country.code;
      const address = row.address?.trim().slice(0, 240) || null;
      const postal = row.postalCode?.trim().slice(0, 24) || null;
      const website = row.website?.trim().slice(0, 300) || null;
      const phone = row.phone?.trim().slice(0, 40) || null;
      const providerId = row.providerId.slice(0, 200);
      const providerName = row.providerName;

      const byProvider = await pool.query<{ id: string }>(
        'SELECT id FROM gyms WHERE provider_name = $1 AND provider_id = $2',
        [providerName, providerId],
      );
      if (byProvider.rows[0]) {
        await pool.query(
          `UPDATE gyms SET
             name = $2, normalized_name = $3,
             address = coalesce($4, address), city = coalesce($5, city),
             area = coalesce($6, area), state = coalesce($7, state),
             country = coalesce($8, country), country_code = coalesce($9, country_code),
             postal_code = coalesce($10, postal_code),
             latitude = $11, longitude = $12,
             website = coalesce($13, website), phone = coalesce($14, phone),
             last_verified_at = now(), updated_at = now()
           WHERE id = $1`,
          [byProvider.rows[0].id, name, normalized, address, city, area, state,
           countryName, countryCode, postal, row.latitude, row.longitude, website, phone],
        );
        continue;
      }

      const duplicate = await pool.query<{ id: string }>(
        `SELECT id FROM gyms
          WHERE normalized_name = $1
            AND (
              (latitude IS NOT NULL AND longitude IS NOT NULL
               AND (6371.0088 * 2 * asin(sqrt(
                     power(sin(radians(latitude - $2) / 2), 2) +
                     cos(radians($2)) * cos(radians(latitude)) *
                     power(sin(radians(longitude - $3) / 2), 2)
                   ))) < 0.25)
              OR (
                lower(coalesce(city, '')) = lower(coalesce($4, ''))
                AND lower(coalesce(country_code, country, '')) = lower(coalesce($5, $6, ''))
              )
            )
          LIMIT 1`,
        [normalized, row.latitude, row.longitude, city, countryCode, countryName],
      );
      if (duplicate.rows[0]) {
        await pool.query(
          `UPDATE gyms SET
             latitude = coalesce(latitude, $2), longitude = coalesce(longitude, $3),
             last_verified_at = now(), updated_at = now()
           WHERE id = $1`,
          [duplicate.rows[0].id, row.latitude, row.longitude],
        );
        continue;
      }

      await pool.query(
        `INSERT INTO gyms (
           name, normalized_name, address, city, area, state, country, country_code,
           postal_code, latitude, longitude, website, phone, provider_id, provider_name,
           source, verification_status, last_verified_at, updated_at
         ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,'imported',now(),now())
         ON CONFLICT DO NOTHING`,
        [name, normalized, address, city, area, state, countryName, countryCode,
         postal, row.latitude, row.longitude, website, phone, providerId, providerName, providerName],
      );
    }
  }

  async function providerTextSearch(provider: GymProvider, query: string, limit: number): Promise<boolean> {
    const key = `gym:${provider.name}:text:${createHash('sha256')
      .update(normalizeGymName(query))
      .digest('hex')
      .slice(0, 32)}:${limit}`;
    try {
      const cached = await providerCacheGet(key);
      if (cached) {
        await ingestProviderGyms(cached);
        return true;
      }
      const rows = await provider.searchText(query, limit);
      await providerCachePut(provider.name, key, rows);
      await ingestProviderGyms(rows);
      return true;
    } catch (error) {
      logger.error(
        { err: message(error), context: `gym provider ${provider.name} text search` },
        'community operation failed',
      );
      return false;
    }
  }

  async function providerNearbySearch(
    provider: GymProvider,
    latitude: number,
    longitude: number,
    radiusMeters: number,
    limit: number,
  ): Promise<boolean> {
    const key = `gym:${provider.name}:nearby:${latitude.toFixed(3)},${longitude.toFixed(3)}:${radiusMeters}:${limit}`;
    try {
      const cached = await providerCacheGet(key);
      if (cached) {
        await ingestProviderGyms(cached);
        return true;
      }
      const rows = await provider.searchNearby(latitude, longitude, radiusMeters, limit);
      await providerCachePut(provider.name, key, rows);
      await ingestProviderGyms(rows);
      return true;
    } catch (error) {
      logger.error(
        { err: message(error), context: `gym provider ${provider.name} nearby search` },
        'community operation failed',
      );
      return false;
    }
  }

  async function queryNearbyGyms(
    viewer: CommunityViewer,
    latitude: number,
    longitude: number,
    radius: number,
    limit: number,
  ): Promise<Row[]> {
    const latDelta = radius / 111.32;
    const lngDelta = radius / (111.32 * Math.max(Math.cos((latitude * Math.PI) / 180), 0.01));
    const result = await pool.query<Row>(
      `WITH candidates AS (
         SELECT ${gymColumns},
                6371.0088 * 2 * asin(sqrt(
                  power(sin(radians(g.latitude - $1) / 2), 2) +
                  cos(radians($1)) * cos(radians(g.latitude)) *
                  power(sin(radians(g.longitude - $2) / 2), 2)
                )) AS distance_km
           FROM gyms g
          WHERE g.latitude IS NOT NULL AND g.longitude IS NOT NULL
            AND g.latitude BETWEEN $3 AND $4
            AND g.longitude BETWEEN $5 AND $6
            AND (g.verification_status IN ('verified', 'imported') OR g.submitted_by = $7 OR $8)
       )
       SELECT * FROM candidates
        WHERE distance_km <= $9
        ORDER BY distance_km, name
        LIMIT $10`,
      [
        latitude,
        longitude,
        latitude - latDelta,
        latitude + latDelta,
        longitude - lngDelta,
        longitude + lngDelta,
        viewer.userId,
        isAdmin(viewer),
        radius,
        limit,
      ],
    );
    return result.rows;
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
          `SELECT gm.id AS membership_id, gm.membership_type, gm.is_primary, gm.visibility,
                  g.id AS gym_id, g.name AS gym_name, g.address, g.city, g.area,
                  g.state, g.country, g.country_code, g.postal_code,
                  g.latitude, g.longitude, g.verification_status
             FROM gym_memberships gm
             JOIN gyms g ON g.id = gm.gym_id
            WHERE gm.user_id = $1
            ORDER BY gm.is_primary DESC, gm.created_at`,
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
                 AND EXISTS (
                   SELECT 1 FROM gym_memberships mine
                   JOIN gym_memberships theirs ON theirs.gym_id = mine.gym_id
                   WHERE mine.user_id = $1 AND theirs.user_id = cp.user_id
                     AND theirs.visibility <> 'private'
                 )) AS gym_count,
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

      const suggestions = await discover(viewer, { scope: 'gym', limit: 5 });
      const nearby = await discover(viewer, { scope: 'area', limit: 5 });
      const feedRows = await feed(viewer, 'all', 5, 0);
      const connections = (await connectionList(viewer)).filter((row) => row.status === 'accepted').slice(0, 5);
      const counts = countsResult.rows[0];

      return {
        profile: profileResult.rows[0] ?? null,
        preferences: preferencesResult.rows[0] ?? null,
        membership: membershipResult.rows[0] ?? null,
        memberships: membershipResult.rows,
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

    async searchGyms(
      viewer: CommunityViewer,
      input: {
        query?: string;
        country?: string;
        city?: string;
        area?: string;
        postalCode?: string;
        limit?: number;
        offset?: number;
      } = {},
    ): Promise<Row[]> {
      const limit = clamp(input.limit, 20, 50);
      const offset = offsetOf(input.offset);
      const query = clean(input.query);
      const country = normalizedCountryFilter(input.country);
      const city = clean(input.city);
      const area = clean(input.area);
      const postal = clean(input.postalCode);

      // Only an actual search reaches an external directory, never a keystroke
      // with one character, and repeats are served from the cache table.
      let providerFailed = false;
      if (query.length >= 2 && gymProvider) {
        providerFailed = !(await providerTextSearch(gymProvider, query, Math.min(limit, 20)));
      }

      const result = await pool.query<Row>(
        `SELECT ${gymColumns}
           FROM gyms g
          WHERE (g.verification_status IN ('verified', 'imported') OR g.submitted_by = $1 OR $2)
            AND (
              $3::text[] = '{}' OR NOT EXISTS (
                SELECT 1 FROM unnest($3::text[]) AS token
                WHERE gym_normalize(concat_ws(' ', g.name, g.city, g.area, g.state,
                                              g.country, g.postal_code))
                      NOT LIKE '%' || token || '%'
              )
            )
            AND ($4 = '' OR lower(coalesce(g.city, '')) = lower($4))
            AND ($5 = '' OR gym_normalize(coalesce(g.area, '')) LIKE '%' || gym_normalize($5) || '%')
            AND ($6 = '' OR lower(coalesce(g.postal_code, '')) LIKE lower($6) || '%')
            AND (
              $7 = '' OR
              (length($7) = 2 AND upper(coalesce(g.country_code, '')) = upper($7)) OR
              (length($7) <> 2 AND lower(coalesce(g.country, '')) = lower($7))
            )
          ORDER BY (g.verification_status = 'verified') DESC,
                   (g.source = 'forma') DESC,
                   (g.verification_status = 'imported') DESC,
                   g.name
          LIMIT $8 OFFSET $9`,
        [viewer.userId, isAdmin(viewer), searchTokens(query), city, area, postal, country, limit, offset],
      );
      if (providerFailed && result.rows.length === 0) {
        throw serviceUnavailable(
          'gym_directory_unavailable',
          'The gym directory did not respond. Try again, or add your gym manually.',
        );
      }
      return result.rows;
    },

    async nearbyGyms(
      viewer: CommunityViewer,
      latitudeInput: number | undefined,
      longitudeInput: number | undefined,
      radiusInput?: number,
      limitInput?: number,
    ): Promise<Row[]> {
      const latitude = coordinate(latitudeInput, 90);
      const longitude = coordinate(longitudeInput, 180);
      const radius = radiusKm(radiusInput);
      const limit = clamp(limitInput, 20, 50);

      let rows = await queryNearbyGyms(viewer, latitude, longitude, radius, limit);
      if (gymProvider && rows.length < Math.min(limit, 10)) {
        const ok = await providerNearbySearch(
          gymProvider,
          latitude,
          longitude,
          radius * 1000,
          Math.min(limit, 20),
        );
        rows = await queryNearbyGyms(viewer, latitude, longitude, radius, limit);
        if (!ok && rows.length === 0) {
          throw serviceUnavailable(
            'gym_directory_unavailable',
            'The gym directory did not respond. Try again, or add your gym manually.',
          );
        }
      }
      return rows;
    },

    async gymDetails(viewer: CommunityViewer, gymId: string): Promise<Row> {
      const id = validGymId(gymId);
      if (!id) throw badRequest('invalid_gym', 'That gym was not recognized.');
      const result = await pool.query<Row>(
        `SELECT ${gymColumns}
           FROM gyms g
          WHERE g.id = $1
            AND (g.verification_status IN ('verified', 'imported') OR g.submitted_by = $2 OR $3)`,
        [id, viewer.userId, isAdmin(viewer)],
      );
      if (!result.rows[0]) throw notFound('That gym could not be found.');
      return result.rows[0];
    },

    gymProviderStatus(): Row {
      return { ...gymProviderInfo };
    },

    async requestGym(
      viewer: CommunityViewer,
      input: {
        name: string;
        city: string;
        area?: string | null;
        address?: string | null;
        state?: string | null;
        country?: string | null;
        postalCode?: string | null;
      },
    ): Promise<Row> {
      await requireActive(viewer.userId, 'submit gyms');
      const name = clean(input.name);
      const city = clean(input.city);
      if (name.length < 2 || city.length < 2) throw badRequest('invalid_gym', 'Enter the gym name and city.');
      const country = normalizeCountry(input.country);
      const normalized = normalizeGymName(name);
      const existing = await pool.query<Row>(
        `SELECT id, verification_status FROM gyms
          WHERE normalized_name = $1
            AND lower(coalesce(city, '')) = lower($2)
            AND lower(coalesce(country_code, country, '')) = lower(coalesce($3, $4, ''))
            AND lower(coalesce(area, '')) = lower($5)
          LIMIT 1`,
        [normalized, city, country.code, country.name, clean(input.area)],
      );
      if (existing.rows[0]) {
        return { id: existing.rows[0].id, status: existing.rows[0].verification_status, created: false };
      }
      const created = await pool.query<Row>(
        `INSERT INTO gyms (name, normalized_name, city, area, address, state, country, country_code,
                           postal_code, submitted_by, source, verification_status)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'user', 'pending')
         ON CONFLICT DO NOTHING
         RETURNING id, verification_status`,
        [
          name,
          normalized,
          city,
          clean(input.area) || null,
          clean(input.address) || null,
          clean(input.state) || null,
          country.name,
          country.code,
          clean(input.postalCode) || null,
          viewer.userId,
        ],
      );
      if (created.rows[0]) {
        return { id: created.rows[0].id, status: created.rows[0].verification_status, created: true };
      }
      const again = await pool.query<Row>(
        `SELECT id, verification_status FROM gyms
          WHERE normalized_name = $1 AND lower(coalesce(city, '')) = lower($2) LIMIT 1`,
        [normalized, city],
      );
      if (!again.rows[0]) throw badRequest('invalid_gym', 'That gym could not be added. Check the details and try again.');
      return { id: again.rows[0].id, status: again.rows[0].verification_status, created: false };
    },

    async joinGym(
      viewer: CommunityViewer,
      gymId: string,
      optionsInput: { isPrimary?: boolean; membershipType?: string; visibility?: string } = {},
    ): Promise<void> {
      await requireActive(viewer.userId, 'join a gym community');
      const chosen = await pool.query<Row>('SELECT * FROM gyms WHERE id = $1', [gymId]);
      const gym = chosen.rows[0];
      if (!gym) throw notFound('That gym could not be found.');
      if (!['verified', 'imported'].includes(gym.verification_status) && gym.submitted_by !== viewer.userId) {
        throw forbidden('This gym is still awaiting review.');
      }
      const isPrimary = optionsInput.isPrimary ?? true;
      const membershipType = ['member', 'day_pass', 'online', 'coach'].includes(optionsInput.membershipType ?? '')
        ? optionsInput.membershipType!
        : 'member';
      const visibility = ['private', 'members', 'public'].includes(optionsInput.visibility ?? '')
        ? optionsInput.visibility!
        : 'members';
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        if (isPrimary) {
          await client.query(
            'UPDATE gym_memberships SET is_primary = false, updated_at = now() WHERE user_id = $1 AND is_primary',
            [viewer.userId],
          );
        }
        await client.query(
          `INSERT INTO gym_memberships (user_id, gym_id, is_primary, membership_type, visibility)
           VALUES ($1, $2, $3, $4, $5)
           ON CONFLICT (user_id, gym_id) DO UPDATE SET
             is_primary = gym_memberships.is_primary OR excluded.is_primary,
             membership_type = excluded.membership_type,
             visibility = excluded.visibility,
             updated_at = now()`,
          [viewer.userId, gymId, isPrimary, membershipType, visibility],
        );
        if (isPrimary) {
          await client.query(
            `INSERT INTO community_preferences (user_id, city, area, country, country_code)
             VALUES ($1, $2, $3, $4, $5)
             ON CONFLICT (user_id) DO UPDATE SET
               city = coalesce(excluded.city, community_preferences.city),
               area = coalesce(excluded.area, community_preferences.area),
               country = coalesce(excluded.country, community_preferences.country),
               country_code = coalesce(excluded.country_code, community_preferences.country_code),
               updated_at = now()`,
            [viewer.userId, gym.city, gym.area, gym.country, gym.country_code],
          );
        }
        await client.query('COMMIT');
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally {
        client.release();
      }
    },

    async removeGymMembership(viewer: CommunityViewer, gymId: string): Promise<void> {
      const client = await pool.connect();
      try {
        await client.query('BEGIN');
        const removed = await client.query<{ is_primary: boolean }>(
          `DELETE FROM gym_memberships WHERE user_id = $1 AND gym_id = $2 RETURNING is_primary`,
          [viewer.userId, gymId],
        );
        if (!removed.rows[0]) throw notFound('That gym is not in your memberships.');
        if (removed.rows[0].is_primary) {
          const next = await client.query<Row>(
            `SELECT gm.gym_id, g.city, g.area, g.country, g.country_code
               FROM gym_memberships gm JOIN gyms g ON g.id = gm.gym_id
              WHERE gm.user_id = $1
              ORDER BY gm.created_at, gm.id
              LIMIT 1`,
            [viewer.userId],
          );
          if (next.rows[0]) {
            await client.query(
              'UPDATE gym_memberships SET is_primary = true, updated_at = now() WHERE user_id = $1 AND gym_id = $2',
              [viewer.userId, next.rows[0].gym_id],
            );
            await client.query(
              `UPDATE community_preferences SET
                 city = coalesce($2, city), area = coalesce($3, area),
                 country = coalesce($4, country), country_code = coalesce($5, country_code),
                 updated_at = now()
               WHERE user_id = $1`,
              [viewer.userId, next.rows[0].city, next.rows[0].area, next.rows[0].country, next.rows[0].country_code],
            );
          }
        }
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
        showCity: boolean;
        showCountry: boolean;
        nearbyDiscovery: boolean;
        globalDiscovery: boolean;
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
           (user_id, discoverable, show_gym, show_area, show_city, show_country,
            nearby_discovery, global_discovery, allow_connection_requests, allow_messages,
            notify_connections, notify_messages, notify_comments, notify_likes)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
         ON CONFLICT (user_id) DO UPDATE SET
           discoverable = excluded.discoverable,
           show_gym = excluded.show_gym,
           show_area = excluded.show_area,
           show_city = excluded.show_city,
           show_country = excluded.show_country,
           nearby_discovery = excluded.nearby_discovery,
           global_discovery = excluded.global_discovery,
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
          input.showCity,
          input.showCountry,
          input.nearbyDiscovery,
          input.globalDiscovery,
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
                CASE WHEN pref.show_gym AND coalesce(g.visibility, 'members') <> 'private'
                     THEN g.name END AS gym_name,
                CASE WHEN pref.show_city THEN pref.city END AS city,
                CASE WHEN pref.show_area THEN pref.area END AS area,
                CASE WHEN pref.show_country THEN coalesce(pref.country, g.country) END AS country,
                CASE WHEN pref.show_country THEN coalesce(pref.country_code, g.country_code) END AS country_code,
                community_connection_status($1, cp.user_id) AS connection_status,
                EXISTS (
                  SELECT 1 FROM gym_memberships mine
                  JOIN gym_memberships theirs ON theirs.gym_id = mine.gym_id
                  WHERE mine.user_id = $1 AND theirs.user_id = cp.user_id
                    AND theirs.visibility <> 'private'
                ) AS shared_gym,
                community_area_compatible($1, cp.user_id) AS shared_area
           FROM community_profiles cp
           JOIN community_preferences pref ON pref.user_id = cp.user_id
           LEFT JOIN LATERAL (
             SELECT g.name, g.country, g.country_code, gm.visibility
               FROM gym_memberships gm
               JOIN gyms g ON g.id = gm.gym_id
              WHERE gm.user_id = cp.user_id
              ORDER BY gm.is_primary DESC, gm.created_at
              LIMIT 1
           ) g ON true
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
      // Accepted connections can see this post, so their feeds refetch too.
      const audience = await pool.query<{ user_id: string }>(
        `SELECT CASE WHEN requester_id = $1 THEN recipient_id ELSE requester_id END AS user_id
           FROM community_connections
          WHERE status = 'accepted' AND (requester_id = $1 OR recipient_id = $1)
          LIMIT 500`,
        [viewer.userId],
      );
      for (const row of audience.rows) {
        realtime.emitToUser(row.user_id, 'activity', { kind: 'post_created', entity_id: input.id });
      }
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
      if (!['harassment', 'spam', 'inappropriate', 'impersonation', 'suspicious', 'incorrect_details', 'other'].includes(reason)) {
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
      } else if (targetType === 'gym') {
        const result = await pool.query(
          `SELECT 1 FROM gyms
            WHERE id = $1
              AND (verification_status IN ('verified', 'imported') OR submitted_by = $2)`,
          [input.targetID, viewer.userId],
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
