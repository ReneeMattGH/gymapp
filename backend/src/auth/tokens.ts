import { createHash, randomBytes } from 'node:crypto';

/** Opaque bearer credential. Only its SHA-256 hash is ever stored. */
export function generateToken(): string {
  return randomBytes(32).toString('base64url');
}

export function hashToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
