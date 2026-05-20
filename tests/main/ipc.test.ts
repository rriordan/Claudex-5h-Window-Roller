// @vitest-environment node
import { describe, expect, it, vi } from 'vitest';
import { registerIpcHandlers } from '../../src/main/ipc';

describe('registerIpcHandlers', () => {
  it('registers the expected command surface', () => {
    const channels: string[] = [];
    const ipcMain = { handle: (channel: string) => channels.push(channel) };
    const adapter = {
      getStatus: vi.fn(),
      install: vi.fn(),
      uninstall: vi.fn(),
      enable: vi.fn(),
      disable: vi.fn(),
      tick: vi.fn()
    };
    const preferences = { load: vi.fn(), save: vi.fn() };
    const monitor = { refreshNow: vi.fn() };

    registerIpcHandlers(ipcMain, adapter, preferences, monitor);

    expect(channels).toEqual([
      'roller:getStatus',
      'roller:install',
      'roller:uninstall',
      'roller:enable',
      'roller:disable',
      'roller:refresh',
      'preferences:get',
      'preferences:save'
    ]);
  });
});
