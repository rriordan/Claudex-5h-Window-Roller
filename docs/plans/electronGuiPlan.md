---
type: plan
status: draft
updated_at: 2026-05-20
---

# Electron GUI Implementation Plan

## Source Design

Implement the approved design in:

- `docs/superpowers/specs/2026-05-20-electron-gui-design.md`

## Current Repo Facts

- Existing behavior lives in `claudex-roller.ps1`.
- Current script flags are `-Install`, `-Uninstall`, `-Status`, and `-Tick`.
- No Node, Electron, or app packaging files exist yet.
- The Electron app must be Windows-capable first, with unsupported macOS/Linux adapters.
- The background tray monitor must continue after the main window is closed.

## File Structure

Create:

- `package.json`: npm scripts, dependencies, build config entry points.
- `tsconfig.json`: shared TypeScript options.
- `electron.vite.config.ts`: Electron/Vite build config.
- `src/main/index.ts`: Electron lifecycle, tray, window creation.
- `src/main/ipc.ts`: typed IPC handlers.
- `src/main/monitor.ts`: background polling and notification dedupe.
- `src/main/preferences.ts`: persisted settings.
- `src/main/platform/types.ts`: adapter and status types.
- `src/main/platform/windows.ts`: PowerShell-backed adapter.
- `src/main/platform/unsupported.ts`: unsupported adapter for non-Windows OSes.
- `src/preload/index.ts`: safe renderer bridge.
- `src/renderer/index.html`: renderer mount point.
- `src/renderer/main.tsx`: renderer bootstrap.
- `src/renderer/App.tsx`: control panel UI.
- `src/renderer/styles.css`: app styling.
- `tests/main/*.test.ts`: main-process unit tests.
- `tests/renderer/*.test.tsx`: renderer unit tests.

Modify:

- `claudex-roller.ps1`: add `-Enable`, `-Disable`, and `-JsonStatus`.
- `.gitignore`: ignore Electron build output and dependency directories.
- `README.md`: add app usage notes after implementation works.

## Commands

Use these after scaffolding:

```bash
npm install
npm run typecheck
npm test
npm run build
```

Use PowerShell validation from Windows:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\claudex-roller.ps1 -JsonStatus
pwsh -NoProfile -ExecutionPolicy Bypass -File .\claudex-roller.ps1 -Disable
pwsh -NoProfile -ExecutionPolicy Bypass -File .\claudex-roller.ps1 -Enable
```

## Task 1: Add Machine-Readable Script Control

**Files:**

- Modify: `claudex-roller.ps1`
- Test: manual PowerShell commands above

- [ ] **Step 1: Add parameters**

Extend the existing `param(...)` block with:

```powershell
[Parameter(ParameterSetName='Enable')]     [switch]$Enable,
[Parameter(ParameterSetName='Disable')]    [switch]$Disable,
[Parameter(ParameterSetName='JsonStatus')] [switch]$JsonStatus,
```

- [ ] **Step 2: Add status object builder**

Create a helper that returns a `PSCustomObject` with installed, enabled, window, and error fields. Reuse existing `Get-RollerState`, `Get-UserDisabled`, `Get-CliState`, and `Get-WindowStart` behavior instead of duplicating logic.

- [ ] **Step 3: Add enable and disable handlers**

`-Disable` should set the existing `user_disabled` state and stop the scheduled task if it is present.

`-Enable` should clear the existing `user_disabled` state and start the scheduled task if it is present.

- [ ] **Step 4: Add JSON status output**

`-JsonStatus` should only write compact JSON to stdout:

```powershell
$status | ConvertTo-Json -Depth 6 -Compress
```

- [ ] **Step 5: Verify**

Run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\claudex-roller.ps1 -JsonStatus
```

Expected: valid JSON, no human status text.

- [ ] **Step 6: Commit**

```bash
git add claudex-roller.ps1
git commit -m "feat: add script status and enable controls"
```

## Task 2: Scaffold Electron App

**Files:**

- Create: `package.json`
- Create: `tsconfig.json`
- Create: `electron.vite.config.ts`
- Create: `src/main/index.ts`
- Create: `src/preload/index.ts`
- Create: `src/renderer/index.html`
- Create: `src/renderer/main.tsx`
- Create: `src/renderer/App.tsx`
- Create: `src/renderer/styles.css`
- Modify: `.gitignore`

- [ ] **Step 1: Add dependencies**

Use Electron, TypeScript, React, Vite, electron-vite, electron-builder, Vitest, and Testing Library.

- [ ] **Step 2: Add scripts**

`package.json` should include:

```json
{
  "scripts": {
    "dev": "electron-vite dev",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "build": "electron-vite build",
    "dist": "electron-builder --win nsis"
  }
}
```

- [ ] **Step 3: Add minimal app**

Window opens to a control panel shell. Main process creates a tray icon and hides the window on close instead of quitting.

- [ ] **Step 4: Verify**

Run:

```bash
npm run typecheck
npm test
npm run build
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add package.json package-lock.json tsconfig.json electron.vite.config.ts src .gitignore
git commit -m "feat: scaffold electron desktop app"
```

## Task 3: Implement Platform Adapter and IPC

**Files:**

- Create: `src/main/platform/types.ts`
- Create: `src/main/platform/windows.ts`
- Create: `src/main/platform/unsupported.ts`
- Create: `src/main/ipc.ts`
- Modify: `src/main/index.ts`
- Modify: `src/preload/index.ts`
- Test: `tests/main/platform.test.ts`
- Test: `tests/main/ipc.test.ts`

- [ ] **Step 1: Write adapter tests**

