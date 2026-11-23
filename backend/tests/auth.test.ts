import { after, before, beforeEach, describe, it } from 'node:test';
import assert from 'node:assert/strict';
import request from 'supertest';
import type { Express } from 'express';
import { loadConfig, type Config } from '../src/config.js';
import { createLogger } from '../src/logger.js';
import { createPool, type Pool } from '../src/db/pool.js';
import { runMigrations } from '../src/db/migrate.js';
import { createMailer, type Mailer, type OutboundMail } from '../src/auth/mailer.js';
import { createAuthService } from '../src/auth/service.js';
import { createCommunityService, noRealtime } from '../src/community/service.js';
import { createApp } from '../src/http/app.js';

class RecordingMailer implements Mailer {
  readonly configured = true;
  readonly sent: OutboundMail[] = [];
  async send(mail: OutboundMail): Promise<void> {
    this.sent.push(mail);
  }
  lastToken(): string {
    const mail = this.sent.at(-1);
    assert.ok(mail, 'expected an email to have been sent');
    const match = mail.text.match(/token=([A-Za-z0-9_-]+)/);
    assert.ok(match, 'expected a token link in the email');
    return match[1]!;
  }
}

describe('auth API', () => {
  let pool: Pool;
  let app: Express;
  let recordingMailer: RecordingMailer;
  let silentMailer: Mailer;

  const baseConfig: Config = loadConfig({
    NODE_ENV: 'test',
    DATABASE_URL: process.env.TEST_DATABASE_URL ?? 'postgres://localhost:5432/forma_test',
    LOG_LEVEL: 'silent',
  });

  function buildApp(mailer: Mailer): Express {
    const logger = createLogger('silent');
    const auth = createAuthService({ pool, config: baseConfig, mailer, logger });
    const community = createCommunityService({ pool, config: baseConfig, logger, realtime: noRealtime });
    return createApp({ config: baseConfig, pool, logger, auth, community });
  }

  before(async () => {
    pool = createPool(baseConfig.databaseUrl);
    await runMigrations(pool);
  });

  beforeEach(async () => {
    await pool.query('TRUNCATE users CASCADE');
    recordingMailer = new RecordingMailer();
    silentMailer = createMailer({ from: 'Forma <no-reply@example.com>' });
    app = buildApp(recordingMailer);
  });

  after(async () => {
    await pool.end();
  });

  const credentials = { email: 'matt@example.com', password: 'correct horse battery' };

  it('reports health with a live database', async () => {
    const response = await request(app).get('/health');
    assert.equal(response.status, 200);
    assert.equal(response.body.status, 'ok');
    assert.equal(response.body.database, 'up');
  });

  it('registers, issues tokens and serves the account', async () => {
    const response = await request(app).post('/api/v1/auth/register').send(credentials);
    assert.equal(response.status, 201);
    assert.equal(response.body.user.email, credentials.email);
    assert.equal(response.body.user.emailVerified, false);
    assert.equal(response.body.emailVerificationSent, true);
    assert.ok(response.body.tokens.accessToken);
    assert.ok(response.body.tokens.refreshToken);

    const me = await request(app)
      .get('/api/v1/auth/me')
      .set('authorization', `Bearer ${response.body.tokens.accessToken}`);
    assert.equal(me.status, 200);
    assert.equal(me.body.user.id, response.body.user.id);
  });

  it('reports verification honestly when SMTP is not configured', async () => {
    const appWithoutMail = buildApp(silentMailer);
    const response = await request(appWithoutMail).post('/api/v1/auth/register').send(credentials);
    assert.equal(response.status, 201);
    assert.equal(response.body.emailVerificationSent, false);
  });

  it('rejects duplicate emails regardless of case', async () => {
    await request(app).post('/api/v1/auth/register').send(credentials).expect(201);
    const duplicate = await request(app)
      .post('/api/v1/auth/register')
      .send({ ...credentials, email: 'MATT@Example.com' });
    assert.equal(duplicate.status, 409);
    assert.equal(duplicate.body.error.code, 'email_taken');
  });

  it('validates the request body', async () => {
    const response = await request(app)
      .post('/api/v1/auth/register')
      .send({ email: 'not-an-email', password: 'short' });
    assert.equal(response.status, 400);
    assert.equal(response.body.error.code, 'validation_error');
    assert.ok(response.body.error.fields.length >= 2);
  });

  it('answers incorrect credentials with the same generic error', async () => {
    await request(app).post('/api/v1/auth/register').send(credentials).expect(201);
    const wrongPassword = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: credentials.email, password: 'wrong password here' });
    const unknownEmail = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: 'nobody@example.com', password: 'wrong password here' });
    assert.equal(wrongPassword.status, 401);
    assert.equal(unknownEmail.status, 401);
    assert.equal(wrongPassword.body.error.message, unknownEmail.body.error.message);
  });

  it('rotates refresh tokens and revokes the session on reuse', async () => {
    const registered = await request(app).post('/api/v1/auth/register').send(credentials);
    const firstRefresh = registered.body.tokens.refreshToken;

    const rotated = await request(app)
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: firstRefresh });
    assert.equal(rotated.status, 200);
    assert.notEqual(rotated.body.tokens.refreshToken, firstRefresh);
    const secondRefresh = rotated.body.tokens.refreshToken;

    const reuse = await request(app)
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: firstRefresh });
    assert.equal(reuse.status, 401);

    // Reuse must kill the whole session, including the newest refresh token.
    const afterBreach = await request(app)
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: secondRefresh });
    assert.equal(afterBreach.status, 401);

    const me = await request(app)
      .get('/api/v1/auth/me')
      .set('authorization', `Bearer ${rotated.body.tokens.accessToken}`);
    assert.equal(me.status, 401);
  });

  it('revokes access on logout', async () => {
    const registered = await request(app).post('/api/v1/auth/register').send(credentials);
    const accessToken = registered.body.tokens.accessToken;

    await request(app)
      .post('/api/v1/auth/logout')
      .set('authorization', `Bearer ${accessToken}`)
      .expect(204);

    const me = await request(app)
      .get('/api/v1/auth/me')
      .set('authorization', `Bearer ${accessToken}`);
    assert.equal(me.status, 401);

    const refresh = await request(app)
      .post('/api/v1/auth/refresh')
      .send({ refreshToken: registered.body.tokens.refreshToken });
    assert.equal(refresh.status, 401);
  });

  it('confirms an email through the token from the delivered message', async () => {
    const registered = await request(app).post('/api/v1/auth/register').send(credentials);
    const token = recordingMailer.lastToken();

    const verified = await request(app)
      .post('/api/v1/auth/verify-email')
      .send({ token });
    assert.equal(verified.status, 200);

    const me = await request(app)
      .get('/api/v1/auth/me')
      .set('authorization', `Bearer ${registered.body.tokens.accessToken}`);
    assert.equal(me.body.user.emailVerified, true);
  });

  it('answers 503 for password reset when email delivery is missing', async () => {
    const appWithoutMail = buildApp(silentMailer);
    await request(appWithoutMail).post('/api/v1/auth/register').send(credentials).expect(201);
    const response = await request(appWithoutMail)
      .post('/api/v1/auth/password-reset')
      .send({ email: credentials.email });
    assert.equal(response.status, 503);
    assert.equal(response.body.error.code, 'email_delivery_unconfigured');
  });

  it('resets the password and revokes every session', async () => {
    const registered = await request(app).post('/api/v1/auth/register').send(credentials);
    const accessToken = registered.body.tokens.accessToken;

    const requested = await request(app)
      .post('/api/v1/auth/password-reset')
      .send({ email: credentials.email });
    assert.equal(requested.status, 202);
    const token = recordingMailer.lastToken();

    await request(app)
      .post('/api/v1/auth/password-reset/confirm')
      .send({ token, password: 'a brand new passphrase' })
      .expect(204);

    const oldMe = await request(app)
      .get('/api/v1/auth/me')
      .set('authorization', `Bearer ${accessToken}`);
    assert.equal(oldMe.status, 401);

    await request(app)
      .post('/api/v1/auth/login')
      .send(credentials)
      .expect(401);
    const fresh = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: credentials.email, password: 'a brand new passphrase' });
    assert.equal(fresh.status, 200);
  });

  it('changes the password and signs out other sessions only', async () => {
    const registered = await request(app).post('/api/v1/auth/register').send(credentials);
    const accessToken = registered.body.tokens.accessToken;
    const otherLogin = await request(app).post('/api/v1/auth/login').send(credentials);
    const otherAccessToken = otherLogin.body.tokens.accessToken;

    const wrong = await request(app)
      .post('/api/v1/auth/change-password')
      .set('authorization', `Bearer ${accessToken}`)
      .send({ currentPassword: 'definitely wrong', newPassword: 'a different passphrase' });
    assert.equal(wrong.status, 401);

    await request(app)
      .post('/api/v1/auth/change-password')
      .set('authorization', `Bearer ${accessToken}`)
      .send({ currentPassword: credentials.password, newPassword: 'a different passphrase' })
      .expect(204);

    const currentMe = await request(app)
      .get('/api/v1/auth/me')
      .set('authorization', `Bearer ${accessToken}`);
    assert.equal(currentMe.status, 200);

    const otherMe = await request(app)
      .get('/api/v1/auth/me')
      .set('authorization', `Bearer ${otherAccessToken}`);
    assert.equal(otherMe.status, 401);

    const login = await request(app)
      .post('/api/v1/auth/login')
      .send({ email: credentials.email, password: 'a different passphrase' });
    assert.equal(login.status, 200);
  });

  it('rate limits repeated credential attempts outside the test environment', async () => {
    const devConfig = loadConfig({
      NODE_ENV: 'development',
      DATABASE_URL: baseConfig.databaseUrl,
      LOG_LEVEL: 'silent',
    });
    const logger = createLogger('silent');
    const auth = createAuthService({ pool, config: devConfig, mailer: recordingMailer, logger });
    const community = createCommunityService({ pool, config: devConfig, logger, realtime: noRealtime });
    const devApp = createApp({ config: devConfig, pool, logger, auth, community });

    let status = 0;
    for (let attempt = 0; attempt < 11; attempt += 1) {
      const response = await request(devApp)
        .post('/api/v1/auth/login')
        .send({ email: 'nobody@example.com', password: 'whatever-password' });
      status = response.status;
    }
    assert.equal(status, 429);
  });

  it('requires the password to delete an account and then erases it', async () => {
    const registered = await request(app).post('/api/v1/auth/register').send(credentials);
    const accessToken = registered.body.tokens.accessToken;

    const wrong = await request(app)
      .delete('/api/v1/auth/account')
      .set('authorization', `Bearer ${accessToken}`)
      .send({ password: 'not the password' });
    assert.equal(wrong.status, 401);

    await request(app)
      .delete('/api/v1/auth/account')
      .set('authorization', `Bearer ${accessToken}`)
      .send({ password: credentials.password })
      .expect(204);

    const login = await request(app).post('/api/v1/auth/login').send(credentials);
    assert.equal(login.status, 401);
  });
});
