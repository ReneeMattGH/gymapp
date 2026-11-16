import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

import { requireEnv } from './http.ts';

export type AuthedUser = { id: string; email: string | null };

/**
 * Creates a Supabase client bound to the caller's access token.
 * The service role key is only used for operations the user cannot perform
 * from the client (account deletion).
 */
export function userClient(request: Request): SupabaseClient {
  const url = requireEnv('SUPABASE_URL');
  const anonKey = requireEnv('SUPABASE_ANON_KEY');
  const authorization = request.headers.get('Authorization');
  if (!authorization) throw new AuthError('Sign in again to use this feature.');
  return createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export function adminClient(): SupabaseClient {
  const url = requireEnv('SUPABASE_URL');
  const serviceRole = requireEnv('SUPABASE_SERVICE_ROLE_KEY');
  return createClient(url, serviceRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

export class AuthError extends Error {}

export async function authenticate(request: Request): Promise<{
  client: SupabaseClient;
  user: AuthedUser;
}> {
  const client = userClient(request);
  const { data, error } = await client.auth.getUser();
  if (error || !data.user) throw new AuthError('Your session has expired. Sign in again.');
  return {
    client,
    user: { id: data.user.id, email: data.user.email ?? null },
  };
}
