// @vitest-environment jsdom
import '@testing-library/jest-dom/vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
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
    minimizeToTray: vi.fn().mockResolvedValue(undefined),
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

  it('shows command stderr when install fails', async () => {
    mockApi(status({ installed: false, enabled: false }));
    window.rollerApi.install = vi.fn().mockResolvedValue({
      ok: false,
      stdout: '',
      stderr: 'Register-ScheduledTask : Access is denied.',
      error: 'Command failed'
    });
    render(<App />);

    await waitFor(() => expect(screen.getByText('Status refreshed')).toBeInTheDocument());
    fireEvent.click(screen.getByRole('button', { name: /^install$/i }));

    await waitFor(() => expect(screen.getByText('Register-ScheduledTask : Access is denied.')).toBeInTheDocument());
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

  it('shows task state and client timing details', async () => {
    mockApi(status({
      installed: true,
      enabled: true,
      taskState: 'Ready',
      clients: [
        {
          name: 'codex',
          userDisabled: false,
          installed: true,
          sources: ['WSL (Ubuntu)', 'PATH'],
          activeSource: 'WSL (Ubuntu)',
          windowStart: '2026-05-20T00:00:00.000Z',
          windowEnd: '2026-05-20T05:00:00.000Z',
          secondsLeft: 5400,
          pingInSeconds: 120,
          lastPingAt: '2026-05-20T04:00:00.000Z',
          error: null
        }
      ]
    }));
    render(<App />);

    await waitFor(() => expect(screen.getByText('Status refreshed')).toBeInTheDocument());
    expect(screen.getByText('Installed, enabled')).toBeInTheDocument();
    expect(screen.getByText('Ready')).toBeInTheDocument();
    expect(screen.getAllByText('WSL (Ubuntu)').length).toBeGreaterThan(0);
    expect(screen.getByText('Window end')).toBeInTheDocument();
    expect(screen.getByText('Next ping')).toBeInTheDocument();
    expect(screen.getByText('2m')).toBeInTheDocument();
  });

  it('renders status errors as alerts', async () => {
    mockApi(status({ error: 'Scheduled task access denied.' }));
    render(<App />);

    await waitFor(() => expect(screen.getByRole('alert')).toHaveTextContent('Scheduled task access denied.'));
  });

  it('saves notification settings from the settings UI', async () => {
    const savedPreferences = { ...defaultPreferences, timeLeftMinutes: 45 };
    mockApi(status({ installed: true, enabled: true }));
    window.rollerApi.savePreferences = vi.fn().mockResolvedValue(savedPreferences);
    render(<App />);

    await waitFor(() => expect(screen.getByText('Status refreshed')).toBeInTheDocument());
    fireEvent.change(screen.getByLabelText('Time-left alert minutes'), { target: { value: '45' } });

    await waitFor(() => expect(window.rollerApi.savePreferences).toHaveBeenCalledWith({ timeLeftMinutes: 45 }));
    expect(screen.getByLabelText('Time-left alert minutes')).toHaveValue(45);
  });

  it('exposes a minimize to tray control', async () => {
    mockApi(status({ installed: true, enabled: true }));
    render(<App />);

    await waitFor(() => expect(screen.getByText('Status refreshed')).toBeInTheDocument());
    fireEvent.click(screen.getByRole('button', { name: /minimize to tray/i }));

    expect(window.rollerApi.minimizeToTray).toHaveBeenCalledOnce();
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
