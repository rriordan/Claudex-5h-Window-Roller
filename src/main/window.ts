export type RestorableWindow = {
  isDestroyed(): boolean;
  isMinimized(): boolean;
  restore(): void;
  show(): void;
  focus(): void;
};

type WindowLifecycleEvent = {
  preventDefault(): void;
};

export type TrayWindow = RestorableWindow & {
  hide(): void;
  on(eventName: 'close' | 'minimize', listener: (event: WindowLifecycleEvent) => void): void;
};

export function restoreWindow(window: RestorableWindow | null): boolean {
  if (!window || window.isDestroyed()) return false;
  if (window.isMinimized()) window.restore();
  window.show();
  window.focus();
  return true;
}

export function registerTrayWindowBehavior(window: TrayWindow, isQuitting: () => boolean): void {
  window.on('minimize', (event) => {
    event.preventDefault();
    window.hide();
  });

  window.on('close', (event) => {
    if (isQuitting()) return;
    event.preventDefault();
    window.hide();
  });
}
