import { CeeBaseRepository } from './CeeBaseRepository';
import { PreviewRepository } from './PreviewRepository';
import { SupabaseRepository } from './SupabaseRepository';
import type { GymRepository } from './repository';
import { ceebaseConfig, devPreviewEnabled, supabaseConfig } from '@/lib/env';

export const isCeeBase = !devPreviewEnabled && ceebaseConfig.isConfigured;

export const setupRequired =
  !devPreviewEnabled && !ceebaseConfig.isConfigured && !supabaseConfig.isConfigured;

export const repository: GymRepository = devPreviewEnabled
  ? new PreviewRepository()
  : ceebaseConfig.isConfigured
  ? new CeeBaseRepository(ceebaseConfig.url)
  : supabaseConfig.isConfigured
  ? new SupabaseRepository()
  : new PreviewRepository();

export const isPreviewMode = repository.kind === 'preview';

export { CeeBaseRepository };
export type { GymRepository };
