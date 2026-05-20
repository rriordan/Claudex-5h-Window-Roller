import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import type { CommandResult, PlatformAdapter, RollerStatus } from './types';

const execFileAsync = promisify(execFile);

type Runner = (file: string, args: string[]) => Promise<{ stdout: string; stderr: string }>;

export type WindowsAdapterOptions = {
  scriptPath: string;
  powershellPath?: string;
  runner?: Runner;
};

export function buildPowerShellArgs(scriptPath: string, flag: string): string[] {
  return ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptPath, flag];
}

export function createWindowsAdapter(options: WindowsAdapterOptions): PlatformAdapter {
  const powershellPath = options.powershellPath ?? 'pwsh.exe';
  const runner = options.runner ?? ((file, args) => execFileAsync(file, args, {
    windowsHide: true,
    timeout: 300_000,
    maxBuffer: 1024 * 1024
  }));

  async function run(flag: string): Promise<CommandResult> {
    try {
      const { stdout, stderr } = await runner(powershellPath, buildPowerShellArgs(options.scriptPath, flag));
      return { ok: true, stdout: stdout.trim(), stderr: stderr.trim() };
    } catch (error) {
      const err = error as NodeJS.ErrnoException & { stdout?: string; stderr?: string };
      return {
        ok: false,
        stdout: `${err.stdout ?? ''}`.trim(),
        stderr: `${err.stderr ?? ''}`.trim(),
        error: err.message
      };
    }
  }

  return {
    async getStatus(): Promise<RollerStatus> {
      const result = await run('-JsonStatus');
      if (!result.ok) {
        return {
          taskName: 'Claudex5hWindowRoller',
          installed: false,
          enabled: false,
          supported: true,
          platform: process.platform,
          taskState: null,
          windowMinutes: 300,
          pingLeadSeconds: 90,
          stateDir: null,
          logFile: null,
          checkedAt: new Date().toISOString(),
          clients: [],
          error: result.error ?? result.stderr
        };
      }

      const parsed = JSON.parse(result.stdout) as Omit<RollerStatus, 'supported' | 'platform'>;
      return { ...parsed, supported: true, platform: process.platform };
    },
    install: () => run('-Install'),
    uninstall: () => run('-Uninstall'),
    enable: () => run('-Enable'),
    disable: () => run('-Disable'),
    tick: () => run('-Tick')
  };
}
