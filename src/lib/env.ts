import { z } from 'zod';

const envSchema = z.object({
  // Google API Configuration
  GOOGLE_DRIVE_FOLDER_ID: z.string().min(1, 'GOOGLE_DRIVE_FOLDER_ID is required'),
  GOOGLE_SHEET_ID: z.string().min(1, 'GOOGLE_SHEET_ID is required'),
  
  // Either Service Account Key (JSON string or path) or OAuth Client ID + Secret are required.
  // We make them optional here in Zod but we can validate them conditionally.
  GOOGLE_SERVICE_ACCOUNT_KEY: z.string().optional(),
  GOOGLE_OAUTH_CLIENT_ID: z.string().optional(),
  GOOGLE_OAUTH_CLIENT_SECRET: z.string().optional(),
  GOOGLE_REDIRECT_URI: z.string().url().optional().default('http://localhost:3000/api/auth/google/callback'),

  // AI model provider
  AI_PROVIDER: z.enum(['gemini', 'openai', 'anthropic']).default('gemini'),
  AI_MODEL: z.string().optional(),
  AI_API_KEY: z.string().min(1, 'AI_API_KEY is required'),

  // App behavior
  SINGLE_USER_EMAIL: z.string().email('SINGLE_USER_EMAIL must be a valid email'),
  LOW_CONFIDENCE_THRESHOLD: z.coerce.number().min(0).max(1).default(0.75),
  TIMEZONE: z.string().default('America/Los_Angeles'),
  SOURCE_IMAGE_RETENTION_DAYS: z.coerce.number().int().positive().default(30),
  
  // Node Env
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
});

export type Env = z.infer<typeof envSchema>;

export function parseEnv(rawEnv: Record<string, string | undefined> = process.env): Env {
  const result = envSchema.safeParse(rawEnv);

  if (!result.success) {
    console.error('Invalid environment variables:', JSON.stringify(result.error.format(), null, 2));
    throw new Error('Invalid environment variables');
  }

  // Cross-validation check: Need either Google Service Account Key OR OAuth credentials
  const data = result.data;
  if (!data.GOOGLE_SERVICE_ACCOUNT_KEY && (!data.GOOGLE_OAUTH_CLIENT_ID || !data.GOOGLE_OAUTH_CLIENT_SECRET)) {
    console.error('Environment configuration error: Either GOOGLE_SERVICE_ACCOUNT_KEY or both GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET must be provided.');
    throw new Error('Invalid credentials configuration');
  }

  return data;
}

let parsedEnv: Env;

export function getEnv(): Env {
  // In a Next.js server environment, load env.
  // In client component/bundle this will be empty, so env validation should only run on the server side.
  if (typeof window !== 'undefined') {
    throw new Error('getEnv() can only be called on the server side.');
  }
  
  if (!parsedEnv) {
    parsedEnv = parseEnv();
  }
  return parsedEnv;
}
