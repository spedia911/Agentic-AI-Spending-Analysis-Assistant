import { google } from 'googleapis';
import fs from 'fs';
import path from 'path';
import { getGoogleAuthClient } from './auth';

export interface DriveFileMetadata {
  id: string;
  name: string;
  mimeType: string;
  createdTime: string;
  modifiedTime: string;
}

export function isSupportedDriveImage(mimeType: string): boolean {
  return ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'].includes(mimeType);
}

/**
 * Lists files in the configured Google Drive folder.
 */
export async function listDriveFolderFiles(folderId: string): Promise<DriveFileMetadata[]> {
  const auth = getGoogleAuthClient();
  const drive = google.drive({ version: 'v3', auth });

  console.log(`[Drive] Listing files in configured folder.`);
  
  const query = `'${folderId}' in parents and trashed = false`;
  const response = await drive.files.list({
    q: query,
    fields: 'files(id, name, mimeType, createdTime, modifiedTime)',
    orderBy: 'createdTime asc',
  });

  const files = response.data.files || [];
  
  return files.map((file) => ({
    id: file.id || '',
    name: file.name || '',
    mimeType: file.mimeType || '',
    createdTime: file.createdTime || new Date().toISOString(),
    modifiedTime: file.modifiedTime || new Date().toISOString(),
  }));
}

/**
 * Lists supported screenshot image files in the configured Google Drive folder.
 */
export async function listDriveScreenshots(folderId: string): Promise<DriveFileMetadata[]> {
  const files = await listDriveFolderFiles(folderId);
  return files.filter((file) => isSupportedDriveImage(file.mimeType));
}

/**
 * Downloads a file from Google Drive and saves it to a local destination path.
 */
export async function downloadDriveFile(fileId: string, destPath: string): Promise<void> {
  const auth = getGoogleAuthClient();
  const drive = google.drive({ version: 'v3', auth });

  // Ensure destination directory exists
  const destDir = path.dirname(destPath);
  if (!fs.existsSync(destDir)) {
    fs.mkdirSync(destDir, { recursive: true });
  }

  console.log(`[Drive] Downloading file ${fileId} -> ${destPath}`);

  const response = await drive.files.get(
    { fileId, alt: 'media' },
    { responseType: 'stream' }
  );

  return new Promise((resolve, reject) => {
    const destStream = fs.createWriteStream(destPath);
    
    response.data
      .on('error', (err) => {
        destStream.close();
        reject(err);
      })
      .pipe(destStream);

    destStream
      .on('finish', () => {
        resolve();
      })
      .on('error', (err) => {
        reject(err);
      });
  });
}
