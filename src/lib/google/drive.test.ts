import { vi, describe, it, expect, beforeEach } from 'vitest';
import { listDriveScreenshots, downloadDriveFile } from './drive';
import fs from 'fs';
import { Readable } from 'stream';

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
      const mockStream = new Readable();
      mockStream._read = () => {};
      setTimeout(() => {
        mockStream.emit('end');
      }, 10);

      mockFilesGet.mockResolvedValueOnce({
        data: mockStream,
      });

      const mockWriteClose = vi.fn();
      const mockWriteStream = {
        on: vi.fn(function(event, callback) {
          if (event === 'finish') {
            setTimeout(callback, 20);
          }
          return mockWriteStream;
        }),
        close: mockWriteClose,
      };

      vi.spyOn(fs, 'createWriteStream').mockReturnValue(mockWriteStream as any);
      vi.spyOn(fs, 'existsSync').mockReturnValue(true);

      const downloadPromise = downloadDriveFile('file-1', 'path/to/image.png');
      mockStream.push('file-chunk');
      mockStream.push(null);

      await expect(downloadPromise).resolves.toBeUndefined();
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
