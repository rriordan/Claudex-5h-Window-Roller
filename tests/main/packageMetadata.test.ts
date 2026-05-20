// @vitest-environment node
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const root = process.cwd();

describe('package metadata', () => {
  it('declares author metadata and a Windows app icon', () => {
    const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')) as {
      author?: string;
      build?: { win?: { icon?: string } };
    };

    expect(pkg.author).toBe('Robert Riordan');
    expect(pkg.build?.win?.icon).toBe('assets/icon.ico');
    expect(existsSync(join(root, 'assets/icon.svg'))).toBe(true);
    expect(existsSync(join(root, 'assets/icon.ico'))).toBe(true);
  });
});
