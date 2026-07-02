# CLIProxyAPI Local Manager 设计

## 目标

CLIProxyAPI Local Manager 是一个面向个人本机使用的跨平台脚本项目，用于安装、更新、配置和启动 [router-for-me/CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)。它把 CLIProxyAPI 固定运行在 `127.0.0.1`，通过用户自己的 Codex 登录授权获得模型访问能力，再向 WorkBuddy 提供 OpenAI-compatible API。

项目设计重点是本机可用、低权限、可审计：

- 不暴露公网入口。
- 不创建常驻系统服务或开机自启项。
- 不把任何 token、API Key、Management Key、`config.yaml` 或 `auth/` 写入仓库。
- 所有运行时配置和登录状态都放在用户选择的安装目录内。

## 范围

- Windows：PowerShell 5.1 兼容脚本，加 `.cmd` 入口负责 UTF-8 控制台设置。
- macOS：系统 Bash 3.2 兼容脚本，加 Finder 可双击的 `.command` 入口。
- 允许用户选择安装目录，并在后续运行时复用上次选择。
- 从 GitHub release 安装或更新 CLIProxyAPI 核心程序。
- 更新核心程序或配置前先备份旧文件。
- 生成只绑定本机地址的 `config.yaml`。
- 生成安装目录内的启动脚本。
- 支持后台启动、API 可用性检查、打开 WebUI、Codex 登录、查询模型列表和输出 WorkBuddy 配置摘要。

## 非目标

- 不提供 Docker、VPS、云主机或公网部署流程。
- 不配置 Cloudflare Tunnel、frp、ngrok 或公网域名。
- 不创建 Windows Service、LaunchDaemon 或 LaunchAgent。
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
config.yaml
auth/
start-cliproxyapi.*
backups/
downloads/
logs/
```

`auth/` 是登录状态目录。`config.yaml` 会引用这个安装目录内的 `auth/`，避免意外使用全局授权状态。

## 配置策略

生成的 `config.yaml` 遵循以下约束：

- 监听地址只使用 `127.0.0.1`。
- WebUI 管理入口不允许远程访问。
- 生成独立的 Management Key 和 WorkBuddy 客户端 API Key。
- `routing.strategy` 使用 `fill-first`。
- `max-retry-credentials` 使用 `1`，避免多账号轮询语义。
- `auth` 路径指向当前安装目录内的 `auth/`。

脚本状态文件只记录安装目录、最近安装的 release tag 和更新时间，不记录密钥或登录状态。

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

WorkBuddy 的模型字段必须以 `/v1/models` 返回的真实模型 ID 为准。

## 启动模型

Windows 后台启动直接运行安装目录内的 CLIProxyAPI 可执行文件，隐藏窗口并把 stdout、stderr 重定向到 `logs/`，同时记录 PID，方便用户排查启动失败原因。

macOS 启动脚本保持普通用户态运行，不创建系统守护进程。Finder 入口只负责打开终端执行脚本并在结束时提示用户查看结果。

## WorkBuddy 集成

WorkBuddy 使用 OpenAI-compatible 配置：

- Base URL：`http://127.0.0.1:<port>/v1`
- Chat Completions URL：`http://127.0.0.1:<port>/v1/chat/completions`
- API Key：`config.yaml` 中 `api-keys` 下的 `wb-local-...`
- Model：`/v1/models` 返回的实际模型 ID

推荐顺序是先完成安装和登录，再查询 `/v1/models`，最后配置 WorkBuddy。不要凭经验猜模型名。

## 平台状态

项目根目录会生成被 `.gitignore` 忽略的状态文件：

```text
.cliproxyapi-manager-state.windows.json
.cliproxyapi-manager-state.macos.json
```

状态文件只服务于管理器本身的易用性，用来记住上次安装目录和更新信息。敏感配置始终留在安装目录内。

## 依赖

Windows 使用系统自带 PowerShell 能力，包括 `Invoke-RestMethod`、`Invoke-WebRequest`、`Expand-Archive` 和 `Start-Process`。

macOS 使用系统常见命令，包括 `curl`、`unzip`、`tar`、`sed`、`awk`、`find` 和 `open`。脚本不要求 `jq`，如果本机安装了 `jq`，只用于更友好地显示 JSON。
