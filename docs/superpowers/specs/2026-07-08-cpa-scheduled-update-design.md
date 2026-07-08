# CPA 定时自动更新与更新输出修正设计

## Context

用户希望 CLIProxyAPI 本地管理器解决两个问题：

- Windows 更新完成后的帮助检查不应显示红色错误风格字符。当前安装流程运行 `cli-proxy-api.exe -h 2>&1` 并直接回显输出，PowerShell 可能把 native stderr 显示成红色错误记录，即使退出码为 0。
- 管理器应提供定时自动更新 CPA 的功能。默认 cron 为 `0 4 * * *`，也就是每日 `04:00`。用户开启或修改时可以输入每日固定时间 cron：`M H * * *`，也兼容 `HH:mm` 时间。

## Design

Windows 更新流程继续保留安装后帮助检查，但把 native process stdout/stderr 捕获为普通文本，最多显示前 20 行。只有帮助检查退出码非 0 时才抛出失败，避免成功场景出现红色错误记录。

定时更新使用平台原生的当前用户调度机制：

- Windows 使用 Task Scheduler 当前用户任务，名称固定为 `CLIProxyAPI Local Manager Auto Update`，运行 `powershell.exe -NoProfile -ExecutionPolicy Bypass -File <manager> -Action install -InstallDir <installDir>`。
- macOS 使用用户 LaunchAgent，label 固定为 `local.cliproxyapi.manager.autoupdate`，plist 写入 `~/Library/LaunchAgents/local.cliproxyapi.manager.autoupdate.plist`。
- 两个平台都把定时更新日志写入安装目录 `logs/auto-update.stdout.log` 和 `logs/auto-update.stderr.log`。
- 开启或修改时询问每日更新 cron，回车使用 `0 4 * * *`。为保证跨平台稳定转换，当前只支持每日固定时间 cron：`M H * * *`；复杂 cron 语法会被拒绝。
- 管理器把 cron 表达式和转换后的时间写入安装目录 `auto-update-schedule.txt`，用于状态页显示。
- 新增动作：查看定时更新、开启/修改定时更新、关闭定时更新。
- 菜单新增“自动更新”分区，保持跨平台菜单、帮助、README、设计文档和测试同步。

## Safety

自动更新只调用现有 `install` 流程，不新增公网、隧道、多用户或远程管理假设。现有 install 流程会在 CLIProxyAPI 正在运行时先停止服务，更新后恢复启动。任务配置、plist 和日志都保存在用户本机或安装目录，不把 `config.yaml`、密钥、auth、token、日志或运行态写入仓库根目录。

## Testing

新增或更新静态测试覆盖：

- Windows 帮助检查使用普通进程捕获，不直接管道回显 native stderr。
- Windows action/menu/help 包含定时更新操作，Task Scheduler 使用固定任务名、每日时间、日志路径和当前安装目录。
- macOS action/menu/help 包含定时更新操作，LaunchAgent 使用固定 label、每日时间、日志路径和当前安装目录。
- README 和 `docs/design.md` 记录定时更新行为。

最后运行 AGENTS.md 指定的 Windows PowerShell 测试和 macOS shell 测试。
