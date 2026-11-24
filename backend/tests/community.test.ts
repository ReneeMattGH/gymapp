import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, type Server as HttpServer } from 'node:http';
import request from 'supertest';
import type { Express } from 'express';
import { Server } from 'socket.io';
import { loadConfig, type Config } from '../src/config.js';
import { createLogger } from '../src/logger.js';
import { createPool, type Pool } from '../src/db/pool.js';
import { runMigrations, verifySchema } from '../src/db/migrate.js';
import { createMailer } from '../src/auth/mailer.js';
import { createAuthService } from '../src/auth/service.js';
import {
  createCommunityService,
  noRealtime,
  type CommunityRealtime,
} from '../src/community/service.js';
import { attachCommunityRealtime } from '../src/community/realtime.js';
import type { GymProvider, ProviderGym } from '../src/community/gymProvider.js';
import { createApp } from '../src/http/app.js';

interface Account {
  token: string;
  userId: string;
  email: string;
}

class RecordingRealtime implements CommunityRealtime {
  readonly events: Array<{ userId: string; event: string; payload: unknown }> = [];

  emitToUser(userId: string, event: string, payload: unknown): void {
    this.events.push({ userId, event, payload });
  }

  eventsFor(userId: string, event: string): unknown[] {
    return this.events.filter((item) => item.userId === userId && item.event === event).map((item) => item.payload);
  }
}

class FakeProvider implements GymProvider {
  readonly name = 'osm' as const;
  textCalls = 0;
  nearbyCalls = 0;

  constructor(
    private readonly textResults: ProviderGym[],
    private readonly nearbyResults: ProviderGym[] = [],
    private readonly fail: 'none' | 'text' | 'nearby' | 'all' = 'none',
  ) {}

  async searchText(): Promise<ProviderGym[]> {
    this.textCalls += 1;
    if (this.fail === 'text' || this.fail === 'all') throw new Error('overpass unavailable');
    return this.textResults;
  }

  async searchNearby(): Promise<ProviderGym[]> {
    this.nearbyCalls += 1;
    if (this.fail === 'nearby' || this.fail === 'all') throw new Error('overpass unavailable');
    return this.nearbyResults;
  }
}

const ADMIN_EMAIL = 'admin@example.com';

