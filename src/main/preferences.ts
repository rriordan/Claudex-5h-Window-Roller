import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname } from 'node:path';

export type NotificationPreferences = {
  schemaVersion: 1;
  timeLeftNotifications: boolean;
  timeLeftMinutes: number;
  windowEndingNotifications: boolean;
  windowEndingMinutes: number;
  quotaMessageNotifications: boolean;
};

export const defaultPreferences: NotificationPreferences = {
  schemaVersion: 1,
  timeLeftNotifications: true,
  timeLeftMinutes: 30,
  windowEndingNotifications: true,
  windowEndingMinutes: 10,
  quotaMessageNotifications: true
};

export class PreferencesStore {
  constructor(private readonly filePath: string) {}

  async load(): Promise<NotificationPreferences> {
    try {
      const raw = await readFile(this.filePath, 'utf8');
      const parsed = JSON.parse(raw) as Partial<NotificationPreferences>;
      return { ...defaultPreferences, ...parsed, schemaVersion: 1 };
    } catch {
      return defaultPreferences;
    }
  }

  async save(partial: Partial<NotificationPreferences>): Promise<NotificationPreferences> {
    const next: NotificationPreferences = { ...(await this.load()), ...partial, schemaVersion: 1 };
    await mkdir(dirname(this.filePath), { recursive: true });
    await writeFile(this.filePath, `${JSON.stringify(next, null, 2)}\n`, 'utf8');
    return next;
  }
}
