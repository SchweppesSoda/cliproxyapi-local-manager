# CLIProxyAPI Local Manager

一个用于本机安装和维护 [router-for-me/CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI) 的跨平台脚本项目。目标是把 CLIProxyAPI 跑在本机 `127.0.0.1`，通过 Codex OAuth 连接用户自己的 ChatGPT / Codex 权益，再让 WorkBuddy 使用 OpenAI-compatible API 调用本地服务。

本项目只面向个人本机使用，不用于 VPS、云主机、公网暴露、多人共享或商业 API 转发。

## 安全边界

- 生成的配置只绑定 `127.0.0.1`。
- `remote-management.allow-remote` 固定为 `false`。
- 不创建 Windows 服务，不配置开机自启。
- 不配置 Cloudflare Tunnel、frp、ngrok 或公网域名。
- 不配置多账号轮询。
- 不把 `config.yaml`、OAuth token、auth 目录、Management Key 或 API Key 写入仓库。
- 生成配置使用安装目录内的 `auth/`，避免复用已有的全局 auth 目录。
- 生成配置使用 `routing.strategy: "fill-first"` 和 `max-retry-credentials: 1`，避免多账号轮询语义。
- 状态文件只保存安装目录、最近 release tag 和更新时间，不保存敏感信息。

## 快速开始

Windows：

```text
双击 manage-cliproxyapi.cmd
```

macOS：

```bash
chmod +x manage-cliproxyapi.sh manage-cliproxyapi.command scripts/macos/manage-cliproxyapi.sh
./manage-cliproxyapi.sh
```

也可以在 Finder 中双击 `manage-cliproxyapi.command`。macOS 脚本按系统自带 Bash 3.2 编写，避免 Bash 4+ 才支持的语法。

## 文件结构

```text
manage-cliproxyapi.cmd              Windows 一键入口
manage-cliproxyapi.sh               macOS / shell 入口
manage-cliproxyapi.command          macOS Finder 双击入口
scripts/windows/manage-cliproxyapi.ps1
scripts/windows/manage-cliproxyapi.cmd
scripts/macos/manage-cliproxyapi.sh
docs/design.md
```

运行后会在项目根目录生成平台状态文件：

```text
.cliproxyapi-manager-state.windows.json
.cliproxyapi-manager-state.macos.json
```

这些文件已被 `.gitignore` 忽略。

## 管理菜单

脚本提供交互式菜单：

- 选择或修改安装目录
- 安装或更新 CLIProxyAPI 核心程序
- 生成本机安全 `config.yaml`
- 生成服务启动脚本
- 启动 CLIProxyAPI
- API 可用性检查：使用 `config.yaml` 中的客户端 API Key 查询 `/v1/models`
- 打开本地 WebUI
- 执行 Codex 浏览器 OAuth 登录
- 执行 Codex 设备码登录
- 查询 `/v1/models`
- 输出 WorkBuddy 配置摘要

默认安装目录：

Windows：

```text
%LOCALAPPDATA%\Programs\CLIProxyAPI
```

macOS：

```text
$HOME/Library/Application Support/CLIProxyAPI
```

启动时可以输入自定义安装目录。后续运行会优先询问是否复用上一次目录。

## 推荐操作顺序

首次使用建议按下面顺序操作：

1. 选择或确认安装目录。
2. 安装或更新 CLIProxyAPI 核心程序。
3. 生成本机安全 `config.yaml` 和启动脚本。
4. 后台启动 CLIProxyAPI。
5. 选择一种 Codex 登录方式完成授权。
6. 查询 `/v1/models`，确认本机 API 能用并记录真实模型 ID。
7. 按菜单输出的摘要配置 WorkBuddy。

健康检查和模型确认都以 `/v1/models` 为准。该请求会读取当前安装目录 `config.yaml` 中的 `api-keys`，并使用 `Authorization: Bearer ...` 访问本机服务。

## 安装目录内容

安装或生成配置后，安装目录通常包含：

```text
cli-proxy-api.exe       Windows
cli-proxy-api           macOS
config.yaml
auth/
start-cliproxyapi.ps1   Windows
start-cliproxyapi.cmd   Windows
start-cliproxyapi.sh    macOS
start-cliproxyapi.command macOS
backups/
downloads/
logs/
```

更新核心程序时，旧文件会先备份到 `backups/`。

## Codex 登录方式

### Codex 浏览器 OAuth 登录

适合当前机器可以打开浏览器并完成 ChatGPT / Codex 授权的情况。脚本会调用 CLIProxyAPI 的 OAuth 登录流程，通常会打开浏览器或给出本机浏览器登录入口。

### Codex 设备码登录

适合当前终端不方便直接完成浏览器 OAuth，或希望在另一台已登录的设备上输入设备码的情况。脚本会调用设备码登录流程，并按 CLIProxyAPI 输出提示完成授权。

两种方式都会使用当前安装目录内的 `config.yaml` 和 `auth/`。也就是说，菜单里先选择的安装目录决定了登录写入的位置；脚本不会默认复用全局 auth 目录。登录完成后，先在菜单里查询 `/v1/models`，确认模型列表正常，再把 WorkBuddy 的 Base URL、API Key 和 Model 填好。

## WorkBuddy 配置

CLIProxyAPI 正常运行、完成任一 Codex 登录方式，并确认 `/v1/models` 能返回模型后，在 WorkBuddy 中配置：

```text
Provider / Vendor:
OpenAI / Custom / OpenAI Compatible

Base URL:
http://127.0.0.1:8317/v1

Chat Completions URL:
http://127.0.0.1:8317/v1/chat/completions

API Key:
config.yaml 里 api-keys 下的 wb-local-... 值

Model:
/v1/models 返回的实际模型 ID
```

不要猜模型名，以 `/v1/models` 返回为准。

## 常见问题

401：

- WebUI 连接失败时，确认填写的是 `remote-management.secret-key`。
- WorkBuddy 调用失败时，确认填写的是 `api-keys` 下的 `wb-local-...`。

404：

- WorkBuddy 如果要 Base URL，填 `http://127.0.0.1:8317/v1`。
- WorkBuddy 如果要完整 endpoint，填 `http://127.0.0.1:8317/v1/chat/completions`。

model not found：

- 重新运行菜单中的 `/v1/models` 查询，复制真实模型 ID。

OAuth 过期或 models 为空：

- 重新运行 Codex 浏览器 OAuth 登录或 Codex 设备码登录，然后再次查询 `/v1/models`。

端口占用：

- 先确认占用者是不是旧的 CLIProxyAPI 进程。
- 不要随意结束不认识的进程。
- 可以重新生成配置时改用另一个本地端口，并同步修改 WorkBuddy 配置。

## GitHub 发布建议

这个仓库可以公开发布脚本和文档，但不要提交任何本机安装目录、`config.yaml`、auth 目录、token、API Key 或 Management Key。
