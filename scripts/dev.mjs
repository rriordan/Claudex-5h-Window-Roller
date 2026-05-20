import { spawnSync } from 'node:child_process';

await import('./build.mjs');

const result = spawnSync('npx', ['electron', '.'], {
  stdio: 'inherit',
  shell: true
});

process.exit(result.status ?? 1);
