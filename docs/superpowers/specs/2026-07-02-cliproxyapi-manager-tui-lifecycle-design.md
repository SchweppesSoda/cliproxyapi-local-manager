# CLIProxyAPI Manager TUI And Lifecycle Design

## Background

The current CLIProxyAPI Local Manager has the right core operations, but the interaction model is now getting in the way. After CLIProxyAPI has already been installed, opening the script still asks for the install directory because both platform entrypoints call the directory selector before running any menu or action. The menu is also a flat list, so setup, runtime control, WebUI access, login, diagnostics, integration output, and settings compete at the same level.

The manager already parses the WebUI management key from `config.yaml`, but only shows it at config generation time. Windows can start CLIProxyAPI in the background and writes a PID file, but status does not validate whether the PID is actually running, and there is no stop action. macOS still opens a Terminal foreground launcher for start, so it does not match the documented background/log/PID lifecycle.

## Goals

- Stop prompting for install location on normal repeat use.
- Show a denser, cleaner terminal menu with stable sections and a status summary.
- Add a WebUI information action that shows the WebUI URL and full management key.
- Keep `status` useful but avoid printing full secrets there.
- Add managed start, status, and stop lifecycle behavior on both Windows and macOS.
- Preserve the current script-based architecture: PowerShell 5.1 on Windows, Bash 3.2-compatible shell on macOS.
- Keep non-interactive actions script-friendly and non-blocking.

## Non-Goals

- Do not build a full-screen alternate-screen TUI.
- Do not add new runtime dependencies such as `jq`, curses, Textual, Bubble Tea, or Node.
- Do not create Windows Services, LaunchAgents, LaunchDaemons, or automatic startup.
- Do not kill arbitrary `cli-proxy-api` processes by name.
- Do not write secrets to the manager state file, logs, tests, or documentation examples.
- Do not change the local-only security boundary.

## Chosen Approach

Use the existing script architecture and redesign the interaction surface around three pieces:

1. A quiet install-directory resolver that reuses known state unless the user explicitly changes it.
2. A sectioned menu with a compact status header.
3. A managed process lifecycle using PID files, log files, and path/command validation.

This keeps the implementation small enough to verify with the current test style while addressing the real workflow problems.

## Install Directory Resolution

Entry flow becomes:

```text
Load state
Resolve install directory
Run action or menu
```

Resolution rules:

- If the user passed an explicit install directory, use it and save it.
- If state contains an install directory, silently reuse it.
- If state is missing and the default install directory contains a usable install or config, use the default directory.
- If running the interactive menu for the first time and no useful directory is known, ask for the directory once.
- If running a non-interactive action and no directory is known, use the default directory and print clear missing-file guidance if the requested action cannot run.
- Only the menu action `D` / "Change install directory" should open the directory prompt after first setup.

Windows should add `-InstallDir <path>`. macOS should add `--install-dir <path>`. Existing action names stay compatible.

## Status Model

Status is derived from files and runtime checks instead of being fully persisted.

States:

- `core`: `installed` when the executable exists, otherwise `missing`.
- `config`: `configured` when `config.yaml` exists and passes local-only checks, otherwise `missing` or `unsafe`.
- `service`: `running`, `stopped`, or `stale-pid`.
- `api`: `ready`, `unreachable`, `unauthorized`, or `unknown`.
- `webuiKey`: `configured` when `remote-management.secret-key` is present, otherwise `missing`.

`status` should print paths, executable/config existence, host, port, PID file, log files, and derived service state. It should not print the full WebUI management key.

## Menu Layout

The interactive menu should use a fixed, sectioned information architecture rather than a flat list.

Target shape:

```text
CLIProxyAPI 本地管理器
目录: .../CLIProxyAPI
核心: 已安装 | 配置: 已生成 | 服务: 运行中 PID 1234 | 端口: 8317

[安装配置]  1 安装/更新        2 生成配置
[服务运行]  3 启动服务          4 停止服务          5 运行状态
[WebUI]     6 WebUI 信息        7 打开 WebUI
[登录]      8 浏览器 OAuth      9 设备码登录
[检查集成]  10 健康检查         11 模型列表         12 WorkBuddy 信息
[设置]      D 更改安装目录      Q 退出
```

Design constraints:

