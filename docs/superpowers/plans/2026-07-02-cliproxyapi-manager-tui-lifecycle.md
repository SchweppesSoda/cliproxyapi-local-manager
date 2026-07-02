# CLIProxyAPI Manager TUI Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 改善 CLIProxyAPI 本地管理器的重复使用体验：静默复用安装目录，重排菜单，显示 WebUI 管理密钥，并在 Windows/macOS 上提供受管 start/status/stop 生命周期。

**Architecture:** 保留当前单脚本架构。Windows 继续使用 PowerShell 5.1 脚本，macOS 继续使用 Bash 3.2 兼容 shell；把状态派生、WebUI 信息、PID 校验和菜单布局作为同一脚本内的清晰函数边界实现。

**Tech Stack:** Windows PowerShell 5.1-compatible scripts, Bash 3.2-compatible macOS shell scripts, Markdown docs, PowerShell and shell script tests.

---

## File Structure

- `scripts/windows/manage-cliproxyapi.ps1`: Windows 参数、安装目录解析、状态派生、WebUI 信息、进程生命周期、菜单布局。
- `scripts/macos/manage-cliproxyapi.sh`: macOS 参数、安装目录解析、状态派生、WebUI 信息、后台启动、停止、菜单布局。
- `README.md`: 用户面文档，说明自动复用目录、分区菜单、WebUI 信息、受管 start/status/stop。
- `docs/design.md`: 设计文档，描述新状态模型和跨平台生命周期。
- `tests/windows-status-no-prompt.ps1`: Windows 已保存状态下 `status` 不再询问安装目录。
- `tests/macos-status-no-prompt.sh`: macOS 已保存状态下 `--status` 不再询问安装目录。
- `tests/windows-webui-info.ps1`: Windows `webui-info` 输出 WebUI URL 和完整管理密钥。
- `tests/macos-webui-info.sh`: macOS `--webui-info` 输出 WebUI URL 和完整管理密钥。
- `tests/windows-lifecycle-static.ps1`: Windows lifecycle 静态测试，覆盖 `stop`、PID 校验和不按进程名广泛杀进程。
- `tests/macos-lifecycle-static.ps1`: macOS lifecycle 静态测试，覆盖 `nohup` 后台启动、PID/log、默认启动不再 `open "$start_command"`。
- `tests/menu-lifecycle-docs.ps1`: README 和设计文档测试，覆盖菜单分区、WebUI 信息、自动目录复用、受管生命周期。

## Task 1: Windows Quiet Install Directory Resolution

**Files:**
- Create: `tests/windows-status-no-prompt.ps1`
- Modify: `scripts/windows/manage-cliproxyapi.ps1`

- [ ] **Step 1: Write the failing Windows status no-prompt test**

Create `tests/windows-status-no-prompt.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$StatePath = Join-Path $RepoRoot ".cliproxyapi-manager-state.windows.json"
$StateBackupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-manager-state.windows.{0}.json" -f ([Guid]::NewGuid().ToString("N")))
$HadState = Test-Path -LiteralPath $StatePath
$InstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-status-install-{0}" -f ([Guid]::NewGuid().ToString("N")))

try {
  if ($HadState) {
    Move-Item -LiteralPath $StatePath -Destination $StateBackupPath -Force
  }

  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Set-Content -LiteralPath (Join-Path $InstallDir "config.yaml") -Encoding UTF8 -Value @"
host: "127.0.0.1"
port: 8317

api-keys:
  - "wb-local-test"

remote-management:
  allow-remote: false
  secret-key: "mgmt-local-test"
"@
  Set-Content -LiteralPath (Join-Path $InstallDir "cli-proxy-api.exe") -Encoding ASCII -Value "placeholder"
  [ordered]@{
    installDir = $InstallDir
    lastReleaseTag = "test"
    updatedAt = (Get-Date).ToString("o")
  } | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding UTF8

  $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Action status 2>&1
  $text = $output -join "`n"

  if ($text -match "安装目录（|上次安装目录|请选择安装目录") {
    throw "status should not prompt for install directory when state exists. Output:`n$text"
  }
  if ($text -notmatch [regex]::Escape($InstallDir)) {
    throw "status should use saved install dir. Output:`n$text"
  }
  if ($text -match "mgmt-local-test") {
    throw "status must not print full WebUI management key. Output:`n$text"
  }
} finally {
  if (Test-Path -LiteralPath $StatePath) {
    Remove-Item -LiteralPath $StatePath -Force
  }
  if ($HadState -and (Test-Path -LiteralPath $StateBackupPath)) {
    Move-Item -LiteralPath $StateBackupPath -Destination $StatePath -Force
  }
  if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
  }
}

