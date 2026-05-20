// @vitest-environment jsdom
import '@testing-library/jest-dom/vitest';
import { cleanup, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { App } from '../../src/renderer/App';
import type { RollerStatus } from '../../src/main/platform/types';
import { defaultPreferences } from '../../src/main/preferences';

function status(overrides: Partial<RollerStatus>): RollerStatus {
  return {
    taskName: 'Claudex5hWindowRoller',
    installed: false,
    enabled: false,
    supported: true,
    platform: 'win32',
    taskState: null,
    windowMinutes: 300,
    pingLeadSeconds: 90,
    stateDir: null,
    logFile: null,
    checkedAt: '2026-05-20T00:00:00.000Z',
    clients: [],
    ...overrides
  };
}

function mockApi(nextStatus: RollerStatus): void {
  window.rollerApi = {
    getStatus: vi.fn().mockResolvedValue(nextStatus),
    install: vi.fn(),
    uninstall: vi.fn(),
    enable: vi.fn(),
    disable: vi.fn(),
    refresh: vi.fn().mockResolvedValue(nextStatus),
    getPreferences: vi.fn().mockResolvedValue(defaultPreferences),
    savePreferences: vi.fn().mockResolvedValue(defaultPreferences),
    onStatus: vi.fn().mockReturnValue(() => undefined)
  };
}

describe('App controls', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    cleanup();
  });

  it('enables install only when the roller is not installed', async () => {
    mockApi(status({ installed: false, enabled: false }));
    render(<App />);

    await waitFor(() => expect(screen.getByText('Status refreshed')).toBeInTheDocument());
    expect(screen.getByRole('button', { name: /^install$/i })).toBeEnabled();
    expect(screen.getByRole('button', { name: /^uninstall$/i })).toBeDisabled();
    expect(screen.getByRole('button', { name: /^enable/i })).toBeDisabled();
    expect(screen.getByRole('button', { name: /^disable/i })).toBeDisabled();
  });

  it('enables uninstall and disable when installed and enabled', async () => {
    mockApi(status({ installed: true, enabled: true }));
    render(<App />);

    await waitFor(() => expect(screen.getByText('Status refreshed')).toBeInTheDocument());
    expect(screen.getByRole('button', { name: /^install$/i })).toBeDisabled();
    expect(screen.getByRole('button', { name: /^uninstall$/i })).toBeEnabled();
    expect(screen.getByRole('button', { name: /^enable/i })).toBeDisabled();
    expect(screen.getByRole('button', { name: /^disable/i })).toBeEnabled();
  });

  it('enables uninstall and enable when installed and disabled', async () => {
    mockApi(status({ installed: true, enabled: false }));
    render(<App />);

    await waitFor(() => expect(screen.getByText('Status refreshed')).toBeInTheDocument());
    expect(screen.getByRole('button', { name: /^install$/i })).toBeDisabled();
    expect(screen.getByRole('button', { name: /^uninstall$/i })).toBeEnabled();
    expect(screen.getByRole('button', { name: /^enable/i })).toBeEnabled();
    expect(screen.getByRole('button', { name: /^disable/i })).toBeDisabled();
  });

  it('disables operations on unsupported platforms', async () => {
    mockApi(status({ supported: false, platform: 'darwin' }));
    render(<App />);

    await waitFor(() => expect(screen.getByText('Status refreshed')).toBeInTheDocument());
    expect(screen.getByRole('button', { name: /^install$/i })).toBeDisabled();
    expect(screen.getByRole('button', { name: /^uninstall$/i })).toBeDisabled();
    expect(screen.getByRole('button', { name: /^enable/i })).toBeDisabled();
    expect(screen.getByRole('button', { name: /^disable/i })).toBeDisabled();
  });
});
