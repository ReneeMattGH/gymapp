const url = (process.env.EXPO_PUBLIC_SUPABASE_URL ?? '').trim();
const anonKey = (process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY ?? '').trim();

export const supabaseConfig = {
  url,
  anonKey,
  isConfigured: Boolean(url && anonKey),
};

export const devPreviewEnabled =
  __DEV__ && (process.env.EXPO_PUBLIC_DEV_PREVIEW ?? '0').trim() === '1';

export const PREVIEW_USER_ID = 'preview-user';