describe('community API', () => {
  let pool: Pool;
  let app: Express;
  let config: Config;
  let realtime: RecordingRealtime;
  let counter = 0;

  before(async () => {
    pool = createPool(process.env.TEST_DATABASE_URL ?? 'postgres://localhost:5432/forma_test');
    await runMigrations(pool);
  });

  it('confirms the migrated database matches this build', async () => {
    assert.deepEqual(await verifySchema(pool), []);
  });

  beforeEach(async () => {
    await pool.query(
      'TRUNCATE users, gyms, gym_provider_cache, community_moderation_actions, community_reports, community_notifications CASCADE',
    );
    config = loadConfig({
      NODE_ENV: 'test',
      DATABASE_URL: process.env.TEST_DATABASE_URL ?? 'postgres://localhost:5432/forma_test',
      LOG_LEVEL: 'silent',
      COMMUNITY_ADMIN_EMAILS: ADMIN_EMAIL,
      UPLOAD_DIR: '/tmp/forma-test-uploads',
    });
    realtime = new RecordingRealtime();
    app = buildApp(realtime);
    counter = 0;
  });

  after(async () => {
    await pool.end();
  });

  function buildApp(broadcast: CommunityRealtime, provider: GymProvider | null = null): Express {
    const logger = createLogger('silent');
    const auth = createAuthService({ pool, config, mailer: createMailer({ from: 'Forma <no-reply@example.com>' }), logger });
    const community = createCommunityService({ pool, config, logger, realtime: broadcast, gymProvider: provider });
    return createApp({ config, pool, logger, auth, community });
  }

  function email(prefix: string): string {
    counter += 1;
    return `${prefix}-${counter}-${Date.now()}@example.com`;
  }

  async function register(prefix = 'member', address?: string): Promise<Account> {
    const addressValue = address ?? email(prefix);
    const response = await request(app)
      .post('/api/v1/auth/register')
      .send({ email: addressValue, password: 'correct horse battery' });
    assert.equal(response.status, 201, response.text);
    return { token: response.body.tokens.accessToken, userId: response.body.user.id, email: addressValue };
  }

  function auth(account: Account) {
    return { Authorization: `Bearer ${account.token}` };
  }

  async function saveProfile(account: Account, name: string, age = 30): Promise<void> {
    const response = await request(app)
      .put('/api/v1/community/profile')
      .set(auth(account))
      .send({
        username: name,
        displayName: `${name} Display`,
        bio: `Hi, I am ${name}.`,
        interests: ['strength'],
        categories: ['strength'],
        age,
      });
    assert.equal(response.status, 200, response.text);
  }

  async function setArea(account: Account, area = 'Adyar', city = 'Chennai'): Promise<void> {
    const response = await request(app)
      .put('/api/v1/community/area')
      .set(auth(account))
      .send({ city, area });
    assert.equal(response.status, 204, response.text);
  }

  async function savePreferences(account: Account, overrides: Record<string, boolean> = {}): Promise<void> {
    const response = await request(app)
      .put('/api/v1/community/preferences')
      .set(auth(account))
      .send({
        discoverable: true,
        showGym: true,
        showArea: true,
        nearbyDiscovery: true,
        allowConnectionRequests: true,
        allowMessages: true,
        notifyConnections: true,
        notifyMessages: true,
        notifyComments: true,
        notifyLikes: true,
        ...overrides,
      });
    assert.equal(response.status, 200, response.text);
  }

  async function readyMember(name: string, area = 'Adyar', age = 30): Promise<Account> {
    const account = await register(name);
    await saveProfile(account, name, age);
    await setArea(account, area);
    await savePreferences(account);
    return account;
  }

  async function connectPair(a: Account, b: Account): Promise<{ connectionId: string; conversationId: string }> {
    const sent = await request(app)
      .post('/api/v1/community/connections')
      .set(auth(a))
      .send({ target: b.userId });
    assert.equal(sent.status, 201, sent.text);
    const accepted = await request(app)
      .post(`/api/v1/community/connections/${sent.body.connection_id}/respond`)
      .set(auth(b))
      .send({ accept: true });
    assert.equal(accepted.status, 200, accepted.text);
    assert.equal(accepted.body.status, 'accepted');
    assert.ok(accepted.body.conversation_id);
    return { connectionId: sent.body.connection_id, conversationId: accepted.body.conversation_id };
  }

  async function makeGym(
    owner: Account,
    admin: Account,
    input: { name: string; city: string; area?: string; state?: string; country?: string; postalCode?: string },
  ): Promise<string> {
    const requested = await request(app)
      .post('/api/v1/community/gyms')
      .set(auth(owner))
      .send(input);
    assert.equal(requested.status, 201, requested.text);
    if (requested.body.created) {
      const review = await request(app)
        .post(`/api/v1/community/admin/gyms/${requested.body.id}/review`)
        .set(auth(admin))
        .send({ approve: true });
      assert.equal(review.status, 204, review.text);
    }
    return requested.body.id as string;
  }

  it('requires authentication', async () => {
    const response = await request(app).get('/api/v1/community/bootstrap');
    assert.equal(response.status, 401);
  });

  it('enforces age bands during discovery and profile access', async () => {
    const adult = await readyMember('ada', 'Adyar', 30);
    const minor = await readyMember('milo', 'Adyar', 16);

    const discover = await request(app)
      .get('/api/v1/community/discover?scope=area')
      .set(auth(adult));
    assert.equal(discover.status, 200, discover.text);
    assert.equal(discover.body.length, 0, 'an adult must not discover a minor');

    const profile = await request(app).get(`/api/v1/community/profiles/${minor.userId}`).set(auth(adult));
    assert.equal(profile.status, 404);

    const requestSent = await request(app)
      .post('/api/v1/community/connections')
      .set(auth(adult))
      .send({ target: minor.userId });
    assert.equal(requestSent.status, 403);
  });

  it('hides members who opt out and exposes only coarse area data', async () => {
    const viewer = await readyMember('viewer');
    const hidden = await readyMember('hidden');
    await savePreferences(hidden, { discoverable: false });

    const discover = await request(app).get('/api/v1/community/discover?scope=area').set(auth(viewer));
    assert.equal(discover.status, 200, discover.text);
    assert.deepEqual(discover.body.map((row: { username: string }) => row.username), []);

    await savePreferences(hidden, { discoverable: true });
    const again = await request(app).get('/api/v1/community/discover?scope=area').set(auth(viewer));
    assert.equal(again.body.length, 1);
    assert.equal(again.body[0].area, 'Adyar');
    assert.equal(again.body[0].city, 'Chennai');
    assert.equal(again.body[0].connection_status, 'none');
  });

  it('runs the connection, message and notification lifecycle with dedupe', async () => {
    const a = await readyMember('arjun');
    const b = await readyMember('bela');

    const sent = await request(app)
      .post('/api/v1/community/connections')
      .set(auth(a))
      .send({ target: b.userId });
    assert.equal(sent.status, 201, sent.text);
    assert.equal(sent.body.status, 'pending');

    const incoming = await request(app).get('/api/v1/community/bootstrap').set(auth(b));
    assert.equal(incoming.body.incoming_request_count, 1);
    assert.equal(incoming.body.incoming_requests[0].user_id, a.userId);
    assert.equal(realtime.eventsFor(b.userId, 'notification').length, 1);

    const duplicate = await request(app)
      .post('/api/v1/community/connections')
      .set(auth(a))
      .send({ target: b.userId });
    assert.equal(duplicate.status, 201);
    assert.equal(duplicate.body.connection_id, sent.body.connection_id);

    const accepted = await request(app)
      .post(`/api/v1/community/connections/${sent.body.connection_id}/respond`)
      .set(auth(b))
      .send({ accept: true });
    assert.equal(accepted.status, 200, accepted.text);
    const conversationId = accepted.body.conversation_id as string;
    assert.ok(conversationId);

    const messageId = '00000000-0000-4000-8000-000000000001';
    const message = await request(app)
      .post(`/api/v1/community/conversations/${conversationId}/messages`)
      .set(auth(a))
      .send({ id: messageId, body: 'See you at the squat rack.' });
    assert.equal(message.status, 201, message.text);
    assert.equal(message.body.duplicate, false);

    const again = await request(app)
      .post(`/api/v1/community/conversations/${conversationId}/messages`)
      .set(auth(a))
      .send({ id: messageId, body: 'See you at the squat rack.' });
    assert.equal(again.status, 200);
    assert.equal(again.body.duplicate, true);

    const conversations = await request(app).get('/api/v1/community/conversations').set(auth(b));
    assert.equal(conversations.status, 200, conversations.text);
    assert.equal(conversations.body.length, 1);
    assert.equal(conversations.body[0].unread_count, 1);
    assert.equal(conversations.body[0].last_message, 'See you at the squat rack.');

    const messages = await request(app)
      .get(`/api/v1/community/conversations/${conversationId}/messages`)
      .set(auth(b));
    assert.equal(messages.status, 200, messages.text);
    assert.equal(messages.body.length, 1);
    assert.equal(messages.body[0].id, messageId);

    const read = await request(app)
      .post(`/api/v1/community/conversations/${conversationId}/read`)
      .set(auth(b));
    assert.equal(read.status, 204);

    const afterRead = await request(app).get('/api/v1/community/conversations').set(auth(b));
    assert.equal(afterRead.body[0].unread_count, 0);

    const notifications = await request(app).get('/api/v1/community/notifications').set(auth(b));
    assert.equal(notifications.status, 200, notifications.text);
    assert.deepEqual(
      notifications.body.map((row: { kind: string }) => row.kind).sort(),
      ['connection_request', 'message'],
    );

    assert.ok(realtime.eventsFor(b.userId, 'message').length >= 1, 'the recipient stream receives the message');
    const stored = await pool.query('SELECT body FROM community_messages WHERE id = $1', [messageId]);
    assert.equal(stored.rows[0]?.body, 'See you at the squat rack.');
  });

  it('rejects messages from non-participants and blocks contact after blocking', async () => {
    const a = await readyMember('arun');
    const b = await readyMember('bina');
    const outsider = await readyMember('chan');
    const { conversationId } = await connectPair(a, b);

    const blockedSend = await request(app)
      .post(`/api/v1/community/conversations/${conversationId}/messages`)
      .set(auth(outsider))
      .send({ id: '00000000-0000-4000-8000-000000000002', body: 'Let me in.' });
    assert.equal(blockedSend.status, 404);

    const block = await request(app)
      .post('/api/v1/community/blocks')
      .set(auth(b))
      .send({ target: a.userId, blocked: true });
    assert.equal(block.status, 204);

    const afterBlock = await request(app)
      .post(`/api/v1/community/conversations/${conversationId}/messages`)
      .set(auth(a))
      .send({ id: '00000000-0000-4000-8000-000000000003', body: 'Hello?' });
    assert.equal(afterBlock.status, 403);

    const bConversations = await request(app).get('/api/v1/community/conversations').set(auth(b));
    assert.equal(bConversations.body.length, 0);

    const bDiscover = await request(app).get('/api/v1/community/discover?scope=all').set(auth(b));
    assert.ok(
      !bDiscover.body.some((row: { user_id: string }) => row.user_id === a.userId),
      'a blocked member must disappear from discovery',
    );

    const unblock = await request(app)
      .post('/api/v1/community/blocks')
      .set(auth(b))
      .send({ target: a.userId, blocked: false });
    assert.equal(unblock.status, 204);
  });

  it('limits feed visibility, counters, comments and hides', async () => {
    const author = await readyMember('author');
    const friend = await readyMember('friend');
    const stranger = await readyMember('stranger', 'Anna Nagar');
    await connectPair(author, friend);

    const postId = '00000000-0000-4000-8000-000000000010';
    const created = await request(app)
      .post('/api/v1/community/posts')
      .set(auth(author))
      .send({ id: postId, content: 'Five sets of squats today.', kind: 'workout', achievementLabel: 'Leg day' });
    assert.equal(created.status, 201, created.text);

    const friendFeed = await request(app).get('/api/v1/community/feed?filter=connections').set(auth(friend));
    assert.equal(friendFeed.status, 200, friendFeed.text);
    assert.equal(friendFeed.body.length, 1);
    assert.equal(friendFeed.body[0].is_own, false);
    assert.equal(friendFeed.body[0].like_count, 0);

    const strangerFeed = await request(app).get('/api/v1/community/feed').set(auth(stranger));
    assert.equal(strangerFeed.body.length, 0, 'a stranger from another area must not read the post');

    const ownFeed = await request(app).get('/api/v1/community/feed').set(auth(author));
    assert.equal(ownFeed.body.length, 1);
    assert.equal(ownFeed.body[0].is_own, true);

    const liked = await request(app)
      .post(`/api/v1/community/posts/${postId}/like`)
      .set(auth(friend))
      .send({ liked: true });
    assert.equal(liked.status, 200, liked.text);
    assert.deepEqual(liked.body, { liked: true, like_count: 1, comment_count: 0 });

    const commentId = '00000000-0000-4000-8000-000000000011';
    const comment = await request(app)
      .post(`/api/v1/community/posts/${postId}/comments`)
      .set(auth(friend))
      .send({ id: commentId, content: 'Strong work.' });
    assert.equal(comment.status, 201, comment.text);

    const comments = await request(app).get(`/api/v1/community/posts/${postId}/comments`).set(auth(author));
    assert.equal(comments.body.length, 1);
    assert.equal(comments.body[0].is_own, false);

    const authorFeed = await request(app).get('/api/v1/community/feed').set(auth(author));
    assert.equal(authorFeed.body[0].like_count, 1);
    assert.equal(authorFeed.body[0].comment_count, 1);

    const likes = await request(app)
      .post(`/api/v1/community/posts/${postId}/like`)
      .set(auth(friend))
      .send({ liked: false });
    assert.equal(likes.body.like_count, 0);

    await request(app).delete(`/api/v1/community/comments/${commentId}`).set(auth(friend));
    const afterDelete = await request(app).get('/api/v1/community/feed').set(auth(author));
    assert.equal(afterDelete.body[0].comment_count, 0);

    const hidden = await request(app)
      .post(`/api/v1/community/posts/${postId}/hide`)
      .set(auth(friend))
      .send({ hidden: true });
    assert.equal(hidden.status, 204);
    const hiddenFeed = await request(app).get('/api/v1/community/feed').set(auth(friend));
    assert.equal(hiddenFeed.body.length, 0);

    const strangerLike = await request(app)
      .post(`/api/v1/community/posts/${postId}/like`)
      .set(auth(stranger))
      .send({ liked: true });
    assert.equal(strangerLike.status, 404, 'strangers cannot interact with unreadable posts');

    const notifications = await request(app).get('/api/v1/community/notifications').set(auth(author));
    const kinds = notifications.body
      .map((row: { kind: string }) => row.kind)
      .filter((kind: string) => kind.startsWith('post_'))
      .sort();
    assert.deepEqual(kinds, ['post_comment', 'post_like']);
  });

  it('keeps moderation server-side and records an audit trail', async () => {
    const admin = await register('admin', ADMIN_EMAIL);
    const reporter = await readyMember('dinesh');
    const offender = await readyMember('eve');

    const forbidden = await request(app).get('/api/v1/community/admin/reports').set(auth(reporter));
    assert.equal(forbidden.status, 403);

    const report = await request(app)
      .post('/api/v1/community/reports')
      .set(auth(reporter))
      .send({ targetType: 'profile', targetId: offender.userId, reason: 'spam', details: 'Testing the queue.' });
    assert.equal(report.status, 201, report.text);

    const reports = await request(app).get('/api/v1/community/admin/reports').set(auth(admin));
    assert.equal(reports.status, 200, reports.text);
    assert.equal(reports.body.length, 1);
    assert.equal(reports.body[0].reporter_username, 'dinesh');

    const resolved = await request(app)
      .post(`/api/v1/community/admin/reports/${report.body.id}/resolve`)
      .set(auth(admin))
      .send({ action: 'suspend_user', note: 'Repeated spam.' });
    assert.equal(resolved.status, 204, resolved.text);

    const suspended = await request(app)
      .post('/api/v1/community/posts')
      .set(auth(offender))
      .send({ id: '00000000-0000-4000-8000-000000000020', content: 'Still here?', kind: 'update' });
    assert.equal(suspended.status, 403);

    const bootstrap = await request(app).get('/api/v1/community/bootstrap').set(auth(offender));
    assert.equal(bootstrap.body.suspended, true);

    const audit = await request(app).get('/api/v1/community/admin/audit').set(auth(admin));
    assert.equal(audit.status, 200, audit.text);
    assert.deepEqual(audit.body.map((row: { action: string }) => row.action), ['suspend_user']);
  });

  it('verifies a gym through admin review before members can join it', async () => {
    const admin = await register('admin', ADMIN_EMAIL);
    const owner = await readyMember('gymowner');
    const other = await readyMember('gymgoer');

    const requested = await request(app)
      .post('/api/v1/community/gyms')
      .set(auth(owner))
      .send({ name: 'Iron Yard', city: 'Chennai', area: 'Adyar' });
    assert.equal(requested.status, 201, requested.text);
    assert.equal(requested.body.created, true);

    const pendingJoin = await request(app)
      .post(`/api/v1/community/gyms/${requested.body.id}/join`)
      .set(auth(other));
    assert.equal(pendingJoin.status, 403);

    const review = await request(app)
      .post(`/api/v1/community/admin/gyms/${requested.body.id}/review`)
      .set(auth(admin))
      .send({ approve: true, note: 'Confirmed address.' });
    assert.equal(review.status, 204);

    const join = await request(app)
      .post(`/api/v1/community/gyms/${requested.body.id}/join`)
      .set(auth(other));
    assert.equal(join.status, 204);

    const search = await request(app).get('/api/v1/community/gyms?q=Iron').set(auth(other));
    assert.equal(search.status, 200, search.text);
    assert.equal(search.body[0].verification_status, 'verified');
    assert.equal(search.body[0].member_count, 1);

    const bootstrap = await request(app).get('/api/v1/community/bootstrap').set(auth(other));
    assert.equal(bootstrap.body.membership.gym_name, 'Iron Yard');
  });

  it("erases a deleted account's pending gym submissions but keeps approved gyms", async () => {
    const admin = await register('admin', ADMIN_EMAIL);
    const submitter = await readyMember('deletingsubmitter');
    const approved = await makeGym(submitter, admin, { name: 'Stays Around Gym', city: 'Chennai' });
    const pending = await request(app)
      .post('/api/v1/community/gyms')
      .set(auth(submitter))
      .send({ name: 'Disappears Gym', city: 'Chennai' });
    assert.equal(pending.status, 201, pending.text);
    assert.equal(pending.body.created, true);

    const removed = await request(app)
      .delete('/api/v1/auth/account')
      .set(auth(submitter))
      .send({ password: 'correct horse battery' });
    assert.equal(removed.status, 204, removed.text);

    const rows = await pool.query<{ id: string }>('SELECT id FROM gyms WHERE id = ANY($1::uuid[])', [
      [approved, pending.body.id as string],
    ]);
    assert.deepEqual(
      rows.rows.map((row) => row.id),
      [approved],
      'only the pending submission goes away with the account',
    );
  });

  it('searches the worldwide gym directory by text, city, country and postal code', async () => {
    const admin = await register('admin', ADMIN_EMAIL);
    const member = await readyMember('globalsearch');

    const chennai = await makeGym(member, admin, {
      name: 'Iron Yard', city: 'Chennai', area: 'Adyar', country: 'India', postalCode: '600020',
    });
    const paris = await makeGym(member, admin, {
      name: 'Le Marais Strength', city: 'Paris', area: 'Le Marais', country: 'France', postalCode: '75011',
    });

    const ids = async (query: string): Promise<string[]> => {
      const response = await request(app).get(`/api/v1/community/gyms?${query}`).set(auth(member));
      assert.equal(response.status, 200, response.text);
      return response.body.map((row: { id: string }) => row.id);
    };

    assert.deepEqual(await ids('q=Iron'), [chennai]);
    assert.deepEqual(await ids('q=strength'), [paris], 'search is not tied to a single country');
    assert.deepEqual(await ids('q=marais'), [paris], 'area names are searchable');
    assert.deepEqual(await ids('city=Paris'), [paris]);
    assert.deepEqual(await ids('country=FR'), [paris]);
    assert.deepEqual(await ids('country=France'), [paris]);
    assert.deepEqual(await ids('country=India'), [chennai]);
    assert.deepEqual(await ids('postal_code=6000'), [chennai]);
    assert.deepEqual(await ids('q=iron&country=FR'), [], 'filters combine');

    const badLimit = await request(app).get('/api/v1/community/gyms?limit=0').set(auth(member));
    assert.equal(badLimit.status, 400);
  });

  it('orders nearby gyms by distance and validates coordinates', async () => {
    const admin = await register('admin', ADMIN_EMAIL);
    const member = await readyMember('nearbymember');

    const close = await makeGym(member, admin, { name: 'Close Gym', city: 'Chennai', country: 'India' });
    const mid = await makeGym(member, admin, { name: 'Mid Gym', city: 'Chennai', country: 'India' });
    const far = await makeGym(member, admin, { name: 'Far Gym', city: 'Chennai', country: 'India' });
    await pool.query('UPDATE gyms SET latitude = 13.004, longitude = 80.2 WHERE id = $1', [close]);
    await pool.query('UPDATE gyms SET latitude = 13.05, longitude = 80.2 WHERE id = $1', [mid]);
    await pool.query('UPDATE gyms SET latitude = 13.3, longitude = 80.2 WHERE id = $1', [far]);

    const nearby = async (radius: number): Promise<Array<{ id: string; distance_km: number }>> => {
      const response = await request(app)
        .get(`/api/v1/community/gyms/nearby?lat=13.0&lng=80.2&radius_km=${radius}`)
        .set(auth(member));
      assert.equal(response.status, 200, response.text);
      return response.body;
    };

    assert.deepEqual((await nearby(2)).map((gym) => gym.id), [close]);
    assert.deepEqual((await nearby(10)).map((gym) => gym.id), [close, mid]);
    const all = await nearby(50);
    assert.deepEqual(all.map((gym) => gym.id), [close, mid, far]);
    assert.ok(all[0]!.distance_km < all[1]!.distance_km);

    const badLat = await request(app)
      .get('/api/v1/community/gyms/nearby?lat=91&lng=80.2')
      .set(auth(member));
    assert.equal(badLat.status, 400);

    const missing = await request(app).get('/api/v1/community/gyms/nearby').set(auth(member));
    assert.equal(missing.status, 400);
  });

  it('ingests provider results once, dedupes by identity and serves repeats from cache', async () => {
    const admin = await register('admin', ADMIN_EMAIL);
    const member = await readyMember('provideruser');
    const existing = await makeGym(member, admin, {
      name: 'Beacon Strength', city: 'Chennai', country: 'India',
    });
    await pool.query('UPDATE gyms SET latitude = 13.01, longitude = 80.21 WHERE id = $1', [existing]);

    const provider = new FakeProvider([
      {
        providerId: 'osm/node/1', providerName: 'osm', name: 'Beacon Strength',
        address: '1 Beacon Road', city: 'Chennai', region: 'Tamil Nadu', country: 'India',
        countryCode: 'IN', postalCode: null, neighborhood: null,
        latitude: 13.0102, longitude: 80.2102, website: null, phone: null,
      },
      {
        providerId: 'osm/node/2', providerName: 'osm', name: 'Riverside Barbell',
        address: null, city: 'Chennai', region: 'Tamil Nadu', country: 'India',
        countryCode: 'IN', postalCode: null, neighborhood: null,
        latitude: 13.02, longitude: 80.22, website: null, phone: null,
      },
    ]);
    app = buildApp(realtime, provider);

    const first = await request(app).get('/api/v1/community/gyms?q=Beacon').set(auth(member));
    assert.equal(first.status, 200, first.text);
    assert.equal(provider.textCalls, 1);

    const second = await request(app).get('/api/v1/community/gyms?q=Beacon').set(auth(member));
    assert.equal(second.status, 200, second.text);
    assert.equal(provider.textCalls, 1, 'repeated searches are served from the provider cache');

    const beacon = await pool.query<{ count: number }>(
      `SELECT count(*)::int AS count FROM gyms WHERE normalized_name = 'beacon strength'`,
    );
    assert.equal(beacon.rows[0]!.count, 1, 'the provider row is merged into the existing gym');

    const riverside = await pool.query<{ verification_status: string; source: string }>(
      `SELECT verification_status, source FROM gyms WHERE normalized_name = 'riverside barbell'`,
    );
    assert.equal(riverside.rows[0]?.verification_status, 'imported');
    assert.equal(riverside.rows[0]?.source, 'osm');

    const status = await request(app).get('/api/v1/community/gyms/provider').set(auth(member));
    assert.equal(status.status, 200, status.text);
    assert.equal(status.body.configured, true);
    assert.equal(status.body.name, 'osm');

    const emptyApp = buildApp(realtime, null);
    app = emptyApp;
    const unconfigured = await request(app).get('/api/v1/community/gyms/provider').set(auth(member));
    assert.equal(unconfigured.body.configured, false);
    assert.match(unconfigured.body.reason, /No gym directory provider/);
  });

  it('tops up nearby search from the provider and returns measured distances', async () => {
    const admin = await register('admin', ADMIN_EMAIL);
    const member = await readyMember('nearbyprovider');

    const provider = new FakeProvider([], [
      {
        providerId: 'osm/node/3', providerName: 'osm', name: 'Provider Gym',
        address: null, city: 'Chennai', region: 'Tamil Nadu', country: 'India',
        countryCode: 'IN', postalCode: null, neighborhood: null,
        latitude: 13.001, longitude: 80.201, website: null, phone: null,
      },
    ]);
    app = buildApp(realtime, provider);

    const response = await request(app)
      .get('/api/v1/community/gyms/nearby?lat=13.0&lng=80.2&radius_km=5')
      .set(auth(member));
    assert.equal(response.status, 200, response.text);
    assert.equal(provider.nearbyCalls, 1);
    assert.equal(response.body.length, 1);
    assert.equal(response.body[0].name, 'Provider Gym');
    assert.ok(response.body[0].distance_km < 1);
    assert.equal(admin.email, ADMIN_EMAIL);
  });

  it('reports a directory failure instead of pretending there are no gyms', async () => {
    const member = await readyMember('nearbyfail');
    app = buildApp(realtime, new FakeProvider([], [], 'all'));

    const nearby = await request(app)
      .get('/api/v1/community/gyms/nearby?lat=0.5&lng=0.5&radius_km=5')
      .set(auth(member));
    assert.equal(nearby.status, 503, nearby.text);
    assert.equal(nearby.body.error.code, 'gym_directory_unavailable');
    assert.match(nearby.body.error.message, /add your gym manually/);

    const search = await request(app)
      .get('/api/v1/community/gyms?q=qzxvunmatcheddirectory')
      .set(auth(member));
    assert.equal(search.status, 503, search.text);
    assert.equal(search.body.error.code, 'gym_directory_unavailable');
  });

  it('keeps multiple memberships with exactly one primary and removes them safely', async () => {
    const admin = await register('admin', ADMIN_EMAIL);
    const member = await readyMember('multigym');
    const alpha = await makeGym(member, admin, {
      name: 'Alpha Gym', city: 'Chennai', area: 'Adyar', country: 'India',
    });
    const beta = await makeGym(member, admin, {
      name: 'Beta Gym', city: 'Chennai', area: 'Velachery', country: 'India',
    });

    const first = await request(app)
      .post(`/api/v1/community/gyms/${alpha}/join`)
      .set(auth(member))
      .send({});
    assert.equal(first.status, 204, first.text);

    const second = await request(app)
      .post(`/api/v1/community/gyms/${beta}/join`)
      .set(auth(member))
      .send({ isPrimary: true, visibility: 'public', membershipType: 'day_pass' });
    assert.equal(second.status, 204, second.text);

    const bootstrap = await request(app).get('/api/v1/community/bootstrap').set(auth(member));
    assert.equal(bootstrap.status, 200, bootstrap.text);
    const memberships = bootstrap.body.memberships as Array<{ gym_id: string; is_primary: boolean; membership_type: string }>;
    assert.equal(memberships.length, 2);
    assert.equal(memberships.filter((row) => row.is_primary).length, 1);
    assert.equal(memberships[0]!.gym_id, beta);
    assert.equal(memberships[0]!.membership_type, 'day_pass');

    const removeAlpha = await request(app)
      .delete(`/api/v1/community/gyms/membership/${alpha}`)
      .set(auth(member));
    assert.equal(removeAlpha.status, 204, removeAlpha.text);

    const unknown = await request(app)
      .delete('/api/v1/community/gyms/membership/00000000-0000-4000-8000-000000000099')
      .set(auth(member));
    assert.equal(unknown.status, 404);

    const after = await request(app).get('/api/v1/community/bootstrap').set(auth(member));
    assert.equal(after.body.memberships.length, 1);

    const leave = await request(app).delete('/api/v1/community/gyms/membership').set(auth(member));
    assert.equal(leave.status, 204, leave.text);

    const empty = await request(app).get('/api/v1/community/bootstrap').set(auth(member));
    assert.equal(empty.body.memberships.length, 0);
    assert.equal(empty.body.membership, null);
  });

  it('discovers members worldwide and respects gym and global visibility', async () => {
    const admin = await register('admin', ADMIN_EMAIL);
    const viewer = await readyMember('westview');
    const paris = await readyMember('eastmember');
    const parisGym = await makeGym(viewer, admin, {
      name: 'Paris Strength Club', city: 'Paris', area: 'Le Marais',
      state: 'Île-de-France', country: 'France', postalCode: '75003',
    });
    const joinParis = await request(app)
      .post(`/api/v1/community/gyms/${parisGym}/join`)
      .set(auth(paris))
      .send({ isPrimary: true });
    assert.equal(joinParis.status, 204, joinParis.text);

    const discover = async (query: string): Promise<Array<Record<string, unknown>>> => {
      const response = await request(app)
        .get(`/api/v1/community/discover?${query}`)
        .set(auth(viewer));
      assert.equal(response.status, 200, response.text);
      return response.body;
    };

    const global = await discover('scope=global');
    assert.equal(global.length, 1);
    const east = global[0]!;
    assert.equal(east.username, 'eastmember');
    assert.equal(east.city, 'Paris');
    assert.equal(east.country, 'France');
    assert.equal(east.country_code, 'FR');
    assert.equal(east.gym_name, 'Paris Strength Club');
    assert.ok(!('latitude' in east) && !('longitude' in east), 'member coordinates are never exposed');

    assert.deepEqual(await discover('scope=gym'), [], 'different gyms are not a gym match');
    assert.equal((await discover('scope=global&country=FR')).length, 1);
    assert.equal((await discover('scope=global&country=France')).length, 1);
    assert.equal((await discover('scope=global&country=IN')).length, 0);
    assert.equal((await discover('scope=global&city=Paris')).length, 1);
    assert.equal((await discover('scope=global&q=eastmember')).length, 1);

    const profile = await request(app)
      .get(`/api/v1/community/profiles/${paris.userId}`)
      .set(auth(viewer));
    assert.equal(profile.status, 200, profile.text);
    assert.equal(profile.body.country, 'France');

    await savePreferences(paris, { globalDiscovery: false });
    assert.deepEqual(await discover('scope=global'), []);
    const hiddenProfile = await request(app)
      .get(`/api/v1/community/profiles/${paris.userId}`)
      .set(auth(viewer));
    assert.equal(hiddenProfile.status, 404);

    await savePreferences(paris, { globalDiscovery: true });
    const joinViewer = await request(app)
      .post(`/api/v1/community/gyms/${parisGym}/join`)
      .set(auth(viewer))
      .send({ isPrimary: false });
    assert.equal(joinViewer.status, 204, joinViewer.text);

    // Region matching follows the state of the member's primary gym, not its city.
    const versailles = await makeGym(viewer, admin, {
      name: 'Versailles Barbell', city: 'Versailles',
      state: 'Île-de-France', country: 'France', postalCode: '78000',
    });
    const joinPrimary = await request(app)
      .post(`/api/v1/community/gyms/${versailles}/join`)
      .set(auth(viewer))
      .send({ isPrimary: true });
    assert.equal(joinPrimary.status, 204, joinPrimary.text);
    assert.deepEqual((await discover('scope=region')).map((row) => row.username), ['eastmember']);
    assert.deepEqual(await discover('scope=city'), [], 'a shared region is not a city match');

    const shared = await discover('scope=gym');
    assert.deepEqual(shared.map((row) => row.username), ['eastmember']);

    await pool.query(`UPDATE gym_memberships SET visibility = 'private' WHERE user_id = $1`, [paris.userId]);
    assert.deepEqual(await discover('scope=gym'), [], 'a private membership is never surfaced');

    const afterPrivate = await discover('scope=global');
    assert.equal(afterPrivate[0]!.gym_name, null);
    assert.equal(afterPrivate[0]!.city, 'Paris');
  });

  it('reports incorrect gym details and rejects unknown gym ids', async () => {
    const admin = await register('admin', ADMIN_EMAIL);
    const member = await readyMember('reporter');
    const gym = await makeGym(member, admin, {
      name: 'Reportable Gym', city: 'Chennai', country: 'India',
    });

    const reported = await request(app)
      .post(`/api/v1/community/gyms/${gym}/report`)
      .set(auth(member))
      .send({ reason: 'incorrect_details', details: 'Closed two years ago.' });
    assert.equal(reported.status, 201, reported.text);
    const row = await pool.query<{ reason: string; target_type: string }>(
      'SELECT reason, target_type FROM community_reports WHERE id = $1',
      [reported.body.id],
    );
    assert.equal(row.rows[0]?.reason, 'incorrect_details');
    assert.equal(row.rows[0]?.target_type, 'gym');

    const missing = await request(app)
      .post('/api/v1/community/gyms/00000000-0000-4000-8000-000000000098/report')
      .set(auth(member))
      .send({});
    assert.equal(missing.status, 404);

    const malformed = await request(app)
      .get('/api/v1/community/discover?scope=global&gym_id=not-a-uuid')
      .set(auth(member));
    assert.equal(malformed.status, 400);

    const badScope = await request(app)
      .get('/api/v1/community/discover?scope=planet')
      .set(auth(member));
    assert.equal(badScope.status, 400);
  });

  it('streams messages to the authenticated recipient over Socket.IO', async () => {
    const a = await readyMember('nila');
    const b = await readyMember('omar');
    const { conversationId } = await connectPair(a, b);

    const server: HttpServer = createServer(app);
    const io = new Server(server, { serveClient: false });
    let live: CommunityRealtime = noRealtime;
    const proxy: CommunityRealtime = {
      emitToUser(userId, event, payload) {
        live.emitToUser(userId, event, payload);
      },
    };
    app = buildApp(proxy);
    live = attachCommunityRealtime({ io, pool, logger: createLogger('silent') });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    const address = server.address();
    assert.ok(address && typeof address === 'object');
    const baseUrl = `http://127.0.0.1:${address.port}`;

    const recipient = await openSocket(baseUrl, b.token);
    const messageId = '00000000-0000-4000-8000-000000000030';
    try {
      const response = await request(app)
        .post(`/api/v1/community/conversations/${conversationId}/messages`)
        .set(auth(a))
        .send({ id: messageId, body: 'Live from the squat rack.' });
      assert.equal(response.status, 201, response.text);

      const event = await recipient.next('message', 2000);
      assert.equal(event.id, messageId);
      assert.equal(event.body, 'Live from the squat rack.');
      const persisted = await pool.query('SELECT sender_id FROM community_messages WHERE id = $1', [messageId]);
      assert.equal(persisted.rows[0]?.sender_id, a.userId);
    } finally {
      recipient.close();
      io.close();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }

    const anonymous = await openSocket(baseUrl, 'not-a-real-token-xxxxxxxxxxxxxxxxxxxx', { expectFailure: true });
    anonymous.close();
    void live;
  });

  it('disconnects an open socket once its session is revoked', async () => {
    const member = await readyMember('revokedstream');

    const server: HttpServer = createServer(app);
    const io = new Server(server, { serveClient: false });
    attachCommunityRealtime({ io, pool, logger: createLogger('silent'), sessionRecheckMs: 50 });
    await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
    const address = server.address();
    assert.ok(address && typeof address === 'object');
    const baseUrl = `http://127.0.0.1:${address.port}`;

    const socket = await openSocket(baseUrl, member.token);
    try {
      const logout = await request(app).post('/api/v1/auth/logout').set(auth(member));
      assert.equal(logout.status, 204, logout.text);
      await Promise.race([
        socket.closed,
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error('the socket stayed open after its session was revoked')), 2000),
        ),
      ]);
    } finally {
      socket.close();
      io.close();
      await new Promise<void>((resolve) => server.close(() => resolve()));
    }
  });
});

