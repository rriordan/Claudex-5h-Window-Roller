import type { CommandResult, PlatformAdapter, RollerStatus } from './types';

function unsupportedResult(): CommandResult {
  return {
    ok: false,
    stdout: '',
    stderr: '',
    error: 'This platform is not supported yet.'
  };
}

export function createUnsupportedAdapter(platform: NodeJS.Platform = process.platform): PlatformAdapter {
  return {
    async getStatus(): Promise<RollerStatus> {
      return {
        taskName: 'Claudex5hWindowRoller',
        installed: false,
        enabled: false,
        supported: false,
        platform,
        taskState: null,
        windowMinutes: 300,
        pingLeadSeconds: 90,
        stateDir: null,
        logFile: null,
        checkedAt: new Date().toISOString(),
        clients: [],
        error: 'This platform is not supported yet.'
      };
    },
    install: async () => unsupportedResult(),
    uninstall: async () => unsupportedResult(),
    enable: async () => unsupportedResult(),
    disable: async () => unsupportedResult(),
    tick: async () => unsupportedResult()
  };
}
