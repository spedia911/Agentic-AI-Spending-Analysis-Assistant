import { getEnv, parseEnv, type Env } from '../env';
import { configuredAiModel } from '../ai/defaults';
import { listDriveFolderFiles, isSupportedDriveImage, type DriveFileMetadata } from '../google/drive';
import { initializeSpreadsheet } from '../google/sheets';
import { safeErrorDetail } from '../privacy/redact';

export type SetupHealthStatus = 'ok' | 'warning' | 'error';

export interface SetupHealthItem {
  id: string;
  label: string;
  status: SetupHealthStatus;
  message: string;
  detail?: string;
}

export interface SetupHealthReport {
  status: SetupHealthStatus;
  checkedAt: string;
  items: SetupHealthItem[];
}

interface SetupHealthDependencies {
  env?: Env;
  rawEnv?: Record<string, string | undefined>;
  now?: string;
  initializeSpreadsheet?: (sheetId: string) => Promise<string>;
  listDriveFolderFiles?: (folderId: string) => Promise<DriveFileMetadata[]>;
}

function maskValue(value: string): string {
  if (!value) return '';
  if (value.length <= 8) return '[set]';
  return value.slice(0, 4) + '...' + value.slice(-4);
}

function item(id: string, label: string, status: SetupHealthStatus, message: string, detail?: string): SetupHealthItem {
  return { id, label, status, message, detail };
}

function overallStatus(items: SetupHealthItem[]): SetupHealthStatus {
  if (items.some((healthItem) => healthItem.status === 'error')) return 'error';
  if (items.some((healthItem) => healthItem.status === 'warning')) return 'warning';
  return 'ok';
}

function aiModelFor(env: Env): string {
  return configuredAiModel(env);
}

function aiHealth(env: Env): SetupHealthItem {
  const model = aiModelFor(env);
  if (env.AI_PROVIDER === 'anthropic') {
    return item(
      'ai',
      'AI extraction',
      'error',
      'Anthropic is configured, but this MVP only implements Gemini and OpenAI screenshot adapters.',
      'Set AI_PROVIDER to gemini or openai, or add an Anthropic vision adapter before running extraction.'
    );
  }

  return item(
    'ai',
    'AI extraction',
    env.AI_MODEL ? 'ok' : 'warning',
    env.AI_PROVIDER + ' is configured with model ' + model + '.',
    env.AI_MODEL ? undefined : 'AI_MODEL is blank, so the app will use its built-in default for this provider.'
  );
}

export async function runSetupHealthCheck(dependencies: SetupHealthDependencies = {}): Promise<SetupHealthReport> {
  const checkedAt = dependencies.now ?? new Date().toISOString();
  const items: SetupHealthItem[] = [];
  let env: Env | null = dependencies.env ?? null;

  if (!env) {
    try {
      env = dependencies.rawEnv ? parseEnv(dependencies.rawEnv) : getEnv();
      items.push(item('env', 'Environment file', 'ok', 'Required environment values are present and parseable.'));
    } catch (error) {
      items.push(item('env', 'Environment file', 'error', 'Required environment values are missing or invalid.', safeErrorDetail(error)));
      return {
        status: overallStatus(items),
        checkedAt,
        items,
      };
    }
  } else {
    items.push(item('env', 'Environment file', 'ok', 'Required environment values are present and parseable.'));
  }

  items.push(
    item(
      'user',
      'Single-user email',
      'ok',
      'Dashboard access is restricted to the configured single-user email.',
      'Configured email: ' + env.SINGLE_USER_EMAIL.replace(/(.).+(@.+)/, '$1***$2')
    )
  );

  if (env.GOOGLE_SERVICE_ACCOUNT_KEY) {
    items.push(
      item(
        'google_credentials',
        'Google credentials',
        'ok',
        'Google service-account credentials are configured.',
        'GOOGLE_SERVICE_ACCOUNT_KEY=' + maskValue(env.GOOGLE_SERVICE_ACCOUNT_KEY)
      )
    );
  } else {
    items.push(
      item(
        'google_credentials',
        'Google credentials',
        'warning',
        'OAuth credentials are configured, but this MVP path is tested most heavily with service-account credentials.'
      )
    );
  }

  try {
    const files = await (dependencies.listDriveFolderFiles ?? listDriveFolderFiles)(env.GOOGLE_DRIVE_FOLDER_ID);
    const supportedCount = files.filter((file) => isSupportedDriveImage(file.mimeType)).length;
    const unsupportedCount = files.length - supportedCount;
    items.push(
      item(
        'drive',
        'Drive folder access',
        'ok',
        'Drive folder is reachable with ' + supportedCount + ' supported screenshot file(s).',
        unsupportedCount > 0 ? unsupportedCount + ' unsupported file(s) will be skipped.' : undefined
      )
    );
  } catch (error) {
    items.push(
      item(
        'drive',
        'Drive folder access',
        'error',
        'Unable to list files in the configured Drive folder.',
        safeErrorDetail(error)
      )
    );
  }

  try {
    const sheetId = await (dependencies.initializeSpreadsheet ?? initializeSpreadsheet)(env.GOOGLE_SHEET_ID);
    items.push(
      item(
        'sheets',
        'Google Sheet access',
        'ok',
        'Google Sheet is reachable and MVP tabs can be verified.',
        'Sheet ' + maskValue(sheetId)
      )
    );
  } catch (error) {
    items.push(
      item(
        'sheets',
        'Google Sheet access',
        'error',
        'Unable to open or verify the configured Google Sheet.',
        safeErrorDetail(error)
      )
    );
  }

  items.push(aiHealth(env));

  return {
    status: overallStatus(items),
    checkedAt,
    items,
  };
}
