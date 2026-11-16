import { PreviewRepository } from './PreviewRepository';
import { SupabaseRepository } from './SupabaseRepository';
import type { GymRepository } from './repository';
import { devPreviewEnabled, supabaseConfig } from '@/lib/env';

export const setupRequired = !supabaseConfig.isConfigured && !devPreviewEnabled;

export const repository: GymRepository = supabaseConfig.isConfigured
  ? new SupabaseRepository()
  : new PreviewRepository();

export const isPreviewMode = repository.kind === 'preview';

export type { GymRepository };
