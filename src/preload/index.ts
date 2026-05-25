import { contextBridge, ipcRenderer } from 'electron';
import type { NotificationPreferences } from '../main/preferences';

const api = {
  getStatus: () => ipcRenderer.invoke('roller:getStatus'),
  install: () => ipcRenderer.invoke('roller:install'),
  uninstall: () => ipcRenderer.invoke('roller:uninstall'),
  enable: () => ipcRenderer.invoke('roller:enable'),
  disable: () => ipcRenderer.invoke('roller:disable'),
  refresh: () => ipcRenderer.invoke('roller:refresh'),
  getPreferences: () => ipcRenderer.invoke('preferences:get'),
  savePreferences: (partial: Partial<NotificationPreferences>) => ipcRenderer.invoke('preferences:save', partial),
  minimizeToTray: () => ipcRenderer.invoke('window:minimizeToTray'),
  onStatus: (callback: (status: unknown) => void) => {
    const listener = (_event: Electron.IpcRendererEvent, status: unknown): void => callback(status);
    ipcRenderer.on('roller:status', listener);
    return () => ipcRenderer.removeListener('roller:status', listener);
  }
};

contextBridge.exposeInMainWorld('rollerApi', api);

export type RollerApi = typeof api;
