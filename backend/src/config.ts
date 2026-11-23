import 'dotenv/config';
import { z } from 'zod';

const configSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(8787),
  HOST: z.string().min(1).default('0.0.0.0'),
  DATABASE_URL: z.string().min(1, 'DATABASE_URL is required'),
  ACCESS_TOKEN_TTL_MINUTES: z.coerce.number().int().positive().default(60),
  REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().positive().default(30),
  CORS_ORIGINS: z.string().default(''),
  SMTP_URL: z.string().url().optional(),
  MAIL_FROM: z.string().min(1).default('Forma <no-reply@example.com>'),
  APP_LINK_BASE: z.string().min(1).default('forma://auth'),
  COMMUNITY_ADMIN_EMAILS: z.string().default(''),
  UPLOAD_DIR: z.string().min(1).default('./uploads'),
  PUBLIC_BASE_URL: z.string().url().optional(),
  AUTO_MIGRATE: z
    .enum(['true', 'false'])
    .default('true')
    .transform((value) => value === 'true'),
  TRUST_PROXY: z.coerce.number().int().min(0).default(0),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace', 'silent']).default('info'),
});

export interface Config {
  nodeEnv: 'development' | 'test' | 'production';
  port: number;
  host: string;
  databaseUrl: string;
  accessTokenTtlMinutes: number;
  refreshTokenTtlDays: number;
  corsOrigins: string[];
  smtpUrl?: string;
  mailFrom: string;
  appLinkBase: string;
  communityAdminEmails: string[];
  uploadDir: string;
  publicBaseUrl?: string;
  autoMigrate: boolean;
  trustProxy: number;
  logLevel: string;
}

export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const parsed = configSchema.safeParse(env);
  if (!parsed.success) {
    const details = parsed.error.issues
      .map((issue) => `${issue.path.join('.') || 'env'}: ${issue.message}`)
      .join('; ');
    throw new Error(`Invalid configuration: ${details}`);
  }
  const value = parsed.data;
  return {
    nodeEnv: value.NODE_ENV,
    port: value.PORT,
    host: value.HOST,
    databaseUrl: value.DATABASE_URL,
    accessTokenTtlMinutes: value.ACCESS_TOKEN_TTL_MINUTES,
    refreshTokenTtlDays: value.REFRESH_TOKEN_TTL_DAYS,
    corsOrigins: value.CORS_ORIGINS.split(',')
      .map((origin) => origin.trim())
      .filter(Boolean),
    ...(value.SMTP_URL ? { smtpUrl: value.SMTP_URL } : {}),
    mailFrom: value.MAIL_FROM,
    appLinkBase: value.APP_LINK_BASE.replace(/\/+$/, ''),
    communityAdminEmails: value.COMMUNITY_ADMIN_EMAILS.split(',')
      .map((email) => email.trim().toLowerCase())
      .filter(Boolean),
    uploadDir: value.UPLOAD_DIR,
    ...(value.PUBLIC_BASE_URL ? { publicBaseUrl: value.PUBLIC_BASE_URL.replace(/\/+$/, '') } : {}),
    autoMigrate: value.AUTO_MIGRATE,
    trustProxy: value.TRUST_PROXY,
    logLevel: value.LOG_LEVEL,
  };
}
