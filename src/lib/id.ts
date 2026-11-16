import * as Crypto from 'expo-crypto';

export function newId(prefix?: string): string {
  const uuid =
    typeof Crypto.randomUUID === 'function'
      ? Crypto.randomUUID()
      : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 10)}`;
  return prefix ? `${prefix}_${uuid}` : uuid;
}
