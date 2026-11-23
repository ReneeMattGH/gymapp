import argon2 from 'argon2';

const OPTIONS: argon2.Options = {
  type: argon2.argon2id,
  memoryCost: 19_456,
  timeCost: 2,
  parallelism: 1,
};

export function hashPassword(password: string): Promise<string> {
  return argon2.hash(password, OPTIONS);
}

export async function verifyPassword(hash: string, password: string): Promise<boolean> {
  try {
    return await argon2.verify(hash, password);
  } catch {
    return false;
  }
}

/**
 * A real hash of a random value, verified when the email is unknown so that a
 * failed login costs the same time whether or not the account exists.
 */
let dummyHash: Promise<string> | undefined;

export async function verifyAgainstDummy(password: string): Promise<false> {
  dummyHash ??= argon2.hash(`dummy-${Math.random()}-${Date.now()}`, OPTIONS);
  await verifyPassword(await dummyHash, password);
  return false;
}