Write-Output "WINDOWS_STATUS_NO_PROMPT_OK"
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-status-no-prompt.ps1
```

Expected: FAIL because the script still calls `Select-InstallDir` and prints install directory prompts before `status`.

- [ ] **Step 3: Add Windows `-InstallDir` parameter and resolver**

In `scripts/windows/manage-cliproxyapi.ps1`, update the `param` block:

```powershell
param(
  [ValidateSet("menu", "status", "install", "config", "start", "stop", "health", "webui", "webui-info", "oauth", "device-login", "models", "workbuddy")]
  [string] $Action = "menu",
  [string] $InstallDir,
  [switch] $Help
)
```

Add this function after `Select-InstallDir`:

```powershell
function Resolve-InstallDir {
  param(
    [string] $RequestedInstallDir,
    [bool] $Interactive
  )

  if (-not [string]::IsNullOrWhiteSpace($RequestedInstallDir)) {
    $resolved = Expand-InstallPath $RequestedInstallDir
    Save-State -InstallDir $resolved -ReleaseTag ""
    return $resolved
  }

  $state = Read-State
  if ($state -and $state.installDir) {
    return (Expand-InstallPath $state.installDir)
  }

  $defaultPaths = Get-Paths $DefaultInstallDir
  if ((Test-Path -LiteralPath $defaultPaths.Exe) -or (Test-Path -LiteralPath $defaultPaths.Config)) {
    return (Expand-InstallPath $DefaultInstallDir)
  }

  if ($Interactive) {
    return Select-InstallDir
  }

  return (Expand-InstallPath $DefaultInstallDir)
}
```

- [ ] **Step 4: Use the resolver at the Windows entrypoint**

Replace the bottom entrypoint:

```powershell
$installDir = Select-InstallDir
if ($Action -eq "menu") {
  Show-Menu $installDir
} else {
  Invoke-Action -SelectedAction $Action -InstallDir $installDir
}
```

with:

```powershell
$installDir = Resolve-InstallDir -RequestedInstallDir $InstallDir -Interactive ($Action -eq "menu")
if ($Action -eq "menu") {
  Show-Menu $installDir
} else {
  Invoke-Action -SelectedAction $Action -InstallDir $installDir
}
```

- [ ] **Step 5: Run GREEN**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-status-no-prompt.ps1
```

Expected: `WINDOWS_STATUS_NO_PROMPT_OK`.

- [ ] **Step 6: Commit Task 1**

```powershell
git add -- scripts/windows/manage-cliproxyapi.ps1 tests/windows-status-no-prompt.ps1
git commit -m "fix(windows): reuse saved install directory"
```

## Task 2: macOS Quiet Install Directory Resolution

**Files:**
- Create: `tests/macos-status-no-prompt.sh`
- Modify: `scripts/macos/manage-cliproxyapi.sh`

- [ ] **Step 1: Write the failing macOS status no-prompt test**

Create `tests/macos-status-no-prompt.sh`:

```bash
#!/bin/bash

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MANAGER="$REPO_ROOT/scripts/macos/manage-cliproxyapi.sh"
STATE_FILE="$REPO_ROOT/.cliproxyapi-manager-state.macos.json"
STATE_BACKUP="${TMPDIR:-/tmp}/cliproxyapi-manager-state.macos.$$.$RANDOM.json"
INSTALL_DIR="${TMPDIR:-/tmp}/cliproxyapi-status-install-$$-$RANDOM"
HAD_STATE=0

if [ -f "$STATE_FILE" ]; then
  HAD_STATE=1
  mv "$STATE_FILE" "$STATE_BACKUP"
fi

cleanup() {
  rm -rf "$INSTALL_DIR"
  rm -f "$STATE_FILE"
  if [ "$HAD_STATE" -eq 1 ] && [ -f "$STATE_BACKUP" ]; then
    mv "$STATE_BACKUP" "$STATE_FILE"
  fi
}
trap cleanup EXIT

mkdir -p "$INSTALL_DIR"
cat > "$INSTALL_DIR/config.yaml" <<'EOF'
host: "127.0.0.1"
port: 8317

api-keys:
  - "wb-local-test"

remote-management:
  allow-remote: false
  secret-key: "mgmt-local-test"
EOF
printf 'placeholder\n' > "$INSTALL_DIR/cli-proxy-api"
chmod +x "$INSTALL_DIR/cli-proxy-api"
cat > "$STATE_FILE" <<EOF
{
  "installDir": "$(printf '%s' "$INSTALL_DIR" | sed 's/\\/\\\\/g; s/"/\\"/g')",
  "lastReleaseTag": "test",
  "updatedAt": "2026-07-02T00:00:00Z"
}
EOF

output=$("$MANAGER" --status 2>&1)

case "$output" in
  *"安装目录（"*|*"上次安装目录"*|*"请选择安装目录"*)
    printf 'status should not prompt for install directory. Output:\n%s\n' "$output" >&2
    exit 1
    ;;
esac

case "$output" in
  *"$INSTALL_DIR"*) ;;
  *)
    printf 'status should use saved install dir. Output:\n%s\n' "$output" >&2
    exit 1
    ;;
esac

case "$output" in
  *"mgmt-local-test"*)
    printf 'status must not print full WebUI management key. Output:\n%s\n' "$output" >&2
    exit 1
    ;;
esac

printf 'MACOS_STATUS_NO_PROMPT_OK\n'
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
bash .\tests\macos-status-no-prompt.sh
```

Expected: FAIL because the script still calls `select_install_dir` and prints install directory prompts.

- [ ] **Step 3: Add macOS install-dir argument parsing**

In `scripts/macos/manage-cliproxyapi.sh`, add globals before the argument `case`:

```bash
ACTION="menu"
REQUESTED_INSTALL_DIR=""
```

Replace the single-argument `case "${1:-}" in ... esac` block with:

```bash
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) show_help; exit 0 ;;
    --status) ACTION="status" ;;
    --install) ACTION="install" ;;
    --config) ACTION="config" ;;
    --start) ACTION="start" ;;
    --stop) ACTION="stop" ;;
    --health) ACTION="health" ;;
    --webui) ACTION="webui" ;;
    --webui-info) ACTION="webui-info" ;;
    --oauth) ACTION="oauth" ;;
    --device-login) ACTION="device-login" ;;
    --models) ACTION="models" ;;
    --workbuddy) ACTION="workbuddy" ;;
    --install-dir)
      shift
      if [ "$#" -eq 0 ]; then
        warn "--install-dir 需要路径参数"
        exit 1
      fi
      REQUESTED_INSTALL_DIR=$1
      ;;
    "")
      ;;
    *)
      warn "未知参数：$1"
      show_help
      exit 1
      ;;
  esac
  shift
done
```

