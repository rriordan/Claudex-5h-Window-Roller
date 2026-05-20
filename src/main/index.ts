import { app, BrowserWindow, ipcMain, Menu, nativeImage, Notification, Tray } from 'electron';
import { join } from 'node:path';
import { registerIpcHandlers } from './ipc';
import { RollerMonitor } from './monitor';
import { PreferencesStore } from './preferences';
import { createUnsupportedAdapter } from './platform/unsupported';
import { createWindowsAdapter } from './platform/windows';
import type { PlatformAdapter, RollerStatus } from './platform/types';

let mainWindow: BrowserWindow | null = null;
let tray: Tray | null = null;
let isQuitting = false;
let latestStatus: RollerStatus | null = null;

function getScriptPath(): string {
  if (app.isPackaged) return join(process.resourcesPath, 'claudex-roller.ps1');
  return join(app.getAppPath(), 'claudex-roller.ps1');
}

function createAdapter(): PlatformAdapter {
  if (process.platform !== 'win32') return createUnsupportedAdapter(process.platform);
  return createWindowsAdapter({ scriptPath: getScriptPath() });
}

function createWindow(): BrowserWindow {
  const win = new BrowserWindow({
    width: 980,
    height: 680,
    minWidth: 760,
    minHeight: 560,
    title: 'Claudex 5h Window Roller',
    backgroundColor: '#f6f3ed',
    webPreferences: {
      preload: join(__dirname, '../preload/index.mjs'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  win.on('close', (event) => {
    if (isQuitting) return;
    event.preventDefault();
    win.hide();
  });

  if (process.env.ELECTRON_RENDERER_URL) {
    void win.loadURL(process.env.ELECTRON_RENDERER_URL);
  } else {
    void win.loadFile(join(__dirname, '../renderer/index.html'));
  }

  return win;
}

function updateTray(adapter: PlatformAdapter, monitor: RollerMonitor): void {
  if (!tray) return;
  const state = latestStatus
    ? `${latestStatus.installed ? 'Installed' : 'Not installed'} / ${latestStatus.enabled ? 'Enabled' : 'Disabled'}`
    : 'Status pending';
  const timeLeft = latestStatus?.clients.find((client) => client.secondsLeft !== null)?.secondsLeft;
  const minutesLeft = typeof timeLeft === 'number' ? ` / ${Math.max(0, Math.floor(timeLeft / 60))}m left` : '';

  tray.setToolTip(`Claudex Roller - ${state}${minutesLeft}`);
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'Open Claudex Roller', click: () => mainWindow?.show() },
    { label: `${state}${minutesLeft}`, enabled: false },
    { type: 'separator' },
    {
      label: latestStatus?.enabled ? 'Disable' : 'Enable',
      enabled: latestStatus?.installed ?? false,
      click: async () => {
        if (latestStatus?.enabled) await adapter.disable();
        else await adapter.enable();
        await monitor.refreshNow();
      }
    },
    { label: 'Refresh now', click: () => void monitor.refreshNow() },
    { type: 'separator' },
    {
      label: 'Quit',
      click: () => {
        isQuitting = true;
        app.quit();
      }
    }
  ]));
}

app.setAppUserModelId('com.rriordan.claudex-5h-window-roller');

void app.whenReady().then(() => {
  const adapter = createAdapter();
  const preferences = new PreferencesStore(join(app.getPath('userData'), 'preferences.json'));
  const monitor = new RollerMonitor(
    adapter,
    () => preferences.load(),
    {
      notify: (event) => {
        if (!Notification.isSupported()) return;
        new Notification({ title: event.title, body: event.body }).show();
      }
    },
    (status) => {
      latestStatus = status;
      mainWindow?.webContents.send('roller:status', status);
      updateTray(adapter, monitor);
    }
  );

  registerIpcHandlers(ipcMain, adapter, preferences, monitor);
  mainWindow = createWindow();
  tray = new Tray(nativeImage.createEmpty());
  updateTray(adapter, monitor);
  monitor.start();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) mainWindow = createWindow();
    else mainWindow?.show();
  });
});

app.on('window-all-closed', () => {});
