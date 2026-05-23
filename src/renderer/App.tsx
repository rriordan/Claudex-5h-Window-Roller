import { Bell, BellRing, CheckCircle2, Download, Power, RefreshCw, Trash2 } from 'lucide-react';
import { useEffect, useMemo, useState } from 'react';
import type { ReactElement } from 'react';
import type { NotificationPreferences } from '../main/preferences';
import type { CommandResult, RollerStatus } from '../main/platform/types';

type RollerApi = {
  getStatus(): Promise<RollerStatus>;
  install(): Promise<CommandResult>;
  uninstall(): Promise<CommandResult>;
  enable(): Promise<CommandResult>;
  disable(): Promise<CommandResult>;
  refresh(): Promise<RollerStatus>;
  getPreferences(): Promise<NotificationPreferences>;
  savePreferences(partial: Partial<NotificationPreferences>): Promise<NotificationPreferences>;
  onStatus(callback: (status: RollerStatus) => void): () => void;
};

declare global {
  interface Window {
    rollerApi: RollerApi;
  }
}

const fallbackStatus: RollerStatus = {
  taskName: 'Claudex5hWindowRoller',
  installed: false,
  enabled: false,
  supported: false,
  platform: 'linux',
  taskState: null,
  windowMinutes: 300,
  pingLeadSeconds: 90,
  stateDir: null,
  logFile: null,
  checkedAt: new Date().toISOString(),
  clients: [],
  error: 'Desktop bridge unavailable.'
};

const fallbackPreferences: NotificationPreferences = {
  schemaVersion: 1,
  timeLeftNotifications: true,
  timeLeftMinutes: 30,
  windowEndingNotifications: true,
  windowEndingMinutes: 10,
  quotaMessageNotifications: true
};

function formatTimeLeft(seconds: number | null): string {
  if (seconds === null) return 'No open window';
  const safe = Math.max(0, seconds);
  const hours = Math.floor(safe / 3600);
  const minutes = Math.floor((safe % 3600) / 60);
  return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
}

function formatTimestamp(value: string | null): string {
  if (value === null) return 'Not scheduled';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString([], {
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit'
  });
}

function formatPing(seconds: number | null): string {
  if (seconds === null) return 'No ping queued';
  if (seconds <= 0) return 'Due now';
  return formatTimeLeft(seconds);
}

function statusLabel(status: RollerStatus): string {
  if (!status.supported) return 'Unsupported platform';
  if (!status.installed) return 'Not installed';
  return status.enabled ? 'Enabled' : 'Disabled';
}

