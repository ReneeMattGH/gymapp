import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { createServer, type Server as HttpServer } from 'node:http';
import request from 'supertest';
import type { Express } from 'express';
import { Server } from 'socket.io';
import { loadConfig, type Config } from '../src/config.js';
import { createLogger } from '../src/logger.js';
import { createPool, type Pool } from '../src/db/pool.js';
import { runMigrations } from '../src/db/migrate.js';
import { createMailer } from '../src/auth/mailer.js';
import { createAuthService } from '../src/auth/service.js';
import {
  createCommunityService,
  noRealtime,
  type CommunityRealtime,
} from '../src/community/service.js';
import { attachCommunityRealtime } from '../src/community/realtime.js';
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

  beforeEach(async () => {
    await pool.query('TRUNCATE users, gyms, community_moderation_actions, community_reports, community_notifications CASCADE');
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

  function buildApp(broadcast: CommunityRealtime): Express {
    const logger = createLogger('silent');
    const auth = createAuthService({ pool, config, mailer: createMailer({ from: 'Forma <no-reply@example.com>' }), logger });
    const community = createCommunityService({ pool, config, logger, realtime: broadcast });
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
});

interface SocketHandle {
  next(event: string, timeoutMs: number): Promise<Record<string, any>>;
  close(): void;
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
  };
}

void noRealtime;