- [ ] **Step 4: Add macOS resolver and use it at entrypoint**

Add after `select_install_dir()`:

```bash
resolve_install_dir() {
  requested_install_dir=$1
  interactive=$2

  if [ -n "$requested_install_dir" ]; then
    resolved=$(expand_install_path "$requested_install_dir")
    save_state "$resolved" ""
    printf '%s\n' "$resolved"
    return
  fi

  previous=$(read_state_value "installDir" || true)
  if [ -n "$previous" ]; then
    expand_install_path "$previous"
    return
  fi

  default_exe=$(paths_for "$DEFAULT_INSTALL_DIR" exe)
  default_config=$(paths_for "$DEFAULT_INSTALL_DIR" config)
  if [ -f "$default_exe" ] || [ -f "$default_config" ]; then
    expand_install_path "$DEFAULT_INSTALL_DIR"
    return
  fi

  if [ "$interactive" = "yes" ]; then
    select_install_dir
    return
  fi

  expand_install_path "$DEFAULT_INSTALL_DIR"
}
```

Replace:

```bash
INSTALL_DIR=$(select_install_dir)
```

with:

```bash
if [ "$ACTION" = "menu" ]; then
  INSTALL_DIR=$(resolve_install_dir "$REQUESTED_INSTALL_DIR" "yes")
else
  INSTALL_DIR=$(resolve_install_dir "$REQUESTED_INSTALL_DIR" "no")
fi
```

- [ ] **Step 5: Run GREEN**

Run:

```powershell
bash .\tests\macos-status-no-prompt.sh
```

Expected: `MACOS_STATUS_NO_PROMPT_OK`.

- [ ] **Step 6: Commit Task 2**

```powershell
git add -- scripts/macos/manage-cliproxyapi.sh tests/macos-status-no-prompt.sh
git commit -m "fix(macos): reuse saved install directory"
```

## Task 3: WebUI Information Action

**Files:**
- Create: `tests/windows-webui-info.ps1`
- Create: `tests/macos-webui-info.sh`
- Modify: `scripts/windows/manage-cliproxyapi.ps1`
- Modify: `scripts/macos/manage-cliproxyapi.sh`

- [ ] **Step 1: Write the failing Windows WebUI info test**

Create `tests/windows-webui-info.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$InstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-webui-install-{0}" -f ([Guid]::NewGuid().ToString("N")))

try {
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Set-Content -LiteralPath (Join-Path $InstallDir "config.yaml") -Encoding UTF8 -Value @"
host: "127.0.0.1"
port: 9444

api-keys:
  - "wb-local-test"

remote-management:
  allow-remote: false
  secret-key: "mgmt-local-visible"
"@

  $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Action webui-info -InstallDir $InstallDir 2>&1
  $text = $output -join "`n"

  foreach ($required in @("http://localhost:9444/management.html", "WebUI 管理密钥", "mgmt-local-visible")) {
    if ($text -notmatch [regex]::Escape($required)) {
      throw "webui-info output missing '$required'. Output:`n$text"
    }
  }
} finally {
  if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
  }
}

Write-Output "WINDOWS_WEBUI_INFO_OK"
```

- [ ] **Step 2: Write the failing macOS WebUI info test**

Create `tests/macos-webui-info.sh`:

```bash
#!/bin/bash

set -e

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
MANAGER="$REPO_ROOT/scripts/macos/manage-cliproxyapi.sh"
INSTALL_DIR="${TMPDIR:-/tmp}/cliproxyapi-webui-install-$$-$RANDOM"

cleanup() {
  rm -rf "$INSTALL_DIR"
}
trap cleanup EXIT

mkdir -p "$INSTALL_DIR"
cat > "$INSTALL_DIR/config.yaml" <<'EOF'
host: "127.0.0.1"
port: 9444

api-keys:
  - "wb-local-test"

remote-management:
  allow-remote: false
  secret-key: "mgmt-local-visible"
EOF

output=$("$MANAGER" --webui-info --install-dir "$INSTALL_DIR" 2>&1)

case "$output" in
  *"http://localhost:9444/management.html"* ) ;;
  *) printf 'missing WebUI URL. Output:\n%s\n' "$output" >&2; exit 1 ;;
esac
case "$output" in
  *"WebUI 管理密钥"* ) ;;
  *) printf 'missing WebUI key label. Output:\n%s\n' "$output" >&2; exit 1 ;;
esac
case "$output" in
  *"mgmt-local-visible"* ) ;;
  *) printf 'missing WebUI key. Output:\n%s\n' "$output" >&2; exit 1 ;;
esac

printf 'MACOS_WEBUI_INFO_OK\n'
```

- [ ] **Step 3: Run the tests to verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-webui-info.ps1
bash .\tests\macos-webui-info.sh
```

Expected: both FAIL because `webui-info` is not implemented.

- [ ] **Step 4: Implement Windows WebUI info**

Add this function after `Open-WebUI`:

