export function authErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error ?? '');
  const lower = message.toLowerCase();

  if (lower.includes('invalid login credentials')) {
    return 'That email and password do not match an account.';
  }
  if (lower.includes('email not confirmed')) {
    return 'Confirm your email first. Check your inbox for the link we sent.';
  }
  if (lower.includes('user already registered')) {
    return 'An account already exists for that email. Try signing in instead.';
  }
  if (lower.includes('rate limit') || lower.includes('too many requests')) {
    return 'Too many attempts. Wait a moment and try again.';
  }
  if (lower.includes('password should be at least')) {
    return 'Use a password with at least 8 characters.';
  }
  if (lower.includes('unable to validate email') || lower.includes('invalid email')) {
    return 'Enter a valid email address.';
  }
  if (lower.includes('network') || lower.includes('fetch')) {
    return 'We could not reach the server. Check your connection and try again.';
  }
  return message || 'Something went wrong. Please try again.';
}