- Fit the essential menu in an 80x24 terminal.
- Truncate very long install paths with a middle ellipsis in the menu header.
- Keep detailed logs, JSON model output, and install download output in action result screens rather than the menu header.
- Use color only as an enhancement. Text labels such as `已安装`, `缺失`, `运行中`, and `已停止` must carry meaning without color.
- Windows should use `Write-Host -ForegroundColor` where useful. macOS may use `tput` only when stdout is a TTY and `TERM` is not `dumb`.
- Non-interactive actions should not clear the screen or print decorative chrome.

## WebUI Information

Add a `webui-info` action on both platforms:

- Windows: `-Action webui-info`
- macOS: `--webui-info`

The interactive menu label is `WebUI 信息`.

Output includes:

```text
WebUI:
http://localhost:<port>/management.html

WebUI 管理密钥:
<remote-management.secret-key>
```

This action intentionally prints the full management key because the user explicitly asked for a way to see it. `status` only prints `WebUI 管理密钥: 已配置` or `未配置`.

`webui` continues to open the URL. It may also print a short reminder to use `webui-info` for the key.

## Process Lifecycle

Both platforms should use the same managed files in the install directory:

```text
cli-proxy-api.pid
logs/cli-proxy-api.stdout.log
logs/cli-proxy-api.stderr.log
```

### Windows

Windows keeps the existing background start model:

```text
Start-Process <exe> -WorkingDirectory <installDir> -ArgumentList -config <config> -WindowStyle Hidden -RedirectStandardOutput <stdout> -RedirectStandardError <stderr> -PassThru
```

Before starting:

- Check the existing PID file.
- If it points to a running process whose path/command matches the managed executable/config, report that CLIProxyAPI is already running.
- If it points to a non-running process, report stale PID and overwrite it after successful start.

Stop behavior:

- Read the managed PID file.
- Verify the process exists.
- Verify the executable path or command line matches the selected install directory and config path.
- Stop only that PID.
- Remove the PID file after successful stop or when it is stale.

### macOS

macOS `start` should become a real background launch:

```text
nohup "$exe" -config "$config" >"$stdout_log" 2>"$stderr_log" &
echo $! > "$pid_file"
```

The `.command` and generated start scripts stay available as foreground troubleshooting launchers, not the default lifecycle path.

Stop behavior:

- Read the managed PID file.
- Use `ps -p "$pid" -o args=` to verify the command includes the selected executable and config path.
- Send `TERM` only to the verified managed PID.
- Wait briefly for exit.
- If it remains running, print guidance instead of force-killing by default.
- Remove stale PID files.

## Error Handling

- `start` requires executable and config files. Missing prerequisites should name the missing file and the next action to run.
- `stop` with no PID should report that no managed process is running.
- `status` should tolerate missing files and show clear state.
- Unsafe config, such as a non-loopback host or `allow-remote: true`, remains a hard stop for start, health, WebUI, login, and model queries.
- PID mismatch should never be resolved with broad process-name matching.

## Testing

Add focused tests before implementation:

- Windows status with saved state should not prompt for install directory.
- macOS status with saved state should not prompt for install directory.
- Windows `webui-info` should print the WebUI URL and management key from a temporary config.
- macOS `webui-info` should print the WebUI URL and management key from a temporary config.
- Windows static lifecycle test should assert the presence of `stop`, PID validation, and no broad process-name kill.
- macOS static lifecycle test should assert `start` uses `nohup`, writes PID/logs, and does not use `open "$start_command"` as default start.
- README/docs test should assert the documented menu sections, automatic install-directory reuse, WebUI information action, start/status/stop lifecycle, and managed PID/log files.

Keep existing tests for health checks, background start, localized help, default directories, and README workflow text.

## Documentation Updates

README and `docs/design.md` should describe:

- The new sectioned menu.
- Automatic install-directory reuse.
- How to change the install directory explicitly.
- `WebUI 信息` and its secret-display behavior.
- Managed start/status/stop behavior.
- macOS background start via PID/log files.
- Safety rule: the manager only stops the process represented by its own validated PID file.

## Acceptance Criteria

- Reopening the manager after setup no longer asks for the install directory.
- Menu is grouped into installation, service runtime, WebUI, login, diagnostics/integration, and settings sections.
- `status` shows service state and whether the WebUI key exists, but not the full key.
- `webui-info` shows the full WebUI management key.
- `start` is idempotent when the managed process is already running.
- `stop` terminates only the validated managed process.
- macOS uses background start with PID/log files.
- All existing and new tests pass.