```powershell
function Show-WebUIInfo {
  param([string] $InstallDir)

  $info = Get-ConfigInfo $InstallDir
  Assert-LocalOnlyConfig $InstallDir
  Write-Host ""
  Write-Host "WebUI:"
  Write-Host "http://localhost:$($info.Port)/management.html"
  Write-Host ""
  Write-Host "WebUI 管理密钥:"
  if ($info.ManagementKey) {
    Write-Host $info.ManagementKey
  } else {
    Write-Host "<未在 config.yaml remote-management.secret-key 中找到>"
  }
}
```

Update `Invoke-Action`:

```powershell
"webui-info" { Show-WebUIInfo $InstallDir }
```

Update `Open-WebUI` after printing/opening the URL:

```powershell
Write-Host "如需查看 WebUI 管理密钥，请运行 webui-info。"
```

- [ ] **Step 5: Implement macOS WebUI info**

Add this function after `open_webui()`:

```bash
show_webui_info() {
  install_dir=$1
  config=$(paths_for "$install_dir" config)
  port=$(config_value "$config" port "8317")
  management_key=$(config_value "$config" management_key "")
  assert_local_only_config "$install_dir" || return 1

  printf '\nWebUI:\n'
  printf 'http://localhost:%s/management.html\n' "$port"
  printf '\nWebUI 管理密钥:\n'
  if [ -n "$management_key" ]; then
    printf '%s\n' "$management_key"
  else
    printf '<未在 config.yaml remote-management.secret-key 中找到>\n'
  fi
}
```

Update `run_action()`:

```bash
webui-info) show_webui_info "$install_dir" ;;
```

Update `open_webui()` after `open "$url"`:

```bash
printf '如需查看 WebUI 管理密钥，请运行 --webui-info。\n'
```

- [ ] **Step 6: Run GREEN**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-webui-info.ps1
bash .\tests\macos-webui-info.sh
```

Expected:

```text
WINDOWS_WEBUI_INFO_OK
MACOS_WEBUI_INFO_OK
```

- [ ] **Step 7: Commit Task 3**

```powershell
git add -- scripts/windows/manage-cliproxyapi.ps1 scripts/macos/manage-cliproxyapi.sh tests/windows-webui-info.ps1 tests/macos-webui-info.sh
git commit -m "feat: add webui info action"
```

## Task 4: Windows Managed Lifecycle Status And Stop

**Files:**
- Create: `tests/windows-lifecycle-static.ps1`
- Modify: `scripts/windows/manage-cliproxyapi.ps1`

- [ ] **Step 1: Write the failing Windows lifecycle static test**

Create `tests/windows-lifecycle-static.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$text = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

foreach ($required in @(
  '"stop"',
  'function Get-ManagedProcess',
  'function Get-ServiceState',
  'function Stop-CLIProxyAPI',
  'Get-CimInstance',
  'Win32_Process',
  'CommandLine',
  'Stop-Process -Id',
  'stale-pid',
  'WebUI 管理密钥: 已配置'
)) {
  if ($text -notmatch [regex]::Escape($required)) {
    throw "Windows lifecycle implementation is missing token: $required"
  }
}

foreach ($forbidden in @('Stop-Process -Name', 'Get-Process cli-proxy-api', 'taskkill /IM', 'pkill')) {
  if ($text -match [regex]::Escape($forbidden)) {
    throw "Windows lifecycle must not use broad process-name termination token: $forbidden"
  }
}

Write-Output "WINDOWS_LIFECYCLE_STATIC_OK"
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-lifecycle-static.ps1
```

Expected: FAIL because `stop`, managed process validation, and status service state are missing.

- [ ] **Step 3: Implement Windows managed process helpers**

Add after `Assert-LocalOnlyConfig`:

```powershell
function Get-ManagedProcess {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  if (-not (Test-Path -LiteralPath $paths.PidFile)) {
    return $null
  }

  $pidText = (Get-Content -LiteralPath $paths.PidFile -Raw -Encoding ASCII).Trim()
  if ($pidText -notmatch '^\d+$') {
    return [ordered]@{ State = "stale-pid"; Id = $pidText; Process = $null; Reason = "PID 文件不是数字" }
  }

  $processId = [int]$pidText
  $process = Get-CimInstance Win32_Process -Filter "ProcessId = $processId" -ErrorAction SilentlyContinue
  if (-not $process) {
    return [ordered]@{ State = "stale-pid"; Id = $processId; Process = $null; Reason = "PID 对应进程不存在" }
  }

  $exePath = [System.IO.Path]::GetFullPath($paths.Exe)
  $configPath = [System.IO.Path]::GetFullPath($paths.Config)
  $processPath = ""
  if ($process.ExecutablePath) {
    $processPath = [System.IO.Path]::GetFullPath($process.ExecutablePath)
  }
  $commandLine = [string] $process.CommandLine
  $pathMatches = $processPath -and ($processPath -ieq $exePath)
  $commandMatches = ($commandLine -like "*$exePath*") -or ($commandLine -like "*$configPath*")

  if (-not ($pathMatches -or $commandMatches)) {
    return [ordered]@{ State = "stale-pid"; Id = $processId; Process = $process; Reason = "PID 对应进程不匹配当前安装目录" }
  }

  return [ordered]@{ State = "running"; Id = $processId; Process = $process; Reason = "" }
}

