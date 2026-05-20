import type { NotificationPreferences } from './preferences';
import type { PlatformAdapter } from './platform/types';

type IpcMainLike = {
  handle(channel: string, listener: (event: unknown, ...args: unknown[]) => unknown): void;
};

type PreferencesLike = {
  load(): Promise<NotificationPreferences>;
  save(partial: Partial<NotificationPreferences>): Promise<NotificationPreferences>;
};

type MonitorLike = {
  refreshNow(): Promise<unknown>;
};

export function registerIpcHandlers(
  ipcMain: IpcMainLike,
  adapter: PlatformAdapter,
  preferences: PreferencesLike,
  monitor: MonitorLike
): void {
  ipcMain.handle('roller:getStatus', () => adapter.getStatus());
  ipcMain.handle('roller:install', () => adapter.install());
  ipcMain.handle('roller:uninstall', () => adapter.uninstall());
  ipcMain.handle('roller:enable', () => adapter.enable());
  ipcMain.handle('roller:disable', () => adapter.disable());
  ipcMain.handle('roller:refresh', () => monitor.refreshNow());
  ipcMain.handle('preferences:get', () => preferences.load());
  ipcMain.handle('preferences:save', (_event, partial) => preferences.save(partial as Partial<NotificationPreferences>));
}