export function App(): ReactElement {
  const api = window.rollerApi;
  const [status, setStatus] = useState<RollerStatus>(fallbackStatus);
  const [preferences, setPreferences] = useState<NotificationPreferences>(fallbackPreferences);
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState('Ready');

  const bestClient = useMemo(
    () => status.clients.find((client) => client.secondsLeft !== null) ?? status.clients[0],
    [status.clients]
  );

  async function load(): Promise<void> {
    setBusy('refresh');
    try {
      const [nextStatus, nextPreferences] = await Promise.all([api.getStatus(), api.getPreferences()]);
      setStatus(nextStatus);
      setPreferences(nextPreferences);
      setMessage('Status refreshed');
    } catch (error) {
      setMessage(error instanceof Error ? error.message : 'Refresh failed');
    } finally {
      setBusy(null);
    }
  }

  async function run(label: string, action: () => Promise<CommandResult | RollerStatus>): Promise<void> {
    setBusy(label);
    try {
      const result = await action();
      if ('ok' in result && !result.ok) setMessage(result.stderr || result.error || `${label} failed`);
      else setMessage(`${label} complete`);
      setStatus(await api.getStatus());
    } catch (error) {
      setMessage(error instanceof Error ? error.message : `${label} failed`);
    } finally {
      setBusy(null);
    }
  }

  async function updatePreference(partial: Partial<NotificationPreferences>): Promise<void> {
    const next = await api.savePreferences(partial);
    setPreferences(next);
  }

  useEffect(() => {
    void load();
    return api.onStatus((nextStatus) => setStatus(nextStatus));
  }, []);

  const operationDisabled = busy !== null || !status.supported;

  return (
    <main className="app-shell">
      <section className="top-strip">
        <div>
          <p className="eyebrow">Claudex Roller</p>
          <h1>5h Window Control</h1>
        </div>
        <div className={`state-pill ${status.enabled ? 'is-enabled' : 'is-disabled'}`}>
          <CheckCircle2 size={17} />
          <span>{statusLabel(status)}</span>
        </div>
      </section>

      <section className="status-band">
        <div>
          <span>Time remaining</span>
          <strong>{formatTimeLeft(bestClient?.secondsLeft ?? null)}</strong>
        </div>
        <div>
          <span>Roller</span>
          <strong>{status.installed ? (status.enabled ? 'Installed, enabled' : 'Installed, disabled') : 'Not installed'}</strong>
        </div>
        <div>
          <span>Active source</span>
          <strong>{bestClient?.activeSource ?? 'None'}</strong>
        </div>
        <div>
          <span>Task</span>
          <strong>{status.taskState ?? 'None'}</strong>
        </div>
        <div>
          <span>Platform</span>
          <strong>{status.platform}</strong>
        </div>
      </section>

      <section className="workspace-grid">
        <div className="panel">
          <div className="panel-heading">
            <h2>Controls</h2>
            <button className="icon-button" type="button" title="Refresh" onClick={() => run('Refresh', api.refresh)} disabled={busy !== null}>
              <RefreshCw size={18} />
            </button>
          </div>
          <div className="action-grid">
            <button type="button" onClick={() => run('Install', api.install)} disabled={operationDisabled || status.installed}>
              <Download size={18} /> Install
            </button>
            <button type="button" onClick={() => run('Uninstall', api.uninstall)} disabled={operationDisabled || !status.installed}>
              <Trash2 size={18} /> Uninstall
            </button>
            <button type="button" onClick={() => run('Enable', api.enable)} disabled={operationDisabled || !status.installed || status.enabled}>
              <Power size={18} /> Enable
            </button>
            <button type="button" onClick={() => run('Disable', api.disable)} disabled={operationDisabled || !status.installed || !status.enabled}>
              <Power size={18} /> Disable
            </button>
          </div>
          <p className="message-line">{message}</p>
          {status.error && <p className="status-error" role="alert">{status.error}</p>}
        </div>

        <div className="panel">
          <div className="panel-heading">
            <h2>Notifications</h2>
            <BellRing size={19} />
          </div>
          <label className="setting-row">
            <input
              type="checkbox"
              checked={preferences.timeLeftNotifications}
              onChange={(event) => void updatePreference({ timeLeftNotifications: event.currentTarget.checked })}
            />
            <span>Time-left alerts</span>
            <input
              type="number"
              min="1"
              max="240"
              value={preferences.timeLeftMinutes}
              onChange={(event) => void updatePreference({ timeLeftMinutes: Number(event.currentTarget.value) })}
              aria-label="Time-left alert minutes"
            />
          </label>
          <label className="setting-row">
            <input
              type="checkbox"
              checked={preferences.windowEndingNotifications}
              onChange={(event) => void updatePreference({ windowEndingNotifications: event.currentTarget.checked })}
            />
            <span>Window-ending alerts</span>
            <input
              type="number"
              min="1"
              max="120"
              value={preferences.windowEndingMinutes}
              onChange={(event) => void updatePreference({ windowEndingMinutes: Number(event.currentTarget.value) })}
              aria-label="Window-ending alert minutes"
            />
          </label>
          <label className="setting-row">
            <input
              type="checkbox"
              checked={preferences.quotaMessageNotifications}
              onChange={(event) => void updatePreference({ quotaMessageNotifications: event.currentTarget.checked })}
            />
            <span>Quota-message alerts</span>
            <Bell size={18} />
          </label>
        </div>
      </section>

      <section className="client-list">
        {status.clients.map((client) => (
          <article className="client-row" key={client.name}>
            <div>
              <h3>{client.name}</h3>
              <p>{client.sources.length > 0 ? client.sources.join(', ') : 'No source detected'}</p>
              <dl className="client-details">
                <div>
                  <dt>Active</dt>
                  <dd>{client.activeSource ?? 'None'}</dd>
                </div>
                <div>
                  <dt>Window end</dt>
                  <dd>{formatTimestamp(client.windowEnd)}</dd>
                </div>
                <div>
                  <dt>Next ping</dt>
                  <dd>{formatPing(client.pingInSeconds)}</dd>
                </div>
                <div>
                  <dt>Last ping</dt>
                  <dd>{formatTimestamp(client.lastPingAt)}</dd>
                </div>
              </dl>
              {client.error && <p className="client-error">{client.error}</p>}
            </div>
            <strong>{formatTimeLeft(client.secondsLeft)}</strong>
          </article>
        ))}
        {status.clients.length === 0 && <p className="empty-state">{status.error ?? 'No client status available.'}</p>}
      </section>
    </main>
  );
}