function Get-ServiceState {
  param([string] $InstallDir)

  $managed = Get-ManagedProcess $InstallDir
  if (-not $managed) {
    return [ordered]@{ Label = "已停止"; Detail = ""; State = "stopped" }
  }
  if ($managed.State -eq "running") {
    return [ordered]@{ Label = "运行中"; Detail = "PID $($managed.Id)"; State = "running" }
  }
  return [ordered]@{ Label = "stale-pid"; Detail = "$($managed.Reason)"; State = "stale-pid" }
}
```

- [ ] **Step 4: Use lifecycle helpers in Windows status and start**

In `Show-Status`, after printing port, add:

```powershell
$serviceState = Get-ServiceState $InstallDir
$webuiKeyState = if ($info.ManagementKey) { "已配置" } else { "未配置" }
Write-Host "服务状态:   $($serviceState.Label) $($serviceState.Detail)"
Write-Host "WebUI 管理密钥: $webuiKeyState"
```

At the start of `Start-CLIProxyAPI`, after `Assert-LocalOnlyConfig $InstallDir`, add:

```powershell
$managed = Get-ManagedProcess $InstallDir
if ($managed -and $managed.State -eq "running") {
  Write-Ok "CLIProxyAPI 已在运行，PID: $($managed.Id)"
  return
}
if ($managed -and $managed.State -eq "stale-pid") {
  Write-Warn "发现 stale PID: $($managed.Reason)"
}
```

- [ ] **Step 5: Implement Windows stop action**

Add after `Start-CLIProxyAPI`:

```powershell
function Stop-CLIProxyAPI {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $managed = Get-ManagedProcess $InstallDir
  if (-not $managed) {
    Write-Warn "没有找到受管 PID 文件，CLIProxyAPI 未由此管理器启动或已经停止。"
    return
  }
  if ($managed.State -eq "stale-pid") {
    Write-Warn "删除 stale PID 文件: $($managed.Reason)"
    Remove-Item -LiteralPath $paths.PidFile -Force -ErrorAction SilentlyContinue
    return
  }

  Stop-Process -Id $managed.Id -ErrorAction Stop
  Remove-Item -LiteralPath $paths.PidFile -Force -ErrorAction SilentlyContinue
  Write-Ok "CLIProxyAPI 已停止，PID: $($managed.Id)"
}
```

Update `Invoke-Action`:

```powershell
"stop" { Stop-CLIProxyAPI $InstallDir }
```

- [ ] **Step 6: Run GREEN**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-lifecycle-static.ps1
```

Expected: `WINDOWS_LIFECYCLE_STATIC_OK`.

- [ ] **Step 7: Commit Task 4**

```powershell
git add -- scripts/windows/manage-cliproxyapi.ps1 tests/windows-lifecycle-static.ps1
git commit -m "feat(windows): manage cli proxy lifecycle"
```

## Task 5: macOS Managed Background Lifecycle

**Files:**
- Create: `tests/macos-lifecycle-static.ps1`
- Modify: `scripts/macos/manage-cliproxyapi.sh`

- [ ] **Step 1: Write the failing macOS lifecycle static test**

Create `tests/macos-lifecycle-static.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\macos\manage-cliproxyapi.sh"
$text = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

foreach ($required in @(
  '--stop',
  'stop_clip_proxy_api()',
  'managed_process_state()',
  'pid_file)',
  'stdout_log)',
  'stderr_log)',
  'nohup "$exe" -config "$config"',
  'echo $! > "$pid_file"',
  'ps -p "$pid" -o args=',
  'kill "$pid"',
  'stale-pid'
)) {
  if ($text -notmatch [regex]::Escape($required)) {
    throw "macOS lifecycle implementation is missing token: $required"
  }
}

$startIndex = $text.IndexOf("start_clip_proxy_api()")
$healthIndex = $text.IndexOf("health_check()", $startIndex)
if ($startIndex -lt 0 -or $healthIndex -lt $startIndex) {
  throw "Could not locate start_clip_proxy_api body"
}
$startBody = $text.Substring($startIndex, $healthIndex - $startIndex)
if ($startBody -match [regex]::Escape('open "$start_command"')) {
  throw 'macOS default start should not open the foreground .command launcher'
}

foreach ($forbidden in @('pkill', 'killall', 'kill -9')) {
  if ($text -match [regex]::Escape($forbidden)) {
    throw "macOS lifecycle must not use broad or forced termination token: $forbidden"
  }
}

Write-Output "MACOS_LIFECYCLE_STATIC_OK"
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\macos-lifecycle-static.ps1
```

Expected: FAIL because macOS still opens the foreground `.command` launcher and lacks PID/log lifecycle.

- [ ] **Step 3: Extend macOS paths and layout**

Update `paths_for()`:

```bash
logs) printf '%s/logs\n' "$install_dir" ;;
stdout_log) printf '%s/logs/cli-proxy-api.stdout.log\n' "$install_dir" ;;
stderr_log) printf '%s/logs/cli-proxy-api.stderr.log\n' "$install_dir" ;;
pid_file) printf '%s/cli-proxy-api.pid\n' "$install_dir" ;;
```

Update `ensure_install_layout()`:

```bash
mkdir -p "$install_dir" "$(paths_for "$install_dir" auth)" "$(paths_for "$install_dir" backups)" "$(paths_for "$install_dir" downloads)" "$(paths_for "$install_dir" logs)"
```

- [ ] **Step 4: Add macOS managed process helpers**

Add after `assert_local_only_config()`:

