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

  it('gates notifications by preferences', () => {
    const state = createMonitorState();

    const events = selectNotifications(
      baseStatus,
      {
        ...defaultPreferences,
        timeLeftNotifications: false,
        windowEndingNotifications: false,
        quotaMessageNotifications: false
      },
      state,
      ['line-1']
    );

    expect(events).toEqual([]);
  });

  it('uses clear notification copy without exact quota percentages', () => {
    const state = createMonitorState();

    const events = selectNotifications(baseStatus, defaultPreferences, state, ['line-1']);

    expect(events[0]).toMatchObject({
      title: 'codex window time low',
      body: 'codex via PATH has 30 minutes or less remaining in the current 5h window.'
    });
    expect(events[1]).toMatchObject({
      title: 'codex window ending',
      body: 'codex via PATH is within 10 minutes of the current window ending.'
    });
    expect(events[2]).toMatchObject({
      title: 'Quota message detected',
      body: expect.stringContaining('not an exact usage percentage')
    });
  });
});
