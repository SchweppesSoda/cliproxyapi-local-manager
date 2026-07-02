# CLIProxyAPI Manager UX Health Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix CLIProxyAPI Local Manager health checks, Windows background startup, Chinese user-facing guidance, and login explanation.

**Architecture:** Keep the existing single-script-per-platform structure. Replace the invalid `/health` probe with authenticated `/v1/models`, make Windows startup hidden with explicit logs, and update docs/menu text without changing public action names.

**Tech Stack:** Windows PowerShell 5.1-compatible scripts, Bash 3.2-compatible macOS scripts, Markdown docs, script-based tests.

---

## File Structure

- `scripts/windows/manage-cliproxyapi.ps1`: Windows behavior, menu/help text, health check, background start.
- `manage-cliproxyapi.cmd` and `scripts/windows/manage-cliproxyapi.cmd`: UTF-8 console setup before launching PowerShell.
- `scripts/macos/manage-cliproxyapi.sh`: macOS health check and user-facing text.
- `manage-cliproxyapi.command`: macOS Finder close prompt.
- `README.md`: Chinese workflow and Codex login explanation.
- `docs/design.md`: high-level design updated to current behavior.
- `tests/windows-health-endpoint.ps1`: Windows health endpoint behavior test.
- `tests/windows-start-background-static.ps1`: Windows startup static behavior test.
- `tests/windows-help-localized.ps1`: Windows help localization test.
- `tests/macos-health-endpoint-static.ps1`: macOS health endpoint static test.
- `tests/readme-workflow-docs.ps1`: README workflow documentation test.

### Task 1: Windows Health Check Test And Fix

**Files:**
- Create: `tests/windows-health-endpoint.ps1`
- Modify: `scripts/windows/manage-cliproxyapi.ps1`

- [ ] **Step 1: Write the failing test**

Create a PowerShell test that starts a local mock HTTP listener, writes a temporary `config.yaml`, runs `-Action health`, and asserts the request is `GET /v1/models` with `Authorization: Bearer wb-local-testkey`.

- [ ] **Step 2: Run the test to verify RED**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-health-endpoint.ps1`

Expected before implementation: FAIL because the script requests `/health` without the bearer token.

- [ ] **Step 3: Implement the minimal fix**

Change `Test-Health` to:
- read `ClientKey` from `Get-ConfigInfo`;
- prompt only if missing;
- request `/v1/models`;
- pass `Authorization = "Bearer $clientKey"`;
- treat success as API availability, not generic `/health`.

- [ ] **Step 4: Run GREEN**

Run the same test. Expected: `WINDOWS_HEALTH_ENDPOINT_OK`.

### Task 2: Windows Background Startup Test And Fix

**Files:**
- Create: `tests/windows-start-background-static.ps1`
- Modify: `scripts/windows/manage-cliproxyapi.ps1`

- [ ] **Step 1: Write the failing static test**

Assert the Windows script contains `-WindowStyle Hidden`, `-RedirectStandardOutput`, `-RedirectStandardError`, `-PassThru`, and no longer uses `Start-Process powershell.exe` inside `Start-CLIProxyAPI`.

- [ ] **Step 2: Run RED**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-start-background-static.ps1`

Expected before implementation: FAIL because startup opens PowerShell without hidden mode or redirects.

- [ ] **Step 3: Implement minimal background start**

Add `Logs`, `StdoutLog`, `StderrLog`, and `PidFile` to `Get-Paths`; create `logs/` in `Ensure-InstallLayout`; update `Start-CLIProxyAPI` to launch `$paths.Exe` directly with hidden window, stdout/stderr redirects, and `-PassThru`; write PID to `PidFile`; print PID and log paths.

- [ ] **Step 4: Run GREEN**

Run the same test. Expected: `WINDOWS_START_BACKGROUND_STATIC_OK`.

### Task 3: Chinese Windows Help/Menu And Encoding

**Files:**
- Create: `tests/windows-help-localized.ps1`
- Modify: `scripts/windows/manage-cliproxyapi.ps1`
- Modify: `manage-cliproxyapi.cmd`
- Modify: `scripts/windows/manage-cliproxyapi.cmd`

- [ ] **Step 1: Write failing help localization test**

Assert `-Help` output contains `CLIProxyAPI 本地管理器`, `后台启动`, `API 可用性检查`, `Codex 浏览器 OAuth 登录`, and `Codex 设备码登录`.

- [ ] **Step 2: Run RED**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-help-localized.ps1`

Expected before implementation: FAIL because help is English.

- [ ] **Step 3: Implement localized text and encoding setup**

Translate help, menu, key status/config/start/health messages, and add `[Console]::InputEncoding = [System.Text.Encoding]::UTF8`. Add `chcp 65001 >nul` to Windows `.cmd` wrappers.

- [ ] **Step 4: Run GREEN**

Run the same test. Expected: `WINDOWS_HELP_LOCALIZED_OK`.

### Task 4: macOS Health And Text

**Files:**
- Create: `tests/macos-health-endpoint-static.ps1`
- Modify: `scripts/macos/manage-cliproxyapi.sh`
- Modify: `manage-cliproxyapi.command`

- [ ] **Step 1: Write failing static test**

Assert macOS script no longer contains `/health`, contains `/v1/models`, and sends `Authorization: Bearer`.

- [ ] **Step 2: Run RED**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\macos-health-endpoint-static.ps1`

Expected before implementation: FAIL because script still uses `/health`.

- [ ] **Step 3: Implement macOS changes**

Change `health_check` to request `/v1/models` with the first API key. Translate help/menu/user-facing messages that match Windows terms. Translate Finder close prompt.

- [ ] **Step 4: Run GREEN**

Run the same test. Expected: `MACOS_HEALTH_ENDPOINT_STATIC_OK`.

### Task 5: README And Design Docs

**Files:**
- Create: `tests/readme-workflow-docs.ps1`
- Modify: `README.md`
- Modify: `docs/design.md`

- [ ] **Step 1: Write failing docs test**

Assert README contains `推荐操作顺序`, `Codex 浏览器 OAuth 登录`, `Codex 设备码登录`, `两种方式都会使用当前安装目录`, and `/v1/models`.

- [ ] **Step 2: Run RED**

Run: `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\readme-workflow-docs.ps1`

Expected before implementation: FAIL because README lacks the new operation order and login comparison text.

- [ ] **Step 3: Implement docs**

Update README management menu, workflow, health check wording, WorkBuddy wording, FAQ, and design doc to reflect authenticated `/v1/models`, background start, and login differences.

- [ ] **Step 4: Run GREEN**

Run the same test. Expected: `README_WORKFLOW_DOCS_OK`.

### Task 6: Full Verification

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run all tests**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-default-install-dir.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-health-endpoint.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-start-background-static.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-help-localized.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\macos-health-endpoint-static.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\readme-workflow-docs.ps1
```

Expected: all tests print their `*_OK` marker.

- [ ] **Step 2: Review diff**

Run: `git diff --check` and `git diff --stat`.

Expected: no whitespace errors; changed files match this plan.
