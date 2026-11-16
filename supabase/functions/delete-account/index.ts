import { adminClient, authenticate, AuthError } from '../_shared/auth.ts';
import { json, methodNotAllowed, preflight } from '../_shared/http.ts';

Deno.serve(async (request: Request) => {
  const options = preflight(request);
  if (options) return options;
  if (request.method !== 'POST') return methodNotAllowed();

  try {
    const { user } = await authenticate(request);
    if (!user.email) {
      return json({ error: 'This account cannot be deleted from the app.' }, 400);
    }

    const { error } = await adminClient().auth.admin.deleteUser(user.id);
    if (error) {
      console.error('delete-account failed', error.message);
      return json({ error: 'The account could not be deleted. Please try again.' }, 500);
    }

    return json({ ok: true });
  } catch (error) {
    if (error instanceof AuthError) return json({ error: error.message }, 401);
    console.error('delete-account failed', error instanceof Error ? error.message : 'unknown');
    return json({ error: 'The account could not be deleted. Please try again.' }, 500);
  }
});