```bash
managed_process_state() {
  install_dir=$1
  pid_file=$(paths_for "$install_dir" pid_file)
  exe=$(paths_for "$install_dir" exe)
  config=$(paths_for "$install_dir" config)

  if [ ! -f "$pid_file" ]; then
    printf 'stopped\t\t\n'
    return
  fi

  pid=$(sed -n '1p' "$pid_file" | tr -d '[:space:]')
  case "$pid" in
    ''|*[!0-9]*)
      printf 'stale-pid\t%s\tPID 文件不是数字\n' "$pid"
      return
      ;;
  esac

  args=$(ps -p "$pid" -o args= 2>/dev/null || true)
  if [ -z "$args" ]; then
    printf 'stale-pid\t%s\tPID 对应进程不存在\n' "$pid"
    return
  fi

  case "$args" in
    *"$exe"*|*"$config"*)
      printf 'running\t%s\t\n' "$pid"
      ;;
    *)
      printf 'stale-pid\t%s\tPID 对应进程不匹配当前安装目录\n' "$pid"
      ;;
  esac
}

service_status_text() {
  install_dir=$1
  state_line=$(managed_process_state "$install_dir")
  state=$(printf '%s' "$state_line" | awk -F '\t' '{print $1}')
  pid=$(printf '%s' "$state_line" | awk -F '\t' '{print $2}')
  reason=$(printf '%s' "$state_line" | awk -F '\t' '{print $3}')
  case "$state" in
    running) printf '运行中 PID %s\n' "$pid" ;;
    stale-pid) printf 'stale-pid %s\n' "$reason" ;;
    *) printf '已停止\n' ;;
  esac
}
```

- [ ] **Step 5: Implement macOS background start and stop**

Replace `start_clip_proxy_api()` body after validation with:

```bash
  ensure_install_layout "$install_dir"
  state_line=$(managed_process_state "$install_dir")
  state=$(printf '%s' "$state_line" | awk -F '\t' '{print $1}')
  pid=$(printf '%s' "$state_line" | awk -F '\t' '{print $2}')
  reason=$(printf '%s' "$state_line" | awk -F '\t' '{print $3}')
  pid_file=$(paths_for "$install_dir" pid_file)
  stdout_log=$(paths_for "$install_dir" stdout_log)
  stderr_log=$(paths_for "$install_dir" stderr_log)

  if [ "$state" = "running" ]; then
    ok "CLIProxyAPI 已在运行，PID: $pid"
    return 0
  fi
  if [ "$state" = "stale-pid" ]; then
    warn "发现 stale PID：$reason"
  fi

  write_start_scripts "$install_dir"
  info "后台启动 CLIProxyAPI"
  (
    cd "$install_dir" || exit 1
    nohup "$exe" -config "$config" >"$stdout_log" 2>"$stderr_log" &
    echo $! > "$pid_file"
  )
  ok "CLIProxyAPI 已后台启动，PID: $(cat "$pid_file")"
  printf 'stdout 日志：%s\n' "$stdout_log"
  printf 'stderr 日志：%s\n' "$stderr_log"
```

Add after `start_clip_proxy_api()`:

```bash
stop_clip_proxy_api() {
  install_dir=$1
  pid_file=$(paths_for "$install_dir" pid_file)
  state_line=$(managed_process_state "$install_dir")
  state=$(printf '%s' "$state_line" | awk -F '\t' '{print $1}')
  pid=$(printf '%s' "$state_line" | awk -F '\t' '{print $2}')
  reason=$(printf '%s' "$state_line" | awk -F '\t' '{print $3}')

  case "$state" in
    running)
      kill "$pid"
      sleep 1
      if ps -p "$pid" >/dev/null 2>&1; then
        warn "进程仍在运行，请先查看日志后手动处理 PID: $pid"
        return 1
      fi
      rm -f "$pid_file"
      ok "CLIProxyAPI 已停止，PID: $pid"
      ;;
    stale-pid)
      warn "删除 stale PID 文件：$reason"
      rm -f "$pid_file"
      ;;
    *)
      warn "没有找到受管 PID 文件，CLIProxyAPI 未由此管理器启动或已经停止。"
      ;;
  esac
}
```

Update `run_action()`:

```bash
stop) stop_clip_proxy_api "$install_dir" ;;
```

- [ ] **Step 6: Show macOS service state in status**

In `show_status()`, add:

```bash
management_key=$(config_value "$config" management_key "")
webui_key_state="未配置"
if [ -n "$management_key" ]; then
  webui_key_state="已配置"
fi
printf '服务状态：    %s\n' "$(service_status_text "$install_dir")"
printf 'PID 文件：    %s\n' "$(paths_for "$install_dir" pid_file)"
printf '日志目录：    %s\n' "$(paths_for "$install_dir" logs)"
printf 'WebUI 管理密钥：%s\n' "$webui_key_state"
```

- [ ] **Step 7: Run GREEN**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\macos-lifecycle-static.ps1
```

Expected: `MACOS_LIFECYCLE_STATIC_OK`.

- [ ] **Step 8: Commit Task 5**

```powershell
git add -- scripts/macos/manage-cliproxyapi.sh tests/macos-lifecycle-static.ps1
git commit -m "feat(macos): manage cli proxy lifecycle"
```

## Task 6: Sectioned Menu Layout

**Files:**
- Modify: `scripts/windows/manage-cliproxyapi.ps1`
- Modify: `scripts/macos/manage-cliproxyapi.sh`

- [ ] **Step 1: Extend Windows menu rendering**

In `scripts/windows/manage-cliproxyapi.ps1`, add helper functions before `Show-Menu`:

```powershell
function Format-ShortPath {
  param(
    [string] $Path,
    [int] $MaxLength = 68
  )
  if ([string]::IsNullOrWhiteSpace($Path) -or $Path.Length -le $MaxLength) {
    return $Path
  }
  $headLength = [Math]::Max(10, [int](($MaxLength - 3) / 2))
  $tailLength = $MaxLength - 3 - $headLength
  return ($Path.Substring(0, $headLength) + "..." + $Path.Substring($Path.Length - $tailLength))
}

