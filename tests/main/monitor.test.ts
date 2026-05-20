// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { defaultPreferences } from '../../src/main/preferences';
import { createMonitorState, selectNotifications } from '../../src/main/monitor';
import type { RollerStatus } from '../../src/main/platform/types';

const baseStatus: RollerStatus = {
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
      sources: ['PATH'],
      activeSource: 'PATH',
      windowStart: '2026-05-20T00:00:00.000Z',
      windowEnd: '2026-05-20T05:00:00.000Z',
      secondsLeft: 500,
      pingInSeconds: 410,
      lastPingAt: null,
      error: null
    }
  ]
};

describe('selectNotifications', () => {
  it('deduplicates time and quota notifications', () => {
    const state = createMonitorState();

    const first = selectNotifications(baseStatus, defaultPreferences, state, ['line-1']);
    const second = selectNotifications(baseStatus, defaultPreferences, state, ['line-1']);

    expect(first.map((event) => event.id)).toEqual([
      'codex:2026-05-20T00:00:00.000Z:time-left:30',
      'codex:2026-05-20T00:00:00.000Z:window-ending:10',
      'quota:line-1'
    ]);
    expect(second).toEqual([]);
  });
});
