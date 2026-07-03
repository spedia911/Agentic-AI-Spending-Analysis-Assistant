const EMAIL_PATTERN = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi;
const LONG_NUMBER_PATTERN = /\b\d{5,}\b/g;
const KNOWN_SECRET_PATTERN = /\b(?:AIza[0-9A-Za-z_-]{20,}|sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9_]{20,})\b/g;
const KEY_VALUE_SECRET_PATTERN = /\b(api[_-]?key|authorization|bearer|client[_-]?secret|password|private[_-]?key|secret|token)\s*[:=]\s*["']?[^"',\s]+/gi;

export function maskSensitiveText(value: string, maxLength = 240): string {
  return value
    .replace(EMAIL_PATTERN, '[email]')
    .replace(KNOWN_SECRET_PATTERN, '[secret]')
    .replace(KEY_VALUE_SECRET_PATTERN, (_match, label: string) => label + '=[secret]')
    .replace(LONG_NUMBER_PATTERN, '[number]')
    .slice(0, maxLength);
}

export function safeErrorDetail(error: unknown, fallback = 'Unknown error'): string {
  if (error instanceof Error) return maskSensitiveText(error.message);
  if (typeof error === 'string') return maskSensitiveText(error);
  return fallback;
}
