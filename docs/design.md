# CLIProxyAPI Local Manager 设计

## 目标

CLIProxyAPI Local Manager 是一个面向个人本机使用的跨平台脚本项目，用于安装、更新、配置和启动 [router-for-me/CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)。它把 CLIProxyAPI 固定运行在 `127.0.0.1`，通过用户自己的 Codex 登录授权获得模型访问能力，再向 WorkBuddy 提供 OpenAI-compatible API。

项目设计重点是本机可用、低权限、可审计：

- 不暴露公网入口。
- 不创建常驻系统服务或开机自启项。
- 不把任何 token、API Key、Management Key、`webui-management-key.txt`、`config.yaml` 或 `auth/` 写入仓库。
- 所有运行时配置和登录状态都放在用户选择的安装目录内。

## 范围

- Windows：PowerShell 5.1 兼容脚本，加 `.cmd` 入口负责 UTF-8 控制台设置。
- macOS：系统 Bash 3.2 兼容脚本，加 Finder 可双击的 `.command` 入口。
- 允许用户选择安装目录，并在后续运行时复用上次选择。
- 从 GitHub release 安装或更新 CLIProxyAPI 核心程序。
- 支持用户显式开启、查看和关闭每日定时自动更新。
- 更新核心程序或配置前先备份旧文件。
- 生成只绑定本机地址的 `config.yaml`。
- 生成安装目录内的启动脚本。
- 支持后台启动、API 可用性检查、打开 WebUI、Codex 登录、查询模型列表和输出 WorkBuddy 配置摘要。

## 非目标

- 不提供 Docker、VPS、云主机或公网部署流程。
- 不配置 Cloudflare Tunnel、frp、ngrok 或公网域名。
- 不创建 Windows Service 或 LaunchDaemon；只有用户显式开启定时自动更新时，才创建当前用户计划任务或 LaunchAgent。
- 不做多账号轮询。
- 不管理多个用户共享的服务实例。
- 不默认复用 CLIProxyAPI 或 Codex 的全局 auth 目录。

## 安装目录

默认安装目录：

- Windows：`%LOCALAPPDATA%\Programs\CLIProxyAPI`
- macOS：`$HOME/Library/Application Support/CLIProxyAPI`

安装目录内保存运行所需文件：

```text
cli-proxy-api.exe / cli-proxy-api
cli-proxy-api-test.exe / cli-proxy-api-test（可选，自备测试版核心）
config.yaml
auth/
start-cliproxyapi.*
backups/
downloads/
logs/
```

`auth/` 是登录状态目录。`config.yaml` 会引用这个安装目录内的 `auth/`，避免意外使用全局授权状态。

更新核心程序时，旧可执行文件会备份到 `backups/`，文件名包含旧版本号和时间戳；无法确认旧版本号时使用 `unknown-version`。

`downloads/` 只用于更新期间的 release 元数据、压缩包、解压目录和临时文件，成功更新后会自动清空。`backups/` 中由管理器生成的核心程序备份和 `config.yaml` 备份分别只保留最近 3 个；菜单和命令行的显式清理入口可随时清理旧下载缓存和超出上限的备份。清理前会拒绝符号链接或重解析点，且只删除受管理的 `downloads/` 内容及旧备份，绝不删除 `auth/`、当前配置、密钥或日志。

管理器会自动复用安装目录：有已保存状态时直接使用上次选择的安装目录；只有首次没有安装目录状态文件，或用户在设置中显式更改目录时，才进入目录选择流程。

## 配置策略

生成的 `config.yaml` 遵循以下约束：

- 监听地址只使用 `127.0.0.1`。
- WebUI 管理入口不允许远程访问。
- 生成独立的 WebUI Management Key 和 WorkBuddy 客户端 API Key。
- `routing.strategy` 使用 `fill-first`。
- `max-retry-credentials` 使用 `1`，避免多账号轮询语义。
- `auth` 路径指向当前安装目录内的 `auth/`。

脚本状态文件保存在安装目录内，只记录安装目录、最近安装的 release tag 和更新时间，不记录密钥或登录状态。WebUI 明文管理密钥只保存在安装目录的 `webui-management-key.txt`，用于 CLIProxyAPI 将 `remote-management.secret-key` 改写成 bcrypt 哈希后仍能查看可输入的 WebUI 密码。

## 交互菜单与状态摘要

管理器使用分区菜单，而不是平铺功能列表。菜单顶部显示安装目录、核心程序、配置、服务状态和端口；功能分为安装配置、服务运行、WebUI、登录、检查集成、自动更新、存储清理和设置。

服务运行分区提供正式版的 `启动服务`、`停止服务`、`运行状态`，以及测试版的 `T1) 启动测试版`、`T2) 停止测试版`、`T3) 测试版状态`。WebUI 分区提供 `WebUI 信息` 和打开 WebUI；`WebUI 信息` 显示 WebUI URL 和完整 WebUI 管理密钥。显示逻辑优先读取 `webui-management-key.txt`；如果 `config.yaml` 里的 `remote-management.secret-key` 是 `$2a$...` bcrypt 哈希，管理器不会把哈希当作 WebUI 明文密码显示。`status 不显示完整密钥`，只显示 WebUI 管理密钥是否已配置。

## 登录流程

管理器提供两种 Codex 登录方式：

- Codex 浏览器 OAuth 登录：适合当前机器能打开浏览器并完成授权的场景。
- Codex 设备码登录：适合终端环境不方便直接打开浏览器，或需要在另一台已登录设备上输入设备码的场景。

