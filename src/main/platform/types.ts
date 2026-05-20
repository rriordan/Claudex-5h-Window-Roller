export type ClientStatus = {
  name: 'claude' | 'codex';
  userDisabled: boolean;
  installed: boolean;
  sources: string[];
  activeSource: string | null;
  windowStart: string | null;
  windowEnd: string | null;
  secondsLeft: number | null;
  pingInSeconds: number | null;
  lastPingAt: string | null;
  error: string | null;
};

export type RollerStatus = {
  taskName: string;
  installed: boolean;
  enabled: boolean;
  supported: boolean;
  platform: NodeJS.Platform;
  taskState: string | null;
  windowMinutes: number;
  pingLeadSeconds: number;
  stateDir: string | null;
  logFile: string | null;
  checkedAt: string;
  clients: ClientStatus[];
  error?: string | null;
};

export type CommandResult = {
  ok: boolean;
  stdout: string;
  stderr: string;
  error?: string;
};

export type PlatformAdapter = {
  getStatus(): Promise<RollerStatus>;
  install(): Promise<CommandResult>;
  uninstall(): Promise<CommandResult>;
  enable(): Promise<CommandResult>;
  disable(): Promise<CommandResult>;
  tick(): Promise<CommandResult>;
};
