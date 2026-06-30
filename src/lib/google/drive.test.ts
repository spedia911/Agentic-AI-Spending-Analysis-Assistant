import { vi, describe, it, expect, beforeEach } from 'vitest';
import { listDriveScreenshots, downloadDriveFile } from './drive';
import fs, { type WriteStream } from 'fs';
import { Readable, Writable } from 'stream';

// Mock auth client
vi.mock('./auth', () => ({
  getGoogleAuthClient: vi.fn(() => ({})),
}));

// Mock process.env config
vi.mock('../env', () => ({
  getEnv: vi.fn(() => ({
    GOOGLE_DRIVE_FOLDER_ID: 'folder-123',
    GOOGLE_SHEET_ID: 'sheet-123',
    AI_API_KEY: 'key-xyz',
    SINGLE_USER_EMAIL: 'user@example.com',
  })),
}));

const mockFilesList = vi.fn();
const mockFilesGet = vi.fn();

vi.mock('googleapis', () => ({
  google: {
    drive: () => ({
      files: {
        list: mockFilesList,
        get: mockFilesGet,
      },
    }),
  },
}));

vi.mock('fs', () => ({
  default: {
    existsSync: vi.fn(),
    mkdirSync: vi.fn(),
    createWriteStream: vi.fn(),
  },
  existsSync: vi.fn(),
  mkdirSync: vi.fn(),
  createWriteStream: vi.fn(),
}));

describe('Google Drive Module', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('listDriveScreenshots', () => {
    it('queries drive folder for image files', async () => {
      mockFilesList.mockResolvedValueOnce({
        data: {
          files: [
            {
              id: 'file-1',
              name: 'screenshot1.png',
              mimeType: 'image/png',
              createdTime: '2026-06-28T12:00:00Z',
              modifiedTime: '2026-06-28T12:00:00Z',
            },
          ],
        },
      });

      const files = await listDriveScreenshots('folder-123');
      expect(files).toHaveLength(1);
      expect(files[0].id).toBe('file-1');
      expect(mockFilesList).toHaveBeenCalledWith(
        expect.objectContaining({
          q: expect.stringContaining("'folder-123' in parents"),
          fields: expect.stringContaining('files(id, name, mimeType'),
        })
      );
    });
  });

  describe('downloadDriveFile', () => {
    it('downloads drive file and pipes stream', async () => {
      const mockStream = Readable.from(['file-chunk']);

      mockFilesGet.mockResolvedValueOnce({
        data: mockStream,
      });

      const writtenChunks: Buffer[] = [];
      const mockWriteStream = Object.assign(
        new Writable({
          write(chunk: Buffer | string, _encoding, callback) {
            writtenChunks.push(Buffer.from(chunk));
            callback();
          },
        }),
        { close: vi.fn() }
      );

      vi.spyOn(fs, 'createWriteStream').mockReturnValue(mockWriteStream as unknown as WriteStream);
      vi.spyOn(fs, 'existsSync').mockReturnValue(true);

      const downloadPromise = downloadDriveFile('file-1', 'path/to/image.png');

      await expect(downloadPromise).resolves.toBeUndefined();
      expect(Buffer.concat(writtenChunks).toString()).toBe('file-chunk');
      expect(mockFilesGet).toHaveBeenCalledWith(
        expect.objectContaining({
          fileId: 'file-1',
          alt: 'media',
        }),
        expect.objectContaining({
          responseType: 'stream',
        })
      );
    });
  });
});
