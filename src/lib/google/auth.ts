import { google } from 'googleapis';
import fs from 'fs';
import path from 'path';
import { getEnv } from '../env';

/**
 * Creates and returns an authenticated JWT client for Google Drive and Google Sheets APIs
 * using a Service Account credential.
 */
export function getGoogleAuthClient() {
  const env = getEnv();
  
  let credentials: { client_email?: string; private_key?: string } | null = null;

  // 1. Try to load from GOOGLE_SERVICE_ACCOUNT_KEY env variable
  if (env.GOOGLE_SERVICE_ACCOUNT_KEY) {
    try {
      // Check if it is a JSON string
      credentials = JSON.parse(env.GOOGLE_SERVICE_ACCOUNT_KEY);
    } catch {
      // Otherwise, assume it is a file path
      const filePath = path.resolve(process.cwd(), env.GOOGLE_SERVICE_ACCOUNT_KEY);
      if (fs.existsSync(filePath)) {
        try {
          const fileContent = fs.readFileSync(filePath, 'utf-8');
          credentials = JSON.parse(fileContent);
        } catch (err) {
          throw new Error(`Failed to parse Service Account JSON file at ${filePath}: ${(err as Error).message}`);
        }
      }
    }
  }

  // 2. If not loaded, fallback to checking for a local service-account.json in the project root
  if (!credentials) {
    const defaultSA = path.join(process.cwd(), 'service-account.json');
    if (fs.existsSync(defaultSA)) {
      try {
        const fileContent = fs.readFileSync(defaultSA, 'utf-8');
        credentials = JSON.parse(fileContent);
      } catch (err) {
        throw new Error(`Failed to parse default service-account.json: ${(err as Error).message}`);
      }
    }
  }

  if (credentials && credentials.client_email && credentials.private_key) {
    return new google.auth.JWT({
      email: credentials.client_email,
      // Handle escaped newlines in env-injected keys
      key: credentials.private_key.replace(/\\n/g, '\n'),
      scopes: [
        'https://www.googleapis.com/auth/drive.readonly',
        'https://www.googleapis.com/auth/spreadsheets',
      ],
    });
  }

  throw new Error('No valid Google Service Account credentials found. Please set GOOGLE_SERVICE_ACCOUNT_KEY or add service-account.json.');
}