interface SocketHandle {
  next(event: string, timeoutMs: number): Promise<Record<string, any>>;
  close(): void;
  readonly closed: Promise<void>;
}

async function openSocket(
  baseUrl: string,
  token: string,
  options: { expectFailure?: boolean } = {},
): Promise<SocketHandle> {
  const url = `${baseUrl.replace(/^http/, 'ws')}/socket.io/?EIO=4&transport=websocket&token=${encodeURIComponent(token)}`;
  const socket = new WebSocket(url);
  const events: Array<{ name: string; payload: Record<string, any> }> = [];
  const listeners: Array<() => void> = [];
  let connected = false;
  let resolveClosed: () => void = () => {};
  const closed = new Promise<void>((resolve) => {
    resolveClosed = resolve;
  });
  socket.addEventListener('close', () => resolveClosed());

  function handle(raw: string): void {
    if (raw.startsWith('0')) {
      socket.send('40');
      return;
    }
    if (raw === '2') {
      socket.send('3');
      return;
    }
    if (raw.startsWith('40')) {
      connected = true;
      return;
    }
    if (raw.startsWith('42')) {
      const [name, payload] = JSON.parse(raw.slice(2)) as [string, Record<string, any>];
      events.push({ name, payload });
      for (const listener of listeners.splice(0)) listener();
    }
  }

  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(
      () =>
        reject(
          new Error(
            options.expectFailure ? 'an unauthenticated socket stayed connected' : 'socket did not connect in time',
          ),
        ),
      3000,
    );
    const settle = (error?: Error) => {
      clearTimeout(timer);
      if (error) reject(error);
      else resolve();
    };
    socket.addEventListener('message', (event) => {
      const raw = String(event.data);
      handle(raw);
      if (options.expectFailure) {
        if (raw.startsWith('44')) settle();
        return;
      }
      if (raw.startsWith('40')) settle();
    });
    socket.addEventListener('error', () => {
      if (options.expectFailure) settle();
      else settle(new Error('socket error'));
    });
    socket.addEventListener('close', () => {
      if (options.expectFailure) settle();
      else if (!connected) settle(new Error('socket closed before connecting'));
    });
  }).catch((error: unknown) => {
    socket.close();
    if (!options.expectFailure) throw error;
  });

  return {
    next(event, timeoutMs) {
      const found = events.find((item) => item.name === event);
      if (found) {
        events.splice(events.indexOf(found), 1);
        return Promise.resolve(found.payload);
      }
      return new Promise<Record<string, any>>((resolve, reject) => {
        const timer = setTimeout(() => {
          socket.close();
          reject(new Error(`timed out waiting for ${event}`));
        }, timeoutMs);
        const check = () => {
          const match = events.find((item) => item.name === event);
          if (!match) return;
          clearTimeout(timer);
          events.splice(events.indexOf(match), 1);
          resolve(match.payload);
        };
        listeners.push(check);
      });
    },
    close() {
      socket.close();
    },
    closed,
  };
}

void noRealtime;
