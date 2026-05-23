---
type: plan
status: done
updated_at: 2026-05-22
---

# v0.6.0 Through v0.7.0 Completion Plan

> For agentic workers: REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Finish release stabilization from `v0.6.0` through `v0.7.0`.

**Architecture:** Keep the PowerShell script as the Windows authority for scheduled task install/status/tick behavior. Keep Electron main responsible for tray, monitor loop, notification delivery, and IPC. Improve visibility and notification behavior without moving core business logic out of PowerShell yet.

**Tech Stack:** PowerShell, Electron, React, TypeScript, Vitest, electron-builder NSIS.

---

## Task 1: Close v0.6.1 Install Stabilization

- [x] Make scheduled-task install operations fail fast when Windows denies task registration.
- [x] Add PowerShell smoke coverage for install error handling.
- [x] Add `npm run test:powershell` and `npm run test:all`.
- [x] Document Scheduled Task permission requirements.
- [x] Prefer command stderr in the renderer so install failures show the actionable Windows error.
- [x] Verify the final install failure path still exits non-zero in this restricted session.

## Task 2: Improve v0.7.0 Status Visibility

- [x] Add clearer renderer status copy for installed/enabled/task state.
- [x] Add per-client source, state, next ping/window end visibility.
- [x] Add status error rendering that is visually distinct from empty-state copy.
- [x] Add renderer tests for the visibility changes.

## Task 3: Harden v0.7.0 Tray Visibility

- [x] Include installed/enabled/task state in tray tooltip/menu.
- [x] Include the best client and time remaining when available.
- [x] Keep Refresh now and Enable/Disable behavior intact.
- [x] Add focused tests for tray label formatting if extracted to pure functions.

## Task 4: Harden v0.7.0 Notifications

- [x] Ensure time-left, window-ending, and quota-message notifications stay preference-gated.
- [x] Ensure notification event IDs dedupe across repeated monitor ticks.
- [x] Improve notification titles/bodies to be clear but not claim exact quota percentages.
- [x] Add monitor tests for disabled preferences and event body text.

## Task 5: Release Prep

- [x] Update package version to `0.7.0` only after Tasks 1-4 pass.
- [x] Update roadmap/docs to mark `v0.6.1` and `v0.7.0` complete.
- [x] Run release gate: `npm run typecheck`, `npm test`, `npm run test:powershell`, `npm run build`.
- [x] Report remaining manual packaged-app checks that cannot be completed from this restricted session.

## Completion Notes

- Built `dist/Claudex 5h Window Roller Setup 0.7.0.exe`.
- Silent installer smoke test exited `0` and registered app version `0.7.0`.
- Packaged app launch smoke test started the installed Electron app.
- This restricted session cannot create Windows Scheduled Tasks (`Register-ScheduledTask` and `schtasks /Create` both return access denied), so full live task install/start/tray lifecycle still requires an elevated or policy-allowed Windows desktop session.
