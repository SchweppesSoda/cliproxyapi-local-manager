# CPA Scheduled Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix misleading red Windows update output and add configurable daily CPA auto-update on Windows and macOS.

**Architecture:** Keep the existing single script per platform. Add small scheduler helpers beside lifecycle helpers, reuse the existing install/update command, and expose three new actions through help, command dispatch, and menu.

**Tech Stack:** PowerShell 5.1-compatible script, POSIX shell for macOS, Windows Task Scheduler, macOS LaunchAgent plist, existing repository static tests.

## Global Constraints

- Do not commit local install directories, `config.yaml`, `webui-management-key.txt`, `auth/`, OAuth tokens, API keys, management keys, logs, downloads, or generated runtime state.
- Keep generated CLIProxyAPI configuration local-only: bind to `127.0.0.1`, keep remote management disabled, and do not add tunnel, public-domain, VPS, cloud-host, or multi-user assumptions.
- Do not change menu behavior, output format, or lifecycle semantics without updating Windows, macOS, README, and tests together.
- Default scheduled update cron is `0 4 * * *`; user-entered cron is limited to daily fixed-time `M H * * *`, with `HH:mm` accepted as shorthand.

---

### Task 1: Regression Tests

**Files:**
- Modify: `tests/windows-lifecycle-static.ps1`
- Modify: `tests/macos-lifecycle-static.ps1`
- Modify: `tests/menu-lifecycle-docs.ps1`

**Interfaces:**
- Produces static expectations for `schedule-status`, `schedule-enable`, `schedule-disable`, Task Scheduler, LaunchAgent, auto-update logs, and non-red Windows help capture.

- [ ] Add Windows static assertions for scheduler functions, actions, menu choices, help text, and captured help output.
- [ ] Add macOS static assertions for scheduler functions, actions, menu choices, help text, and LaunchAgent plist tokens.
- [ ] Add docs/menu assertions for the new “自动更新” section.
- [ ] Run the relevant tests and verify they fail because implementation is missing.

### Task 2: Windows Implementation

**Files:**
- Modify: `scripts/windows/manage-cliproxyapi.ps1`

**Interfaces:**
- Produces `Show-ScheduledUpdateStatus`, `Enable-ScheduledUpdate`, `Disable-ScheduledUpdate`, `Read-ScheduleTimeOrDefault`, and `Test-ScheduleTime`.

- [ ] Replace direct `& $paths.Exe -h 2>&1` display with plain `System.Diagnostics.Process` capture.
- [ ] Add three schedule actions to `ValidateSet`, help, `Invoke-Action`, and menu.
- [ ] Add Task Scheduler helpers using `Register-ScheduledTask`, `Get-ScheduledTask`, and `Unregister-ScheduledTask`.
- [ ] Write stdout/stderr logs to install-dir `logs/auto-update.*.log`.
- [ ] Run Windows static tests and verify they pass.

### Task 3: macOS Implementation

**Files:**
- Modify: `scripts/macos/manage-cliproxyapi.sh`

**Interfaces:**
- Produces `show_scheduled_update_status`, `enable_scheduled_update`, `disable_scheduled_update`, `read_schedule_time_or_default`, and `validate_schedule_time`.

- [ ] Add three schedule actions to help, argument parsing, `run_action`, and menu.
- [ ] Add LaunchAgent plist creation under `~/Library/LaunchAgents`.
- [ ] Write stdout/stderr logs to install-dir `logs/auto-update.*.log`.
- [ ] Run shell syntax and macOS static tests and verify they pass.

### Task 4: Documentation and Full Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/design.md`

**Interfaces:**
- Documents default `04:00`, custom `HH:mm`, current-user scheduler scope, log paths, and existing install/update lifecycle reuse.

- [ ] Update README with menu entries and scheduled update behavior.
- [ ] Update design docs with scheduler architecture and safety notes.
- [ ] Run all AGENTS.md validation commands.
- [ ] Review `git diff` for accidental secrets, logs, install dirs, or generated runtime state.
