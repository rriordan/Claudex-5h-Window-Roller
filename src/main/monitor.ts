import { readFile } from 'node:fs/promises';
import type { NotificationPreferences } from './preferences';
import type { PlatformAdapter, RollerStatus } from './platform/types';

type NotificationEvent = {
  id: string;
  title: string;
  body: string;
};

type MonitorState = {
  sent: Set<string>;
};

export type Notifier = {
  notify(event: NotificationEvent): void;
};

export function createMonitorState(): MonitorState {
  return { sent: new Set<string>() };
}

function clientLabel(client: RollerStatus['clients'][number]): string {
  return `${client.name}${client.activeSource ? ` via ${client.activeSource}` : ''}`;
}

export function selectNotifications(
  status: RollerStatus,
  preferences: NotificationPreferences,
  state: MonitorState,
  quotaEventIds: string[] = []
): NotificationEvent[] {
  const events: NotificationEvent[] = [];

  for (const client of status.clients) {
    if (client.secondsLeft === null || client.windowStart === null) continue;

    if (preferences.timeLeftNotifications && client.secondsLeft <= preferences.timeLeftMinutes * 60) {
      const id = `${client.name}:${client.windowStart}:time-left:${preferences.timeLeftMinutes}`;
      if (!state.sent.has(id)) {
        state.sent.add(id);
        events.push({
          id,
          title: `${client.name} window time low`,
          body: `${clientLabel(client)} has ${preferences.timeLeftMinutes} minutes or less remaining in the current 5h window.`
        });
      }
    }

    if (preferences.windowEndingNotifications && client.secondsLeft <= preferences.windowEndingMinutes * 60) {
      const id = `${client.name}:${client.windowStart}:window-ending:${preferences.windowEndingMinutes}`;
      if (!state.sent.has(id)) {
        state.sent.add(id);
        events.push({
          id,
          title: `${client.name} window ending`,
          body: `${clientLabel(client)} is within ${preferences.windowEndingMinutes} minutes of the current window ending.`
        });
      }
    }
  }

  if (preferences.quotaMessageNotifications) {
    for (const quotaEventId of quotaEventIds) {
      const id = `quota:${quotaEventId}`;
      if (!state.sent.has(id)) {
        state.sent.add(id);
        events.push({
          id,
          title: 'Quota message detected',
          body: 'A recent local log line matched usage-limit wording. Treat this as a quota-message alert, not an exact usage percentage.'
        });
      }
    }
  }

  return events;
}

export async function scanQuotaMessages(logFile: string | null): Promise<string[]> {
  if (!logFile) return [];
  try {
    const raw = await readFile(logFile, 'utf8');
    return raw
      .split(/\r?\n/)
      .filter((line) => /(usage limit|rate limit|limit reached|quota|try again)/i.test(line))
      .slice(-20)
      .map((line) => Buffer.from(line).toString('base64url'));
  } catch {
    return [];
  }
}

export class RollerMonitor {
  private timer: NodeJS.Timeout | null = null;
  private readonly state = createMonitorState();

  constructor(
    private readonly adapter: PlatformAdapter,
    private readonly loadPreferences: () => Promise<NotificationPreferences>,
    private readonly notifier: Notifier,
    private readonly onStatus?: (status: RollerStatus) => void
  ) {}

  start(): void {
    if (this.timer) return;
    void this.refreshNow();
    this.timer = setInterval(() => {
      void this.refreshNow();
    }, 60_000);
  }

  stop(): void {
    if (!this.timer) return;
    clearInterval(this.timer);
    this.timer = null;
  }

  async refreshNow(): Promise<RollerStatus> {
    const status = await this.adapter.getStatus();
    const preferences = await this.loadPreferences();
    const quotaEventIds = await scanQuotaMessages(status.logFile);
    const events = selectNotifications(status, preferences, this.state, quotaEventIds);
    for (const event of events) this.notifier.notify(event);
    this.onStatus?.(status);
    return status;
  }
}
