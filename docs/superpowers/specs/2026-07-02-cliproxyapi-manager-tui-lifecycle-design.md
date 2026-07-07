# CLIProxyAPI 管理器交互式命令行菜单与生命周期设计

## 背景

当前 CLIProxyAPI 本地管理器已经具备核心操作，但交互模型开始影响日常使用。用户已经安装过 CLIProxyAPI 后，再次打开脚本仍会询问安装目录，因为两个平台的入口都会先调用目录选择逻辑，再进入菜单或执行动作。菜单也是一组平铺选项，安装配置、运行控制、WebUI、登录、诊断、集成输出和设置混在同一层级。

管理器已经能从 `config.yaml` 解析 WebUI 管理密钥，但只在生成配置时显示。Windows 已经能后台启动 CLIProxyAPI 并写入 PID 文件，但状态页没有验证 PID 是否真实运行，也没有停止动作。macOS 仍通过 Terminal 前台启动脚本，不符合文档里描述的后台、日志和 PID 生命周期。

## 目标

- 正常重复使用时不再询问安装位置。
- 提供更紧凑、更清晰的终端菜单，包含稳定分区和状态摘要。
- 增加 WebUI 信息动作，显示 WebUI URL 和完整管理密钥。
- 保持 `status` 有用，但不在其中打印完整密钥。
- 在 Windows 和 macOS 上都提供受管的启动、状态和停止生命周期。
- 保留当前脚本架构：Windows 使用 PowerShell 5.1，macOS 使用 Bash 3.2 兼容 shell。
- 让非交互动作保持脚本友好，不阻塞 stdin。

## 非目标

- 不构建全屏 alternate-screen terminal UI。
- 不增加 `jq`、curses、Textual、Bubble Tea 或 Node 之类的新运行依赖。
- 不创建 Windows Service、LaunchAgent、LaunchDaemon 或开机自启。
- 不按进程名杀掉任意 `cli-proxy-api` 进程。
- 不把密钥写入管理器状态文件、日志、测试或文档示例。
- 不改变仅本机访问的安全边界。

## 选定方案

保留现有脚本架构，并围绕三个点重设计交互面：

1. 静默安装目录解析器：除非用户主动更改，否则复用已知状态。
2. 带紧凑状态头的分区菜单。
3. 使用 PID 文件、日志文件、路径和命令校验的受管进程生命周期。

这个方案足够小，可以沿用当前测试风格验证，同时解决真实工作流问题。

## 安装目录解析

入口流程改为：

```text
Load state
Resolve install directory
Run action or menu
```

解析规则：

- 如果用户显式传入安装目录，使用该目录并保存。
- 如果状态文件中已有安装目录，静默复用。
- 如果没有状态文件，但默认安装目录中已有可用安装或配置，使用默认目录。
- 如果首次运行交互菜单且没有可用目录，只询问一次安装目录。
- 如果运行非交互动作且没有可用目录，使用默认目录；若动作无法执行，输出明确的缺失文件和下一步建议。
- 首次设置后，只有菜单动作 `D` / `更改安装目录` 才打开目录选择提示。

Windows 增加 `-InstallDir <path>`。macOS 增加 `--install-dir <path>`。现有动作名保持兼容。

## 状态模型

状态从文件和运行时检查派生，不完整持久化。

状态项：

- `core`: 可执行文件存在时为 `installed`，否则为 `missing`。
- `config`: `config.yaml` 存在且通过本机安全检查时为 `configured`，否则为 `missing` 或 `unsafe`。
- `service`: `running`、`stopped` 或 `stale-pid`。
- `api`: `ready`、`unreachable`、`unauthorized` 或 `unknown`。
- `webuiKey`: 存在 `remote-management.secret-key` 时为 `configured`，否则为 `missing`。

`status` 应输出路径、可执行文件和配置是否存在、Host、端口、PID 文件、日志文件和派生服务状态。它不输出完整 WebUI 管理密钥。

## 菜单布局

交互菜单应使用固定的分区信息架构，而不是平铺列表。

目标形态：

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

设计约束：

- 核心菜单内容要能放进 80x24 终端。
- 菜单头中的超长安装路径使用中间省略。
- 详细日志、JSON 模型输出和安装下载输出放在动作结果页，不塞进菜单头。
- 颜色只能作为增强。`已安装`、`缺失`、`运行中`、`已停止` 等文字本身必须能表达状态。
- Windows 在合适位置使用 `Write-Host -ForegroundColor`。macOS 只有在 stdout 是 TTY 且 `TERM` 不是 `dumb` 时才使用 `tput`。
- 非交互动作不清屏，不打印装饰性边框。

