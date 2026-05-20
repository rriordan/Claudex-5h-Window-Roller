// @vitest-environment node
import { mkdtemp, rm } from 'node:fs/promises';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { describe, expect, it } from 'vitest';
import { defaultPreferences, PreferencesStore } from '../../src/main/preferences';

describe('PreferencesStore', () => {
  it('returns defaults when no file exists', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'claudex-prefs-'));
    try {
      const store = new PreferencesStore(join(dir, 'preferences.json'));
      await expect(store.load()).resolves.toEqual(defaultPreferences);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });

  it('persists partial changes over defaults', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'claudex-prefs-'));
    try {
      const store = new PreferencesStore(join(dir, 'preferences.json'));
      await store.save({ timeLeftMinutes: 45, quotaMessageNotifications: false });
      await expect(store.load()).resolves.toMatchObject({
        timeLeftMinutes: 45,
        quotaMessageNotifications: false,
        windowEndingMinutes: 10
      });
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});
