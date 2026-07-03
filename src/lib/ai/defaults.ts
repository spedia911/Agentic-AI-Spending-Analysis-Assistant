import type { Env } from '../env';

export const DEFAULT_GEMINI_MODEL = 'gemini-2.5-flash';
export const DEFAULT_OPENAI_MODEL = 'gpt-4.1-mini';

export function defaultAiModelFor(provider: Env['AI_PROVIDER']): string {
  if (provider === 'gemini') return DEFAULT_GEMINI_MODEL;
  if (provider === 'openai') return DEFAULT_OPENAI_MODEL;
  return '';
}

export function configuredAiModel(env: Pick<Env, 'AI_PROVIDER' | 'AI_MODEL'>): string {
  const explicitModel = env.AI_MODEL?.trim();
  return explicitModel || defaultAiModelFor(env.AI_PROVIDER);
}
