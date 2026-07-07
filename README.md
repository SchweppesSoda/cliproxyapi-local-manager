# CLIProxyAPI Local Manager

本仓库提供一组跨平台脚本，用来在个人电脑本机安装、配置和维护 [router-for-me/CLIProxyAPI](https://github.com/router-for-me/CLIProxyAPI)。

典型用法是：把 CLIProxyAPI 跑在 `127.0.0.1`，通过 Codex OAuth 使用你自己的 ChatGPT / Codex 权益，再让 WorkBuddy / CodeBuddy 通过 OpenAI-compatible API 调用这个本地服务。

本项目只面向个人本机使用，不用于 VPS、云主机、公网暴露、多人共享或商业 API 转发。

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

## 安全边界

- 所有默认服务地址只绑定 `127.0.0.1`。
- `remote-management.allow-remote` 固定为 `false`。
- 不创建 Windows 服务，不配置开机自启。
- 不配置 Cloudflare Tunnel、frp、ngrok 或公网域名。
- 不配置多账号轮询。
- 不把 `config.yaml`、OAuth token、auth 目录、Management Key、`webui-management-key.txt` 或 API Key 写入仓库。
- 生成配置使用安装目录内的 `auth/`，避免复用已有的全局 auth 目录。
- 生成配置使用 `routing.strategy: "fill-first"` 和 `max-retry-credentials: 1`，避免多账号轮询语义。
- 状态文件只保存安装目录、最近 release tag 和更新时间，不保存敏感信息。

## 推荐操作顺序

首次使用建议按下面顺序操作：

1. 选择或确认安装目录。
2. 安装或更新 CLIProxyAPI 核心程序。
3. 生成本机安全 `config.yaml` 和启动脚本。
4. 后台启动 CLIProxyAPI。
5. 选择一种 Codex 登录方式完成授权。
6. 查询 `/v1/models`，确认本机 API 能用并记录真实模型 ID。
7. 按菜单输出的摘要配置 WorkBuddy / CodeBuddy。

健康检查和模型确认都以 `/v1/models` 为准。该请求会读取当前安装目录 `config.yaml` 中的 `api-keys`，并使用 `Authorization: Bearer ...` 访问本机服务。

## 管理菜单

脚本会自动复用安装目录。首次没有安装目录状态文件时，交互菜单才会询问安装目录；后续运行会直接使用上次选择的目录，也可通过 `D 更改安装目录` 显式切换。

菜单按功能分区：

```text
[安装配置]  安装/更新、生成配置
[服务运行]  启动服务、停止服务、运行状态
[WebUI]     WebUI 信息、打开 WebUI
[登录]      浏览器 OAuth、设备码登录
[检查集成]  健康检查、模型列表、WorkBuddy 信息、WorkBuddy models.json
[设置]      更改安装目录、退出
```

`WebUI 信息` 会显示 WebUI URL 和完整 WebUI 管理密钥。脚本生成配置时会把 WebUI 明文管理密钥保存在安装目录的 `webui-management-key.txt`；如果 `config.yaml` 里的 `remote-management.secret-key` 已经被 CLIProxyAPI 改写成 `$2a$...` bcrypt 哈希，脚本不会把哈希当作登录密码显示。`status 不显示完整密钥`，只显示 WebUI 管理密钥是否已配置。

## 安装目录

默认安装目录：

Windows：

```text
%LOCALAPPDATA%\Programs\CLIProxyAPI
```

macOS：

```text
$HOME/Library/Application Support/CLIProxyAPI
```

首次使用或在设置中更改时，可以输入自定义安装目录。运行后会在安装目录生成平台状态文件：

```text
.cliproxyapi-manager-state.windows.json
.cliproxyapi-manager-state.macos.json
```

旧版本曾把这些状态文件放在项目根目录；新版本会读取旧文件一次并迁移到安装目录。

安装或生成配置后，安装目录通常包含：

```text
cli-proxy-api.exe          Windows
cli-proxy-api              macOS
config.yaml
webui-management-key.txt
auth/
start-cliproxyapi.ps1      Windows
start-cliproxyapi.cmd      Windows
start-cliproxyapi.sh       macOS
start-cliproxyapi.command  macOS
backups/
downloads/
logs/
```

更新核心程序时，旧文件会先备份到 `backups/`。备份文件名包含状态文件记录的旧版本号和时间戳，例如 `cli-proxy-api-v7.2.50-20260707-084830.exe`；如果旧版本号不可用，会使用 `unknown-version`。

## 受管进程生命周期

受管 start/status/stop 对应菜单里的 `启动服务`、`运行状态`、`停止服务`。后台启动会在安装目录写入：

```text
cli-proxy-api.pid
logs/cli-proxy-api.stdout.log
logs/cli-proxy-api.stderr.log
```

`运行状态` 会读取 PID 并验证进程是否仍匹配当前安装目录。`停止服务` 只停止管理器自己验证过的 PID；不会按进程名批量结束其他 `cli-proxy-api` 进程。

## Codex 登录方式

### Codex 浏览器 OAuth 登录

适合当前机器可以打开浏览器并完成 ChatGPT / Codex 授权的情况。脚本会调用 CLIProxyAPI 的 OAuth 登录流程，通常会打开浏览器或给出本机浏览器登录入口。

### Codex 设备码登录

适合当前终端不方便直接完成浏览器 OAuth，或希望在另一台已登录的设备上输入设备码的情况。脚本会调用设备码登录流程，并按 CLIProxyAPI 输出提示完成授权。

两种方式都会使用当前安装目录内的 `config.yaml` 和 `auth/`。也就是说，菜单里先选择的安装目录决定了登录写入的位置；脚本不会默认复用全局 auth 目录。登录完成后，先在菜单里查询 `/v1/models`，确认模型列表正常，再把 WorkBuddy 的 Base URL、API Key 和 Model 填好。

## WorkBuddy / CodeBuddy 配置

CLIProxyAPI 正常运行、完成任一 Codex 登录方式，并确认 `/v1/models` 能返回模型后，在 WorkBuddy / CodeBuddy 中配置：

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

### 生成 models.json

如果要直接生成可复制到 WorkBuddy / CodeBuddy `models.json` 的 JSON，可以使用菜单中的 `13) WorkBuddy models.json`。菜单会先读取 `/v1/models` 并列出编号，选择时支持 `1,3`、`2-4`、`all` / `*`，也可以直接粘贴模型 ID。

命令行也可以直接指定模型：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\manage-cliproxyapi.ps1 `
  -Action workbuddy-json `
  -ModelIds "chat-model,image-model" `
  -ImageModelIds "image-model"
```

```bash
./scripts/macos/manage-cliproxyapi.sh \
  --workbuddy-json \
  --model-ids "chat-model,image-model" \
  --image-model-ids "image-model"
```

`ImageModelIds` / `--image-model-ids` 是命令行里的显式覆盖项，用来把对应模型输出为 `"supportsImages": true`。菜单交互不会再让你手动猜哪些模型支持图片输入。这里的 `supportsImages` 表示 WorkBuddy 的图片输入/视觉理解能力，不是单独的图片生成接口。

`maxInputTokens` / `maxOutputTokens` 默认不输出。菜单生成时会询问是否输出；命令行需要显式加 `-IncludeTokenLimits` 或 `--include-token-limits`。

生成器默认只输出 `models`，不会输出 `availableModels`。`availableModels` 会限制模型下拉列表，只在你确实想隐藏其他内置模型时才需要手动添加。

### 模型能力补齐逻辑

生成器会优先根据 `/v1/models` 返回的模型对象补充能力字段。如果 CLIProxyAPI 返回了 `"supportsReasoning"`、`"reasoning"`、`"supportsImages"` 或 `"supportsToolCall"`，生成器会复制这些信息。CLIProxyAPI 返回的 `"maxInputTokens"` 或 `"maxOutputTokens"` 只在显式选择输出 token 上限时才会写入。

当 `/v1/models` 只返回模型 ID 时，生成器会使用内置的保守 fallback 表补齐官方 API 文档明确说明的模型能力。目前只覆盖 `gpt-5.5*`、`gpt-5.4*` 和 `gpt-5.4-mini*`。

这些模型会输出：

- `"supportsReasoning": true`
- `"supportsImages": true`
- WorkBuddy 可选的 `"low"`、`"medium"`、`"high"`、`"xhigh"` 思考强度

`gpt-5.5*` 会写入官方默认 `"medium"`。`gpt-5.4*` 和 `gpt-5.4-mini*` 因官方默认是 `"none"`，而 CodeBuddy 公开 `models.json` 文档没有说明 `reasoning.supportedEfforts` 支持 `"none"`，所以生成器不写 `defaultEffort`，也不会把 `"none"` 写入 WorkBuddy 的 `supportedEfforts`。

`gpt-image-*` / `dall-e*` 这类图片生成或编辑模型不能作为 WorkBuddy 的聊天模型输出。它们需要走 OpenAI Image API 的 `/v1/images/generations` 或 `/v1/images/edits`，而 WorkBuddy 自定义模型配置面向 `/chat/completions`。生成器会标注并跳过这些模型。

## 模型能力资料维护

仓库里有两类资料：

- [docs/workbuddy-model-capabilities-prompt.md](docs/workbuddy-model-capabilities-prompt.md)：固定提示词，用来让 Codex 辅助刷新模型能力资料。
- [data/workbuddy-model-capabilities.candidate.json](data/workbuddy-model-capabilities.candidate.json)：一次人工审核前的候选资料，不是运行时事实来源。

刷新资料时，先用固定提示词让 Codex 查询 OpenAI、Claude/Anthropic、Gemini/Google/Antigravity、Kimi/Moonshot、xAI/Grok 等官方文档，再人工检查来源和字段含义。

`sources`、`verifiedAt`、`provider`、`match`、`notes` 这类审计字段只属于维护资料，不能写进实际 WorkBuddy `models.json` 输出。实际输出只应包含 WorkBuddy / CodeBuddy 消费的字段，例如 `id`、`name`、`vendor`、`url`、`apiKey`、`supportsToolCall`、`supportsImages`、`supportsReasoning`、`reasoning`、`maxInputTokens`、`maxOutputTokens`。

## 文件结构

```text
manage-cliproxyapi.cmd
manage-cliproxyapi.sh
manage-cliproxyapi.command
scripts/windows/manage-cliproxyapi.ps1
scripts/windows/manage-cliproxyapi.cmd
scripts/macos/manage-cliproxyapi.sh
docs/design.md
docs/workbuddy-model-capabilities-prompt.md
data/workbuddy-model-capabilities.candidate.json
tests/
```

## 常见问题

### 401

- WebUI 连接失败时，确认填写的是 `WebUI 信息` 显示的明文管理密钥。
- 如果 `remote-management.secret-key` 显示为 `$2a$...`，这是 bcrypt 哈希，不是可输入的 WebUI 明文密码；管理器不会把哈希当作登录密码显示。
- WorkBuddy 调用失败时，确认填写的是 `api-keys` 下的 `wb-local-...`。

### 404

- WorkBuddy 如果要 Base URL，填 `http://127.0.0.1:8317/v1`。
- WorkBuddy 如果要完整 endpoint，填 `http://127.0.0.1:8317/v1/chat/completions`。
- 不要把 `gpt-image-*` 这类图片生成模型配置到 `/v1/chat/completions`。

### model not found

重新运行菜单中的 `/v1/models` 查询，复制真实模型 ID。

### OAuth 过期或 models 为空

重新运行 Codex 浏览器 OAuth 登录或 Codex 设备码登录，然后再次查询 `/v1/models`。

### 端口占用

先确认占用者是不是旧的 CLIProxyAPI 进程。不要随意结束不认识的进程。可以重新生成配置时改用另一个本地端口，并同步修改 WorkBuddy 配置。

## GitHub 发布建议

这个仓库可以公开发布脚本和文档，但不要提交任何本机安装目录、`config.yaml`、`webui-management-key.txt`、auth 目录、token、API Key 或 Management Key。
