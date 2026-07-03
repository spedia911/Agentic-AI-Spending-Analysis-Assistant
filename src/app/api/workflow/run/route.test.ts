import { describe, expect, it } from 'vitest';
import { maxDocumentsFromRequestBody } from './route';

describe('workflow run request options', () => {
  it('accepts empty and valid maxDocuments values', () => {
    expect(maxDocumentsFromRequestBody(undefined)).toBeUndefined();
    expect(maxDocumentsFromRequestBody('')).toBeUndefined();
    expect(maxDocumentsFromRequestBody(1)).toBe(1);
    expect(maxDocumentsFromRequestBody('12')).toBe(12);
  });

  it('rejects invalid maxDocuments values before processing starts', () => {
    expect(() => maxDocumentsFromRequestBody(0)).toThrow('maxDocuments must be a whole number from 1 to 50.');
    expect(() => maxDocumentsFromRequestBody(51)).toThrow('maxDocuments must be a whole number from 1 to 50.');
    expect(() => maxDocumentsFromRequestBody(1.5)).toThrow('maxDocuments must be a whole number from 1 to 50.');
    expect(() => maxDocumentsFromRequestBody('many')).toThrow('maxDocuments must be a whole number from 1 to 50.');
  });
});
