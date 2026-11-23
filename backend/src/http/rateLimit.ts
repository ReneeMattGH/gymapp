import rateLimit from 'express-rate-limit';

const body = (code: string, message: string) => ({ error: { code, message } });

/** Brute-force protection for credential endpoints. */
export function createSensitiveLimiter(enabled: boolean) {
  return rateLimit({
    windowMs: 15 * 60 * 1000,
    limit: 10,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    skip: () => !enabled,
    message: body('rate_limited', 'Too many attempts. Try again in a few minutes.'),
  });
}

/** Coarse ceiling for everything else. */
export function createGeneralLimiter(enabled: boolean) {
  return rateLimit({
    windowMs: 60 * 1000,
    limit: 120,
    standardHeaders: 'draft-7',
    legacyHeaders: false,
    skip: () => !enabled,
    message: body('rate_limited', 'Too many requests. Slow down.'),
  });
}
