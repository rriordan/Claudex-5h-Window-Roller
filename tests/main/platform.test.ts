// @vitest-environment node
import { describe, expect, it } from 'vitest';
import { buildPowerShellArgs, createWindowsAdapter } from '../../src/main/platform/windows';
import { createUnsupportedAdapter } from '../../src/main/platform/unsupported';

describe('windows adapter', () => {
  it('builds pwsh arguments without shell interpolation', () => {
    expect(buildPowerShellArgs('C:\\App Dir\\claudex-roller.ps1', '-JsonStatus')).toEqual([
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      'C:\\App Dir\\claudex-roller.ps1',
      '-JsonStatus'
    ]);
  });

  it('calls script flags through the injected runner', async () => {
    const calls: string[][] = [];
    const adapter = createWindowsAdapter({
      scriptPath: 'roller.ps1',
      powershellPath: 'pwsh.exe',
      runner: async (_file, args) => {
        calls.push(args);
        return {
          stdout: '{"taskName":"Claudex5hWindowRoller","installed":false,"enabled":true,"taskState":null,"windowMinutes":300,"pingLeadSeconds":90,"stateDir":null,"logFile":null,"checkedAt":"2026-05-20T00:00:00.000Z","clients":[]}',
          stderr: ''
        };
      }
    });

    await adapter.getStatus();
    await adapter.install();
    await adapter.uninstall();
    await adapter.enable();
    await adapter.disable();
    await adapter.tick();

    expect(calls.map((args) => args.at(-1))).toEqual([
      '-JsonStatus',
      '-Install',
      '-Uninstall',
      '-Enable',
      '-Disable',
      '-Tick'
    ]);
  });
});

describe('unsupported adapter', () => {
  it('returns unsupported status and disabled command results', async () => {
    const adapter = createUnsupportedAdapter('darwin');

    await expect(adapter.getStatus()).resolves.toMatchObject({
      supported: false,
      platform: 'darwin',
      installed: false,
      enabled: false
    });
    await expect(adapter.install()).resolves.toMatchObject({ ok: false });
  });
});
