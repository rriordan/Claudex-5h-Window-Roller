import { describe, expect, it, vi } from 'vitest';
import { registerTrayWindowBehavior, restoreWindow, type RestorableWindow } from '../../src/main/window';

type WindowEventStub = { preventDefault(): void };

type WindowStub = RestorableWindow & {
  hide(): void;
  on(eventName: 'close' | 'minimize', listener: (event: WindowEventStub) => void): void;
  emitWindowEvent(eventName: 'close' | 'minimize', event: WindowEventStub): void;
};

function createWindowStub(options: { destroyed?: boolean; minimized?: boolean } = {}): WindowStub {
  const listeners = new Map<string, (event: WindowEventStub) => void>();
  const win = {
    isDestroyed: vi.fn(() => options.destroyed ?? false),
    isMinimized: vi.fn(() => options.minimized ?? false),
    restore: vi.fn(),
    show: vi.fn(),
    focus: vi.fn(),
    hide: vi.fn(),
    on: vi.fn((eventName: 'close' | 'minimize', listener: (event: WindowEventStub) => void) => {
      listeners.set(eventName, listener);
    })
  };
  return Object.assign(win, {
    emitWindowEvent: (eventName: 'close' | 'minimize', event: WindowEventStub) => listeners.get(eventName)?.(event)
  });
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

describe('registerTrayWindowBehavior', () => {
  it('hides the window to tray when minimized or closed', () => {
    const win = createWindowStub();
    const closeEvent = { preventDefault: vi.fn() };
    const minimizeEvent = { preventDefault: vi.fn() };

    registerTrayWindowBehavior(win, () => false);
    win.emitWindowEvent('minimize', minimizeEvent);
    win.emitWindowEvent('close', closeEvent);

    expect(minimizeEvent.preventDefault).toHaveBeenCalledOnce();
    expect(closeEvent.preventDefault).toHaveBeenCalledOnce();
    expect(win.hide).toHaveBeenCalledTimes(2);
  });

  it('allows close when the app is quitting', () => {
    const win = createWindowStub();
    const closeEvent = { preventDefault: vi.fn() };

    registerTrayWindowBehavior(win, () => true);
    win.emitWindowEvent('close', closeEvent);

    expect(closeEvent.preventDefault).not.toHaveBeenCalled();
    expect(win.hide).not.toHaveBeenCalled();
  });
});
