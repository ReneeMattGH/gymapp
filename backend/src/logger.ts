import pino, { type Logger } from 'pino';

const REDACTED_PATHS = [
  'req.headers.authorization',
  'req.headers.cookie',
  'req.body.password',
  'req.body.newPassword',
  'req.body.refreshToken',
  'req.body.token',
  'password',
  '*.password',
  'passwordHash',
  '*.passwordHash',
  'token',
  '*.token',
  'refreshToken',
  '*.refreshToken',
];

export function createLogger(level: string): Logger {
  return pino({
    level,
    redact: { paths: REDACTED_PATHS, censor: '[redacted]' },
    base: undefined,
    timestamp: pino.stdTimeFunctions.isoTime,
  });
}