两种登录方式都会调用当前安装目录下的 CLIProxyAPI，并传入当前安装目录内的 `config.yaml`。因此，登录写入和后续服务读取的是同一个 `auth/` 目录。

## API 可用性检查

CLIProxyAPI 的可用性检查使用已生成的客户端 API Key 请求：

```text
GET http://127.0.0.1:<port>/v1/models
Authorization: Bearer <api-key>
```

这样可以同时验证三件事：

- 本机服务已经启动并监听目标端口。
- `config.yaml` 中的客户端 API Key 能正常鉴权。
- Codex 登录状态能返回可用模型。

客户端配置中的模型 ID 必须以 `/v1/models` 返回的真实值为准。模型能力来自安装目录中经过验证的 CLIProxyAPI 官方 `models.json`，不从模型名称猜测。

## 受管进程生命周期

Windows 和 macOS 都使用受管 start/status/stop 生命周期。后台启动直接运行安装目录内的 CLIProxyAPI 可执行文件，并在安装目录写入：

```text
cli-proxy-api.pid
logs/cli-proxy-api.stdout.log
logs/cli-proxy-api.stderr.log
```

Windows 启动隐藏窗口并把 stdout、stderr 重定向到上述日志。macOS 启动保持普通用户态运行，不创建系统守护进程。

`运行状态` 读取 PID 文件并派生 `running`、`stopped` 或 `stale-pid`。启动前会检查已有 PID；停止时验证 PID 的路径或命令行匹配当前安装目录和配置。管理器只停止自己验证过的 PID。

用户可以在安装目录放入自备测试版核心：Windows 使用 `cli-proxy-api-test.exe`，macOS 使用 `cli-proxy-api-test`。测试版与正式版共用 `config.yaml`、`auth/` 和端口，但分别使用独立 PID、stdout/stderr 日志及前台排障脚本。两者采用互斥运行；启动前会检查另一版本的受管状态，另一版本正在运行时拒绝启动。停止测试版时必须同时匹配测试版可执行文件路径和当前 `config.yaml` 参数，不能误停正式版。

安装和定时自动更新只管理正式版核心，不覆盖、备份或删除自备测试版核心。存储清理只处理 `downloads/` 和 `backups/` 内的受管内容。

## 定时自动更新

定时自动更新是显式开启功能，不默认创建。开启或修改时，管理器询问每日更新 cron；回车使用 `0 4 * * *`，也就是每日 04:00。为了保证 Windows 和 macOS 都能稳定转换到系统原生定时器，当前只支持每日固定时间 cron：`M H * * *`，并兼容 `HH:mm` 输入。

Windows 使用当前用户 Task Scheduler 任务 `CLIProxyAPI Local Manager Auto Update`，运行安装目录内生成的包装脚本，再由包装脚本调用当前仓库的 Windows 管理脚本执行 `install`。macOS 使用当前用户 LaunchAgent `local.cliproxyapi.manager.autoupdate`，plist 写入 `~/Library/LaunchAgents/local.cliproxyapi.manager.autoupdate.plist`，通过 `StartCalendarInterval` 的 Hour/Minute 每日触发。管理器会把用户输入的 cron 和转换后的时间记录到安装目录 `auto-update-schedule.txt`，供状态页展示。

两个平台都复用现有安装/更新逻辑：如果 CLIProxyAPI 正在运行，会先停止服务，更新后恢复启动。自动更新 stdout/stderr 写入安装目录：

```text
logs/auto-update.stdout.log
logs/auto-update.stderr.log
```

定时更新不改变 `config.yaml` 的本机绑定策略，不启用远程管理，不写入仓库根目录，也不保存密钥、OAuth token 或 auth 内容。

## 客户端模型配置

WorkBuddy 使用 OpenAI-compatible 配置：

- Base URL：`http://127.0.0.1:<port>/v1`
- Chat Completions URL：`http://127.0.0.1:<port>/v1/chat/completions`
- API Key：`config.yaml` 中 `api-keys` 下的 `wb-local-...`
- Model：`/v1/models` 返回的实际模型 ID

推荐顺序是先完成安装和登录，再查询 `/v1/models`，最后配置 WorkBuddy。不要凭经验猜模型名。

统一入口是 `client-config`，第一阶段通过 `format=workbuddy` 生成 WorkBuddy/CodeBuddy `models.json`。Vendor 默认 `CLIProxyAPI`，允许用户自定义。旧 `workbuddy-json` 只保留一个版本作为兼容别名。

仓库随版本保存 `data/cliproxyapi-models.json`，运行时唯一快照位于 CLIProxyAPI 安装目录的 `models.json`。安装和更新在恢复原有服务状态后尝试从 CLIProxyAPI 相同官方源刷新；下载或校验失败保留旧文件并且不阻断主程序生命周期。显式指定模型 ID 时可以离线生成。

## 平台状态

安装目录内会生成平台状态文件：

```text
.cliproxyapi-manager-state.windows.json
.cliproxyapi-manager-state.macos.json
```

状态文件只服务于管理器本身的易用性，用来记住上次安装目录和更新信息。旧版本曾把状态文件放在项目根目录；新版本会读取旧文件一次并迁移到安装目录。敏感配置始终留在安装目录内。

## 依赖

Windows 使用系统自带 PowerShell 能力，包括 `Invoke-RestMethod`、`Invoke-WebRequest`、`Expand-Archive` 和 `Start-Process`。

macOS 使用系统常见命令，包括 `curl`、`unzip`、`tar`、`sed`、`awk`、`find` 和 `open`。脚本不要求 `jq`，如果本机安装了 `jq`，只用于更友好地显示 JSON。
