---
type: design
status: draft
updated_at: 2026-05-20
---

# Electron GUI Design

## Goal

Turn Claudex 5h Window Roller into a packaged Electron desktop app with:

- Install and uninstall controls for the roller.
- Enable and disable controls without removing the app.
- A background tray monitor that keeps running when the main window is closed.
- Notifications for both time-based window warnings and quota-message warnings.
- Architecture that is Windows-first but leaves room for macOS and Linux adapters.

## Non-Goals

- Rewriting the working PowerShell roller logic in TypeScript for v1.
- Supporting macOS or Linux behavior in v1 beyond explicit unsupported states.
- Building a cloud service, account system, or external dependency.
- Inferring exact quota percentage unless upstream logs expose enough data.

## Recommended Approach

Use Electron as the packaged desktop shell. Keep `claudex-roller.ps1` as the Windows authority for install, uninstall, status, and tick behavior in v1.

Electron owns:

- Main window UI.
- Tray lifecycle.
- User preferences.
- Background monitor loop.
- Notification delivery.
- IPC boundary between renderer and privileged main process.

PowerShell owns:

- Windows Scheduled Task install and uninstall.
- Existing Codex and Claude log detection.
- Current 5-hour window state calculation.
- CLI ping behavior.

The app calls PowerShell through a platform adapter interface so future macOS/Linux work can add adapters without rewriting UI or tray code.

## Architecture

```text
Renderer UI
  -> typed IPC client
  -> Electron main process
  -> platform adapter
  -> Windows PowerShell adapter
  -> claudex-roller.ps1
```

Suggested modules:

- `src/main/index.ts`: Electron app lifecycle, tray, window creation.
- `src/main/ipc.ts`: IPC handlers with narrow command surface.
- `src/main/monitor.ts`: background polling and notification decisions.
- `src/main/preferences.ts`: persisted user settings.
- `src/main/platform/types.ts`: common platform adapter interface.
- `src/main/platform/windows.ts`: PowerShell-backed Windows implementation.
- `src/main/platform/unsupported.ts`: macOS/Linux placeholder implementation.
- `src/preload/index.ts`: safe renderer API exposure.
- `src/renderer/*`: UI components and state.

## Platform Adapter

The adapter should expose a small contract:

```ts
interface PlatformAdapter {
  getStatus(): Promise<RollerStatus>;
  install(): Promise<CommandResult>;
  uninstall(): Promise<CommandResult>;
  enable(): Promise<CommandResult>;
  disable(): Promise<CommandResult>;
  tick(): Promise<CommandResult>;
}
```

`enable()` and `disable()` are new v1 behavior. On Windows they should be backed by new PowerShell flags or state changes, not by uninstalling the scheduled task.

## PowerShell Script Changes

Add flags:

- `-Enable`: clear `user_disabled` state and start scheduled task if installed.
- `-Disable`: set `user_disabled` state and stop active scheduled task if installed.
- `-JsonStatus`: return machine-readable status for Electron.

Keep existing flags stable:

- `-Install`
- `-Uninstall`
- `-Status`
- `-Tick`

`-JsonStatus` should include:

- installed state.
- enabled state.
- current window start.
- current window end.
- time remaining.
- latest Codex and Claude activity signals when available.
- last tick time.
- last error.
- notification eligibility signals when available.

## Background Monitor

The Electron main process runs a monitor while the app is active in the tray.

Default polling:

- Status refresh every 60 seconds.
- Log quota-message scan every 60 seconds.
- Manual refresh from UI.

Monitor responsibilities:

- Call `getStatus()`.
- Decide whether a time-left notification should fire.
- Watch status/log signals for quota-message alerts.
- Deduplicate notifications with persisted timestamps and event IDs.
- Update tray tooltip/menu.

The monitor should keep running when the main window is closed. Quitting from the tray exits it.

## Notifications

User preferences:

- Enable time-left notifications.
- Time-left threshold, default 30 minutes.
- Enable quota-message notifications.
- Enable window-ending notifications.
- Window-ending threshold, default 10 minutes.

Notification rules:

- Time-left notification fires once per window per threshold.
- Window-ending notification fires once per window per threshold.
- Quota-message notification fires when a new matching log event appears.
- Notifications must be deduplicated across app restarts.

Quota-message matching should start conservative and configurable in code. Example terms:

- `usage limit`
- `rate limit`
- `limit reached`
- `quota`
- `try again`

## Main Window

The first screen is the operational control panel, not a landing page.

Primary areas:

- Status strip: installed, enabled, monitoring, platform support.
- Window timing: start, end, time remaining.
- Actions: install, uninstall, enable, disable, refresh.
- Notification preferences: toggles and threshold inputs.
- Recent events: last status refresh, last notification, last error.

Button state rules:

- Install disabled when installed.
- Uninstall disabled when not installed.
- Enable disabled when enabled or not installed.
- Disable disabled when disabled or not installed.
- Unsupported platforms show disabled actions with clear status text.

## Tray

Tray menu:

- Open Claudex Roller.
- Status summary.
- Enable or Disable.
- Refresh now.
- Quit.

Tray tooltip should include installed/enabled state and time remaining when available.

Closing the main window hides it to tray. Explicit quit exits the app.

## Cross-Platform Strategy

v1 ships as Windows-capable Electron app.

macOS/Linux behavior:

- App launches.
- UI shows platform unsupported for roller operations.
- Preferences and tray still work.
- Adapter boundary remains stable for future implementation.

Future adapters can replace the PowerShell bridge with native shell scripts or TypeScript logic.

## Packaging

Use Electron with TypeScript and a bundler.

Suggested stack:

- Electron.
- TypeScript.
- Vite for renderer/main build.
- electron-builder for Windows packaging.

Recommended package outputs:

- Windows NSIS installer.
- Portable executable optional after installer works.

## Risks

- PowerShell status output is currently human-readable; Electron needs JSON to avoid fragile parsing.
- Exact quota usage may not be available. v1 should frame quota notifications as log-message based.
- Background tray behavior differs by OS, so platform-specific logic must stay in main process.
- Windows notification behavior may require AppUserModelID handling for packaged builds.

## Acceptance Criteria

- Packaged Electron app opens a control panel.
- App can install and uninstall the existing Windows roller.
- App can enable and disable roller behavior without uninstalling.
- App remains active in tray after window close.
- Tray menu can reopen the app and quit the monitor.
- Time-left and window-ending notification preferences persist.
- Quota-message notifications are supported from log matching where data is available.
- Status refresh does not parse human text when JSON status is available.
- macOS/Linux show a clear unsupported state without crashing.
