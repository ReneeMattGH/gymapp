const backendEnv = (process.env.EXPO_PUBLIC_DATABASE_BACKEND ?? '').trim().toLowerCase();

export const devPreviewEnabled =
  backendEnv === 'preview' ||
  (process.env.EXPO_PUBLIC_DEV_PREVIEW ?? '0').trim() === '1';

const ceebaseUrl = (process.env.EXPO_PUBLIC_CEEBASE_URL ?? '').trim();

export const ceebaseConfig = {
  url: ceebaseUrl || 'http://127.0.0.1:8080',
  isConfigured:
    !devPreviewEnabled &&
    (backendEnv === 'ceebase' || (Boolean(ceebaseUrl) && backendEnv !== 'supabase')),
};

const supabaseUrl = (process.env.EXPO_PUBLIC_SUPABASE_URL ?? '').trim();
const anonKey = (process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? '').trim();

export const supabaseConfig = {
  url: supabaseUrl,
  anonKey,
  isConfigured: !devPreviewEnabled && Boolean(supabaseUrl && anonKey),
};

export const PREVIEW_USER_ID = 'preview-user';
