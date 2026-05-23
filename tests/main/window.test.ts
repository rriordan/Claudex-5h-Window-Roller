import { describe, expect, it, vi } from 'vitest';
import { restoreWindow, type RestorableWindow } from '../../src/main/window';

function createWindowStub(options: { destroyed?: boolean; minimized?: boolean } = {}): RestorableWindow {
  return {
    isDestroyed: vi.fn(() => options.destroyed ?? false),
    isMinimized: vi.fn(() => options.minimized ?? false),
    restore: vi.fn(),
    show: vi.fn(),
    focus: vi.fn()
  };
}

describe('restoreWindow', () => {
  it('shows and focuses an existing window', () => {
    const win = createWindowStub();

    expect(restoreWindow(win)).toBe(true);
    expect(win.show).toHaveBeenCalledOnce();
    expect(win.focus).toHaveBeenCalledOnce();
    expect(win.restore).not.toHaveBeenCalled();
  });

  it('restores minimized windows before showing them', () => {
    const win = createWindowStub({ minimized: true });

    expect(restoreWindow(win)).toBe(true);
    expect(win.restore).toHaveBeenCalledOnce();
    expect(win.show).toHaveBeenCalledOnce();
    expect(win.focus).toHaveBeenCalledOnce();
  });

  it('does not touch missing or destroyed windows', () => {
    const destroyed = createWindowStub({ destroyed: true });

    expect(restoreWindow(null)).toBe(false);
    expect(restoreWindow(destroyed)).toBe(false);
    expect(destroyed.show).not.toHaveBeenCalled();
    expect(destroyed.focus).not.toHaveBeenCalled();
  });
});