function Get-MenuSummary {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $info = Get-ConfigInfo $InstallDir
  $core = if (Test-Path -LiteralPath $paths.Exe) { "已安装" } else { "缺失" }
  $config = if (Test-Path -LiteralPath $paths.Config) { "已生成" } else { "缺失" }
  $service = Get-ServiceState $InstallDir
  return "核心: $core | 配置: $config | 服务: $($service.Label) $($service.Detail) | 端口: $($info.Port)"
}
```

Replace `Show-Menu` menu body with the sectioned layout:

```powershell
Write-Host ""
Write-Host "CLIProxyAPI 本地管理器"
Write-Host "目录: $(Format-ShortPath $InstallDir)"
Write-Host (Get-MenuSummary $InstallDir)
Write-Host ""
Write-Host "[安装配置]  1 安装/更新        2 生成配置"
Write-Host "[服务运行]  3 启动服务          4 停止服务          5 运行状态"
Write-Host "[WebUI]     6 WebUI 信息        7 打开 WebUI"
Write-Host "[登录]      8 浏览器 OAuth      9 设备码登录"
Write-Host "[检查集成]  10 健康检查         11 模型列表         12 WorkBuddy 信息"
Write-Host "[设置]      D 更改安装目录      Q 退出"
$choice = Read-Host "请选择"
```

Update choices:

```powershell
"1" { Install-OrUpdate $InstallDir }
"2" { Generate-Config $InstallDir }
"3" { Start-CLIProxyAPI $InstallDir }
"4" { Stop-CLIProxyAPI $InstallDir }
"5" { Show-Status $InstallDir }
"6" { Show-WebUIInfo $InstallDir }
"7" { Open-WebUI $InstallDir }
"8" { Invoke-CodexLogin -InstallDir $InstallDir -DeviceCode $false }
"9" { Invoke-CodexLogin -InstallDir $InstallDir -DeviceCode $true }
"10" { Test-Health $InstallDir }
"11" { Query-Models $InstallDir }
"12" { Show-WorkBuddyInfo $InstallDir }
"D" { $InstallDir = Select-InstallDir; Save-State -InstallDir $InstallDir -ReleaseTag "" }
"d" { $InstallDir = Select-InstallDir; Save-State -InstallDir $InstallDir -ReleaseTag "" }
"Q" { return }
"q" { return }
"0" { return }
```

- [ ] **Step 2: Extend macOS menu rendering**

In `scripts/macos/manage-cliproxyapi.sh`, add helpers before `show_menu()`:

```bash
short_path() {
  path=$1
  max_len=${2:-68}
  len=${#path}
  if [ "$len" -le "$max_len" ]; then
    printf '%s\n' "$path"
    return
  fi
  head_len=$(( (max_len - 3) / 2 ))
  tail_len=$(( max_len - 3 - head_len ))
  head=$(printf '%s' "$path" | cut -c 1-"$head_len")
  tail=$(printf '%s' "$path" | rev | cut -c 1-"$tail_len" | rev)
  printf '%s...%s\n' "$head" "$tail"
}

menu_summary() {
  install_dir=$1
  exe=$(paths_for "$install_dir" exe)
  config=$(paths_for "$install_dir" config)
  port=$(config_value "$config" port "8317")
  core="缺失"
  config_state="缺失"
  if [ -f "$exe" ]; then core="已安装"; fi
  if [ -f "$config" ]; then config_state="已生成"; fi
  service=$(service_status_text "$install_dir")
  printf '核心: %s | 配置: %s | 服务: %s | 端口: %s\n' "$core" "$config_state" "$service" "$port"
}
```

Replace the body of `show_menu()` with:

```bash
show_menu() {
  install_dir=$1
  while :; do
    printf '\nCLIProxyAPI 本地管理器\n'
    printf '目录: %s\n' "$(short_path "$install_dir")"
    menu_summary "$install_dir"
    printf '\n'
    printf '[安装配置]  1 安装/更新        2 生成配置\n'
    printf '[服务运行]  3 启动服务          4 停止服务          5 运行状态\n'
    printf '[WebUI]     6 WebUI 信息        7 打开 WebUI\n'
    printf '[登录]      8 浏览器 OAuth      9 设备码登录\n'
    printf '[检查集成]  10 健康检查         11 模型列表         12 WorkBuddy 信息\n'
    printf '[设置]      D 更改安装目录      Q 退出\n'
    printf '请选择： '
    IFS= read -r choice

    case "$choice" in
      1) install_or_update "$install_dir" ;;
      2) generate_config "$install_dir" ;;
      3) start_clip_proxy_api "$install_dir" ;;
      4) stop_clip_proxy_api "$install_dir" ;;
      5) show_status "$install_dir" ;;
      6) show_webui_info "$install_dir" ;;
      7) open_webui "$install_dir" ;;
      8) codex_login "$install_dir" browser ;;
      9) codex_login "$install_dir" device ;;
      10) health_check "$install_dir" ;;
      11) query_models "$install_dir" ;;
      12) show_workbuddy_info "$install_dir" ;;
      D|d) install_dir=$(select_install_dir); save_state "$install_dir" "" ;;
      Q|q|0) return 0 ;;
      *) warn "未知选项：$choice" ;;
    esac
  done
}
```

- [ ] **Step 3: Smoke test menu help text**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\manage-cliproxyapi.ps1 -Help
bash -n .\scripts\macos\manage-cliproxyapi.sh
```