## WebUI 信息

两个平台都增加 `webui-info` 动作：

- Windows: `-Action webui-info`
- macOS: `--webui-info`

交互菜单标签为 `WebUI 信息`。

输出包含：

```text
WebUI:
http://localhost:<port>/management.html

WebUI 管理密钥:
<remote-management.secret-key>
```

这个动作会刻意打印完整管理密钥，因为用户明确需要查看它。`status` 只打印 `WebUI 管理密钥: 已配置` 或 `未配置`。

`webui` 继续负责打开 URL。它可以附带短提示，说明如需密钥请使用 `webui-info`。

## 进程生命周期

两个平台都在安装目录中使用同一组受管文件：

```text
cli-proxy-api.pid
logs/cli-proxy-api.stdout.log
logs/cli-proxy-api.stderr.log
```

### Windows

Windows 保留当前后台启动模型：

```text
Start-Process <exe> -WorkingDirectory <installDir> -ArgumentList -config <config> -WindowStyle Hidden -RedirectStandardOutput <stdout> -RedirectStandardError <stderr> -PassThru
```

启动前：

- 检查已有 PID 文件。
- 如果 PID 指向运行中的进程，并且路径或命令匹配受管可执行文件和配置，提示 CLIProxyAPI 已在运行。
- 如果 PID 指向不存在的进程，提示 stale PID，并在成功启动后覆盖。

停止行为：

- 读取受管 PID 文件。
- 验证进程存在。
- 验证可执行文件路径或命令行匹配当前安装目录和配置路径。
- 只停止该 PID。
- 成功停止后，或发现 PID 已 stale 时，删除 PID 文件。

### macOS

macOS 的 `start` 改成真正的后台启动：

```text
nohup "$exe" -config "$config" >"$stdout_log" 2>"$stderr_log" &
echo $! > "$pid_file"
```

`.command` 和生成的启动脚本继续作为前台排障入口保留，但不再是默认生命周期路径。

停止行为：

- 读取受管 PID 文件。
- 使用 `ps -p "$pid" -o args=` 验证命令包含当前可执行文件和配置路径。
- 只对验证通过的受管 PID 发送 `TERM`。
- 短暂等待退出。
- 如果进程仍在运行，输出处理建议，默认不强制 kill。
- 删除 stale PID 文件。

## 错误处理

- `start` 需要可执行文件和配置文件。缺少前置条件时，应指出缺失文件和下一步动作。
- `stop` 找不到 PID 时，应说明当前没有受管进程在运行。
- `status` 应容忍文件缺失，并显示清晰状态。
- 不安全配置，例如非回环 Host 或 `allow-remote: true`，仍然要阻止 start、health、WebUI、login 和 models。
- PID 不匹配时，绝不能退化成按进程名广泛匹配。

## 测试

实现前补充聚焦测试：

- Windows 有已保存状态时，`status` 不应询问安装目录。
- macOS 有已保存状态时，`status` 不应询问安装目录。
- Windows `webui-info` 应从临时配置读取并打印 WebUI URL 和管理密钥。
- macOS `webui-info` 应从临时配置读取并打印 WebUI URL 和管理密钥。
- Windows 静态生命周期测试应断言存在 `stop`、PID 校验，并且没有广泛按进程名杀进程。
- macOS 静态生命周期测试应断言 `start` 使用 `nohup`、写入 PID 和日志，并且默认启动不再使用 `open "$start_command"`。
- README/docs 测试应断言文档包含菜单分区、自动复用安装目录、WebUI 信息动作、start/status/stop 生命周期，以及受管 PID 和日志文件。

保留现有健康检查、后台启动、本地化帮助、默认目录和 README 工作流文案测试。

## 文档更新

README 和 `docs/design.md` 应描述：

- 新的分区菜单。
- 安装目录自动复用。
- 如何显式更改安装目录。
- `WebUI 信息` 及其密钥显示行为。
- 受管 start/status/stop 行为。
- macOS 通过 PID 和日志文件后台启动。
- 安全规则：管理器只停止自己验证过的 PID 文件对应进程。

## 验收标准

- 完成设置后再次打开管理器，不再询问安装目录。
- 菜单按安装配置、服务运行、WebUI、登录、检查集成和设置分区。
- `status` 显示服务状态和 WebUI 管理密钥是否存在，但不显示完整密钥。
- `webui-info` 显示完整 WebUI 管理密钥。
- 受管进程已运行时，`start` 幂等。
- `stop` 只终止验证通过的受管进程。
- macOS 使用带 PID 和日志文件的后台启动。
- 所有现有测试和新增测试通过。
