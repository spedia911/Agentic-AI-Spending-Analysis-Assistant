import { describe, expect, it } from 'vitest';
import { configuredAiModel, defaultAiModelFor, DEFAULT_GEMINI_MODEL, DEFAULT_OPENAI_MODEL } from './defaults';

describe('AI model defaults', () => {
  it('uses the submitted MVP Gemini model by default', () => {
    expect(defaultAiModelFor('gemini')).toBe(DEFAULT_GEMINI_MODEL);
    expect(configuredAiModel({ AI_PROVIDER: 'gemini', AI_MODEL: undefined })).toBe('gemini-2.5-flash');
  });

  it('uses the OpenAI default when OpenAI is configured without an explicit model', () => {
    expect(defaultAiModelFor('openai')).toBe(DEFAULT_OPENAI_MODEL);
    expect(configuredAiModel({ AI_PROVIDER: 'openai', AI_MODEL: '' })).toBe('gpt-4.1-mini');
  });

  it('keeps an explicit configured model', () => {
    expect(configuredAiModel({ AI_PROVIDER: 'gemini', AI_MODEL: 'custom-model' })).toBe('custom-model');
  });
});
