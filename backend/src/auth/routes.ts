import { Router, type RequestHandler } from 'express';
import { z } from 'zod';
import { asyncHandler, unauthorized } from '../errors.js';
import type { AuthService } from './service.js';

const emailSchema = z.string().trim().email('Enter a valid email address.').max(254);
const passwordSchema = z
  .string()
  .min(10, 'Use at least 10 characters.')
  .max(200, 'Use 200 characters or fewer.');

const registerSchema = z.object({
  email: emailSchema,
  password: passwordSchema,
  displayName: z.string().trim().min(1).max(60).optional(),
});

const loginSchema = z.object({
  email: emailSchema,
  password: z.string().min(1).max(200),
});

const refreshSchema = z.object({
  refreshToken: z.string().min(20).max(500),
});

const tokenSchema = z.object({ token: z.string().min(20).max(500) });

const resetSchema = z.object({
  token: z.string().min(20).max(500),
  password: passwordSchema,
});

const deleteSchema = z.object({ password: z.string().min(1).max(200) });

function bearerToken(header: string | undefined): string {
  const [scheme, token] = (header ?? '').split(' ');
  if (scheme?.toLowerCase() !== 'bearer' || !token) throw unauthorized();
  return token;
}

export function createAuthRouter(options: {
  service: AuthService;
  requireAuth: RequestHandler;
  sensitiveLimiter: RequestHandler;
}): Router {
  const { service, requireAuth, sensitiveLimiter } = options;
  const router = Router();

  router.post(
    '/register',
    sensitiveLimiter,
    asyncHandler(async (req, res) => {
      const input = registerSchema.parse(req.body);
      const result = await service.register(input);
      res.status(201).json(result);
    }),
  );

  router.post(
    '/login',
    sensitiveLimiter,
    asyncHandler(async (req, res) => {
      const input = loginSchema.parse(req.body);
      res.json(await service.login(input));
    }),
  );

  router.post(
    '/refresh',
    sensitiveLimiter,
    asyncHandler(async (req, res) => {
      const { refreshToken } = refreshSchema.parse(req.body);
      const tokens = await service.refresh(refreshToken);
      res.json({ tokens });
    }),
  );

  router.post(
    '/logout',
    asyncHandler(async (req, res) => {
      await service.logout(bearerToken(req.header('authorization')));
      res.status(204).end();
    }),
  );

  router.get(
    '/me',
    requireAuth,
    asyncHandler(async (req, res) => {
      const user = await service.me(req.auth!.userId);
      res.json({ user });
    }),
  );

  router.post(
    '/verify-email',
    sensitiveLimiter,
    asyncHandler(async (req, res) => {
      const { token } = tokenSchema.parse(req.body);
      await service.verifyEmail(token);
      res.json({ verified: true });
    }),
  );

  router.post(
    '/resend-verification',
    requireAuth,
    sensitiveLimiter,
    asyncHandler(async (req, res) => {
      const result = await service.resendVerification(req.auth!.userId);
      res.status(202).json(result);
    }),
  );

  router.post(
    '/change-password',
    requireAuth,
    sensitiveLimiter,
    asyncHandler(async (req, res) => {
      const { currentPassword, newPassword } = z
        .object({ currentPassword: z.string().min(1).max(200), newPassword: passwordSchema })
        .parse(req.body);
      await service.changePassword(
        req.auth!.userId,
        req.auth!.sessionId,
        currentPassword,
        newPassword,
      );
      res.status(204).end();
    }),
  );

  router.post(
    '/password-reset',
    sensitiveLimiter,
    asyncHandler(async (req, res) => {
      const { email } = z.object({ email: emailSchema }).parse(req.body);
      await service.requestPasswordReset(email);
      res.status(202).json({ status: 'accepted' });
    }),
  );

  router.post(
    '/password-reset/confirm',
    sensitiveLimiter,
    asyncHandler(async (req, res) => {
      const { token, password } = resetSchema.parse(req.body);
      await service.resetPassword(token, password);
      res.status(204).end();
    }),
  );

  router.delete(
    '/account',
    requireAuth,
    sensitiveLimiter,
    asyncHandler(async (req, res) => {
      const { password } = deleteSchema.parse(req.body);
      await service.deleteAccount(req.auth!.userId, password);
      res.status(204).end();
    }),
  );

  return router;
}
