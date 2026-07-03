import { describe, expect, it } from 'vitest';
import { maskSensitiveText, safeErrorDetail } from './redact';

describe('privacy redaction helpers', () => {
  it('masks emails, long numbers, and common secret-shaped values', () => {
    expect(
      maskSensitiveText(
        'Request failed for user@example.com account 123456789 with api_key=AIzaSyDemoSecretValue1234567890 and token=plain-secret'
      )
    ).toBe('Request failed for [email] account [number] with api_key=[secret] and token=[secret]');
  });

  it('limits user-visible details to a short message', () => {
    expect(maskSensitiveText('x'.repeat(300))).toHaveLength(240);
  });

  it('builds safe details from unknown thrown values', () => {
    expect(safeErrorDetail(new Error('403 folder not shared with person@example.com'))).toBe('403 folder not shared with [email]');
    expect(safeErrorDetail('token=abc123')).toBe('token=[secret]');
    expect(safeErrorDetail({})).toBe('Unknown error');
  });
});
