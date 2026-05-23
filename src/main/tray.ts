import type { RollerStatus } from './platform/types';

function formatMinutes(seconds: number | null | undefined): string {
  if (typeof seconds !== 'number') return '';
  return `${Math.max(0, Math.floor(seconds / 60))}m left`;
}

export function selectTrayClient(status: RollerStatus | null): RollerStatus['clients'][number] | null {
  if (!status) return null;
  return status.clients.find((client) => client.secondsLeft !== null) ?? status.clients[0] ?? null;
}

export function formatTrayState(status: RollerStatus | null): string {
  if (!status) return 'Status pending';
  if (!status.supported) return 'Unsupported platform';
  const installState = status.installed ? 'Installed' : 'Not installed';
  const enabledState = status.enabled ? 'Enabled' : 'Disabled';
  const taskState = status.taskState ? `Task ${status.taskState}` : 'Task none';
  return `${installState} / ${enabledState} / ${taskState}`;
}

export function formatTrayDetail(status: RollerStatus | null): string {
  const client = selectTrayClient(status);
  if (!client) return '';
  const source = client.activeSource ?? 'No source';
  const timeLeft = formatMinutes(client.secondsLeft);
  return timeLeft ? `${client.name} via ${source} / ${timeLeft}` : `${client.name} via ${source}`;
}

export function formatTrayTooltip(status: RollerStatus | null): string {
  const detail = formatTrayDetail(status);
  return detail ? `Claudex Roller - ${formatTrayState(status)} / ${detail}` : `Claudex Roller - ${formatTrayState(status)}`;
}
