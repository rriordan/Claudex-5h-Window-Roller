---
type: plan
status: in_progress
updated_at: 2026-05-22
---

# Release Roadmap

## Version Alignment

`v0.6.0` is the shipped Electron desktop app release. Earlier roadmap labels that used `v0.1` through `v0.6` described product phases, not actual release tags. Going forward, roadmap versions follow the real package and GitHub release sequence.

## Current Stabilization

### v0.6.1 - Installed App Stabilization

Status: complete in the `v0.7.0` release line.

Goal: close the release-hardening gap found after `v0.6.0`.

- Fix false-success install behavior when Windows Scheduled Task registration fails.
- Decide and document the Windows permission path for task registration.
- Add `npm run test:powershell` and include PowerShell smoke tests in release verification.
- Verify install, uninstall, enable, disable, refresh, and JSON status from the packaged app.
- Verify tray close-to-tray, reopen, refresh now, enable/disable, quit, and notification preference persistence.
- Release only after installed-app behavior is verified on Windows.

## Forward Roadmap

### v0.7.0 - Visibility and Notifications

Status: complete.

- Improve status visibility in the app and tray.
- Harden notification delivery and dedupe behavior.
- Keep quota messaging framed as log-message based unless local data proves exact usage percentages.

### v0.8.0 - TypeScript Core and History

- Define TypeScript core APIs for window detection, quota-message scanning, source selection, notification dedupe, and history.
- Add fixture-based tests for Claude and Codex 5-hour window calculations.
- Keep platform adapters responsible for OS-specific install and startup tasks.

### v0.9.0 - Pace and Status Lines

- Add clearer pace and status-line reporting.
- Prefer estimates with explicit labels over unsupported precision.

### v0.10.0 - Timing Control

- Add user-facing timing controls for polling, ping lead time, and notification thresholds.
- Preserve safe defaults for unattended use.

### v0.11.0 - Cross-Platform Flexibility

- Expand unsupported-state adapters into practical macOS/Linux paths where feasible.
- Keep Windows behavior stable while adding platform-specific capabilities.

## Release Gate

Each release must pass:

- `npm run typecheck`
- `npm test`
- `npm run test:powershell`
- `npm run build`
- Packaged-app smoke test on Windows
