# CLIProxyAPI 本地管理器体验修正设计

## 背景

Windows 安装流程中，用户完成安装、生成配置、启动和 Codex 登录后，`/v1/models` 可以正常返回模型列表，但菜单中的健康检查请求 `/health` 返回 404。脚本当前还默认新开 PowerShell 窗口运行 CLIProxyAPI，且交互菜单、帮助和说明混用英文，导致执行步骤不清楚。

## 目标

- 把健康检查改成真实可用的 API 可用性检查，不再请求不存在的 `/health`。
- Windows 默认后台启动 CLIProxyAPI，并明确输出日志路径，保留前台启动脚本用于排障。
- 将主要交互菜单、帮助、状态和说明文案中文化。
- 在 README 中说明推荐操作顺序，以及 Codex 浏览器 OAuth 登录和设备码登录的区别。
- 同步修正 macOS 脚本中的健康检查语义，避免跨平台行为漂移。

## 方案

健康检查改为请求 `http://<host>:<port>/v1/models`，并使用 `config.yaml` 中 `api-keys` 的第一个客户端 key 作为 `Authorization: Bearer ...`。这样它验证的是 WorkBuddy 实际依赖的 OpenAI-compatible API 是否可用，而不是只检查端口是否监听。

Windows 启动逻辑默认直接后台启动 `cli-proxy-api.exe -config <config.yaml>`，使用 `Start-Process -WindowStyle Hidden -RedirectStandardOutput ... -RedirectStandardError ... -PassThru`。安装目录下增加 `logs/`、stdout/stderr 日志和 pid 文件。生成的 `start-cliproxyapi.ps1/.cmd` 继续作为前台排障入口。

中文化保留现有命令参数名，例如 `-Action health`、`--models`，避免破坏自动化兼容；用户可见菜单和解释改为中文。Windows wrapper 设置 UTF-8 代码页，PowerShell 脚本设置 input/output encoding，并以 Windows PowerShell 5.1 能识别的 UTF-8 BOM 保存。

## 用户操作顺序

1. 运行管理脚本。
2. 安装或更新 CLIProxyAPI。
3. 生成本机配置。
4. 后台启动 CLIProxyAPI。
5. 执行 Codex 浏览器 OAuth 登录，浏览器不可用时用设备码登录。
6. 运行 API 可用性检查或查询 `/v1/models`。
7. 将 Base URL、API Key 和真实模型 ID 填入 WorkBuddy。

## 登录说明

Codex 浏览器 OAuth 登录调用 CLIProxyAPI 的 `-codex-login`，适合当前电脑能打开浏览器并在本机完成 ChatGPT / Codex 授权的场景。

Codex 设备码登录调用 `-codex-device-login`，适合默认浏览器无法打开、远程/无 GUI 终端，或想用手机/另一台设备完成授权的场景。

两种方式都会使用当前安装目录的 `config.yaml` 和 `auth/`。登录完成后的 WorkBuddy 配置方式相同。

## 测试

- Windows 健康检查测试：mock HTTP 服务断言请求路径为 `/v1/models` 且带客户端 API Key。
- Windows 启动静态测试：断言默认启动使用隐藏后台进程、日志重定向和 pid 文件，不再新开 PowerShell 窗口。
- Windows 中文帮助测试：断言 `-Help` 输出包含中文菜单说明。
- macOS 健康检查静态/行为测试：断言脚本不再请求 `/health`，改用 `/v1/models` 并带 Authorization。
- README 文档测试：断言包含操作顺序和两种 Codex 登录方式说明。
