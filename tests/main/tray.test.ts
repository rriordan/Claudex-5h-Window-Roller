// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { formatTrayDetail, formatTrayState, formatTrayTooltip } from '../../src/main/tray';
import type { RollerStatus } from '../../src/main/platform/types';

const status: RollerStatus = {
  taskName: 'Claudex5hWindowRoller',
  installed: true,
  enabled: true,
  supported: true,
  platform: 'win32',
  taskState: 'Ready',
  windowMinutes: 300,
  pingLeadSeconds: 90,
  stateDir: 'C:\\state',
  logFile: 'C:\\state\\service.log',
  checkedAt: '2026-05-20T00:00:00.000Z',
  clients: [
    {
      name: 'codex',
      userDisabled: false,
      installed: true,
      sources: ['WSL (Ubuntu)', 'PATH'],
      activeSource: 'WSL (Ubuntu)',
      windowStart: '2026-05-20T00:00:00.000Z',
      windowEnd: '2026-05-20T05:00:00.000Z',
      secondsLeft: 125,
      pingInSeconds: 35,
      lastPingAt: null,
      error: null
    }
  ]
};

describe('tray labels', () => {
  it('formats state with install, enable, and task state', () => {
    expect(formatTrayState(status)).toBe('Installed / Enabled / Task Ready');
  });

  it('formats active client detail with source and remaining time', () => {
    expect(formatTrayDetail(status)).toBe('codex via WSL (Ubuntu) / 2m left');
  });

  it('formats tooltip with state and client detail', () => {
    expect(formatTrayTooltip(status)).toBe('Claudex Roller - Installed / Enabled / Task Ready / codex via WSL (Ubuntu) / 2m left');
  });
});