Test that Windows adapter builds `pwsh` commands with `-JsonStatus`, `-Install`, `-Uninstall`, `-Enable`, `-Disable`, and `-Tick`.

- [ ] **Step 2: Write unsupported adapter tests**

Test that non-Windows adapter returns `supported: false` status and disabled command results.

- [ ] **Step 3: Implement adapters**

Use `child_process.execFile` from Electron main. Pass arguments as an array. Do not shell-interpolate paths.

- [ ] **Step 4: Implement IPC**

Expose only these renderer calls:

```ts
getStatus()
install()
uninstall()
enable()
disable()
refresh()
getPreferences()
savePreferences(partial)
```

- [ ] **Step 5: Verify**

Run:

```bash
npm run typecheck
npm test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add src/main src/preload tests/main
git commit -m "feat: add platform adapter and ipc"
```

## Task 4: Preferences and Monitor

**Files:**

- Create: `src/main/preferences.ts`
- Create: `src/main/monitor.ts`
- Modify: `src/main/index.ts`
- Modify: `src/main/ipc.ts`
- Test: `tests/main/preferences.test.ts`
- Test: `tests/main/monitor.test.ts`

- [ ] **Step 1: Write preferences tests**

Test defaults:

```ts
{
  timeLeftNotifications: true,
  timeLeftMinutes: 30,
  windowEndingNotifications: true,
  windowEndingMinutes: 10,
  quotaMessageNotifications: true
}
```

- [ ] **Step 2: Write monitor tests**

Test notification dedupe by window ID and threshold. Test quota-message dedupe by event ID or timestamp.

- [ ] **Step 3: Implement preferences**

Persist JSON under Electron `app.getPath('userData')`. Keep schema versioned.

- [ ] **Step 4: Implement monitor**

Poll every 60 seconds. Provide a `refreshNow()` method for UI and tray. Emit status updates to the renderer when the window is open.

- [ ] **Step 5: Verify**

Run:

```bash
npm run typecheck
npm test
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add src/main/preferences.ts src/main/monitor.ts src/main/index.ts src/main/ipc.ts tests/main
git commit -m "feat: add tray monitor preferences"
```

## Task 5: Build the Control Panel UI

**Files:**

- Modify: `src/renderer/App.tsx`
- Modify: `src/renderer/styles.css`
- Test: `tests/renderer/App.test.tsx`

- [ ] **Step 1: Write renderer tests**

Test button availability:

- Installed false: install enabled, uninstall/enable/disable disabled.
- Installed true and enabled true: uninstall/disable enabled.
- Installed true and enabled false: uninstall/enable enabled.
- Unsupported platform: all operations disabled.

- [ ] **Step 2: Implement status view**

Show installed, enabled, monitoring, platform support, window start, window end, and time remaining.

- [ ] **Step 3: Implement actions**

Wire install, uninstall, enable, disable, and refresh to preload API calls. Refresh status after command completion.

- [ ] **Step 4: Implement notification settings**

Use toggles for binary settings and numeric inputs for minute thresholds.

- [ ] **Step 5: Verify**

Run:

```bash
npm run typecheck
npm test
npm run build
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add src/renderer tests/renderer
git commit -m "feat: build roller control panel"
```

## Task 6: Tray Menu and Notifications

**Files:**

- Modify: `src/main/index.ts`
- Modify: `src/main/monitor.ts`
- Test: `tests/main/monitor.test.ts`

- [ ] **Step 1: Test notification decision logic**

Cover time-left, window-ending, and quota-message events.

- [ ] **Step 2: Implement tray menu**

Menu items:

- Open Claudex Roller.
- Status summary.
- Enable or Disable.
- Refresh now.
- Quit.

- [ ] **Step 3: Implement notification delivery**

Use Electron `Notification` in main process. Set Windows AppUserModelID before notifications in packaged builds.

- [ ] **Step 4: Verify**

Run:

```bash
npm run typecheck
npm test
npm run build
```

Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add src/main tests/main
git commit -m "feat: add tray notifications"
```

## Task 7: Packaging and Documentation

**Files:**

- Modify: `package.json`
- Modify: `README.md`
- Optional create: `assets/icon.png`
- Optional create: `assets/icon.ico`

- [ ] **Step 1: Configure electron-builder**

Add Windows NSIS packaging. Include `claudex-roller.ps1` as an unpacked extra resource so main process can locate it reliably.

- [ ] **Step 2: Add README section**

Document:

- How to run dev app.
- How to package installer.
- What install/uninstall/enable/disable do.
- Tray behavior.
- Notification settings.
- Windows-first support status.

- [ ] **Step 3: Verify package**

Run:

```bash
npm run dist
```

Expected: Windows installer artifact appears under `dist/`.

- [ ] **Step 4: Commit**

```bash
git add package.json README.md assets
git commit -m "docs: document electron app packaging"
```

## Final Verification

Run:

```bash
npm run typecheck
npm test
npm run build
```

On Windows, run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\claudex-roller.ps1 -JsonStatus
```

Manual app checks:

- Main window opens.
- Install action calls script.
- Uninstall action calls script.
- Enable and disable actions update status.
- Closing window leaves tray process running.
- Tray Open restores the window.
- Tray Quit exits the process.
- Notification preferences persist after restart.
- Unsupported adapter behavior is visible when platform is not Windows.

## Implementation Notes

- Use TDD for logic modules: adapter command building, preferences, monitor notification decisions, and renderer button states.
- Keep PowerShell output for Electron machine-readable. Do not parse human `-Status` text.
- Keep all privileged operations in Electron main process, never renderer.
- Do not add macOS/Linux behavior beyond unsupported adapter in v1.
- If exact quota usage is unavailable, label those notifications as quota-message alerts, not percent-used alerts.