Expected: Windows help prints successfully; `bash -n` exits 0.

- [ ] **Step 4: Commit Task 6**

```powershell
git add -- scripts/windows/manage-cliproxyapi.ps1 scripts/macos/manage-cliproxyapi.sh
git commit -m "feat: group manager menu sections"
```

## Task 7: Documentation For TUI And Lifecycle

**Files:**
- Create: `tests/menu-lifecycle-docs.ps1`
- Modify: `README.md`
- Modify: `docs/design.md`

- [ ] **Step 1: Write the failing docs test**

Create `tests/menu-lifecycle-docs.ps1`:

```powershell
$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ReadmePath = Join-Path $RepoRoot "README.md"
$DesignPath = Join-Path $RepoRoot "docs\design.md"
$text = @(
  Get-Content -LiteralPath $ReadmePath -Raw -Encoding UTF8
  Get-Content -LiteralPath $DesignPath -Raw -Encoding UTF8
) -join "`n"

foreach ($required in @(
  "自动复用安装目录",
  "WebUI 信息",
  "WebUI 管理密钥",
  "status 不显示完整密钥",
  "启动服务",
  "停止服务",
  "运行状态",
  "cli-proxy-api.pid",
  "logs/cli-proxy-api.stdout.log",
  "管理器只停止自己验证过的 PID"
)) {
  if ($text -notmatch [regex]::Escape($required)) {
    throw "docs are missing lifecycle/menu text: $required"
  }
}

Write-Output "MENU_LIFECYCLE_DOCS_OK"
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\menu-lifecycle-docs.ps1
```

Expected: FAIL because the docs do not yet describe the new lifecycle and menu contract.

- [ ] **Step 3: Update README**

In `README.md`, update the management menu section so it includes:

```markdown
## 管理菜单

脚本启动后会自动复用上次安装目录。首次没有状态文件时，交互菜单才会询问安装目录；后续可通过 `D 更改安装目录` 显式切换。

菜单按功能分区：

```text
[安装配置]  安装/更新、生成配置
[服务运行]  启动服务、停止服务、运行状态
[WebUI]     WebUI 信息、打开 WebUI
[登录]      浏览器 OAuth、设备码登录
[检查集成]  健康检查、模型列表、WorkBuddy 信息
[设置]      更改安装目录、退出
```

`WebUI 信息` 会显示 WebUI URL 和完整 WebUI 管理密钥。`status` 不显示完整密钥，只显示是否已配置。
```

Add lifecycle text:

```markdown
## 受管进程生命周期

后台启动会在安装目录写入：

```text
cli-proxy-api.pid
logs/cli-proxy-api.stdout.log
logs/cli-proxy-api.stderr.log
```

`运行状态` 会读取 PID 并验证进程是否仍匹配当前安装目录。`停止服务` 只停止管理器自己验证过的 PID；不会按进程名批量结束其他 `cli-proxy-api` 进程。
```

- [ ] **Step 4: Update docs/design.md**

Add the same architecture-level statements:

```markdown
## 交互菜单与状态摘要

管理器使用分区菜单，而不是平铺功能列表。菜单顶部显示安装目录、核心程序、配置、服务状态和端口；WebUI 管理密钥只在显式 `WebUI 信息` 动作中完整显示，`status` 只显示是否已配置。

## 受管进程生命周期

Windows 和 macOS 都使用安装目录中的 `cli-proxy-api.pid` 以及 `logs/cli-proxy-api.stdout.log`、`logs/cli-proxy-api.stderr.log`。启动前检查已有 PID；停止时验证 PID 的路径或命令行匹配当前安装目录和配置。管理器只停止自己验证过的 PID。
```

- [ ] **Step 5: Run GREEN**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\menu-lifecycle-docs.ps1
```

Expected: `MENU_LIFECYCLE_DOCS_OK`.

- [ ] **Step 6: Commit Task 7**

```powershell
git add -- README.md docs/design.md tests/menu-lifecycle-docs.ps1
git commit -m "docs: describe manager lifecycle menu"
```

## Task 8: Full Verification

**Files:**
- Verify all changed files.

- [ ] **Step 1: Run Windows tests**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-default-install-dir.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-status-no-prompt.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-health-endpoint.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-start-background-static.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-help-localized.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-webui-info.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\windows-lifecycle-static.ps1
```

Expected: each test prints its `*_OK` marker.

- [ ] **Step 2: Run macOS/static shell tests**

Run:

```powershell
bash .\tests\macos-default-install-dir.sh
bash .\tests\macos-status-no-prompt.sh
bash .\tests\macos-webui-info.sh
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\macos-health-endpoint-static.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\macos-lifecycle-static.ps1
```

Expected: each test prints its `*_OK` marker.

- [ ] **Step 3: Run docs tests**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\readme-workflow-docs.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\menu-lifecycle-docs.ps1
```

Expected: both docs tests print their `*_OK` marker.

- [ ] **Step 4: Validate syntax and whitespace**

Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\manage-cliproxyapi.ps1 -Help
bash -n .\scripts\macos\manage-cliproxyapi.sh
git diff --check
git diff --stat
```

Expected: help renders, `bash -n` exits 0, `git diff --check` has no output, and diff stat only includes planned files.

- [ ] **Step 5: Commit any verification-only fixes**

If verification required small fixes, commit them:

```powershell
git add -- README.md docs/design.md scripts/windows/manage-cliproxyapi.ps1 scripts/macos/manage-cliproxyapi.sh tests
git commit -m "fix: verify manager lifecycle changes"
```
