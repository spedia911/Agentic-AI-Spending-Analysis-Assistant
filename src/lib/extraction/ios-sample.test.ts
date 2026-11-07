import { readFileSync } from 'fs';
import { resolve } from 'path';
import { describe, expect, it } from 'vitest';
import { screenshotExtractionResultSchema } from './schema';

describe('iOS sample extraction JSON', () => {
  it('matches the shared extraction contract used by the iOS AI-import path', () => {
    const samplePath = resolve(process.cwd(), 'ios/SpendingAssistant/Resources/sample-extraction.json');
    const raw = JSON.parse(readFileSync(samplePath, 'utf8'));
    const parsed = screenshotExtractionResultSchema.parse(raw);
    expect(parsed.transactions.length).toBeGreaterThan(0);
    expect(parsed.asset_snapshots.length).toBeGreaterThan(0);
    expect(parsed.screenshot_kind).toBe('credit_card');
  });
});
