# Client Config 与模型目录设计

## 背景

现有 `workbuddy-json` 功能把 WorkBuddy/CodeBuddy 的客户端配置格式、CLIProxyAPI 模型发现和一份手写 GPT 能力表混在一起。普通 OpenAI-compatible `/v1/models` 只适合确认当前可用模型，CLIProxyAPI 自身维护的 `models.json` 才包含上下文、输出上限、工具和推理等级等能力数据。继续维护独立能力表会重复上游事实，并且 Windows 与 macOS 已经各复制了一套映射逻辑。

本次改造把用户入口改为通用的 `client-config`，但明确客户端配置文件没有统一的 OpenAI-compatible schema。第一阶段只提供 `workbuddy` adapter；以后新增客户端时增加 adapter，而不是继续扩充一个 WorkBuddy 专用函数。

## 目标

- 新增 `client-config --format workbuddy`，生成 WorkBuddy/CodeBuddy `models.json`。
- 保留 `workbuddy-json` 一个版本作为兼容别名，并在 stderr 输出弃用提示。
- 使用 CLIProxyAPI 官方 `models.json` 代替本项目的手写模型能力表。
- 在 CLIProxyAPI 安装目录中只保留一份运行时 `models.json`。
- CLIProxyAPI 安装或更新时同步刷新该文件；无网时仍可使用有效旧文件或随项目发布的快照。
- 只映射上游明确提供的能力；缺失或冲突字段一律省略，不从模型名猜测。
- Windows 与 macOS 保持相同行为、输出结构和生命周期语义。

## 非目标

- 不定义所谓“所有 OpenAI-compatible 客户端通用”的配置文件。
- 第一阶段不实现 WorkBuddy 以外的 adapter。
- 不自动判断 `/v1/models` 未暴露的 provider 或账号套餐。
- 不恢复独立的模型能力研究、候选表或 GPT 硬编码 fallback。
- 默认不输出会限制 WorkBuddy 下拉列表的 `availableModels`。

## 文件归属与来源

仓库保存一份未经修改的发行快照：

```text
data/cliproxyapi-models.json
```

运行时唯一权威文件位于：

```text
<CLIProxyAPI install dir>/models.json
```

下载源与 CLIProxyAPI 上游保持一致：

1. `https://raw.githubusercontent.com/router-for-me/models/refs/heads/main/models.json`
2. `https://models.router-for.me/models.json`

仓库快照随本项目版本更新，只作为首次安装或首次离线运行的播种文件。生成器永远读取安装目录文件，不在运行时合并仓库快照和安装目录快照，也不回写 Git 工作区。

## 模型目录生命周期

手动安装、手动升级和计划任务升级在 CLIProxyAPI 主程序更新成功后执行同一套目录同步逻辑：

1. 下载到安装目录内的临时文件。
2. 验证 JSON 根节点为对象、模型分组为数组、模型项为对象且 `id` 非空，并拒绝同一分组内重复 ID。
3. 验证成功后使用同文件系统原子替换更新 `models.json`。
4. 下载、解析或验证失败时删除临时文件并保留已有有效文件。
5. 首次运行且没有有效安装目录文件时，从仓库快照播种。
6. 同步失败只输出警告，不让 CLIProxyAPI 安装、升级或计划任务整体失败。

模型目录不得包含 API Key、OAuth token、管理密钥或其他本机状态。

## 组件边界

### Catalog loader

负责定位、验证并加载安装目录 `models.json`，按模型 ID 收集所有上游分组中的候选定义。它不生成 WorkBuddy 字段。

### Normalizer

把候选定义转换为客户端无关的内部记录：

```text
id
displayName
contextTokens
outputTokens
toolCall
inputModalities
reasoningSupported
reasoningLevels
modelType
```

同一 ID 出现在多个分组时，每个字段独立合并：所有非空值一致则采用；出现冲突则省略该字段并向 stderr 输出一次警告。安全分类字段只要任一可信定义明确表示非聊天模型，`workbuddy` adapter 就不得输出该模型。

### Format adapter

adapter 只负责把标准化记录转换成目标客户端 schema。第一阶段格式注册表只接受 `workbuddy`；未知格式立即失败并列出支持值。

Windows 使用 PowerShell 原生对象完成加载和序列化。macOS 沿用当前受支持的 JSON 解析路径；缺少可用解析器时给出明确错误，不静默退化成错误或臆测的能力输出。两端共享同一生产快照、字段契约和测试 fixture，不增加 Windows 端 Python 依赖。

## 模型发现与离线行为

- 未显式提供模型 ID 时，请求本机 `/v1/models`，以其结果决定当前真正可用的模型和交互选择顺序。
- 显式提供 `ModelIds` / `--model-ids` 时，不要求 CLIProxyAPI 正在运行，可以仅凭安装目录快照离线生成。
- 模型不在快照中时仍输出基础连接字段，并向 stderr 警告；不得自动套用相似名称的能力。
- 保持用户选择顺序，并去除重复模型 ID。

## WorkBuddy 字段映射

| WorkBuddy 字段 | 来源与规则 |
|---|---|
| `id` | 真实模型 ID |
| `name` | 上游 `display_name`，缺失时回退到 `id` |
| `vendor` | adapter 参数；默认 `CLIProxyAPI`，支持用户自定义并正确 JSON 转义 |
| `url` | 本机 `/v1/chat/completions` 地址 |
| `apiKey` | 当前客户端 API Key；缺失时使用现有占位符行为 |
| `supportsToolCall` | 只有 `supported_parameters` 明确包含 `tools` 时输出 `true`；无证据时省略 |
| `supportsImages` | 使用上游明确输入模态；显式 `ImageModelIds` 覆盖优先；无证据时省略 |
| `supportsReasoning` | 存在有效 `thinking` 配置时输出 `true`；无信息时省略 |
| `reasoning.supportedEfforts` | `thinking.levels` 与 WorkBuddy 已文档化 effort 值的交集 |
| `reasoning.defaultEffort` | 只有上游明确提供且 WorkBuddy 文档接受时输出，不猜默认值 |
| `maxInputTokens` | `context_length` 或 `inputTokenLimit`，继续保持显式 opt-in |
| `maxOutputTokens` | `max_completion_tokens` 或 `outputTokenLimit`，继续保持显式 opt-in |
| `useCustomProtocol` | 没有明确依据时省略 |

token-budget 型 `thinking.min/max` 只能证明模型支持推理，不能转换成 WorkBuddy effort 等级。第一阶段的 WorkBuddy allowlist 固定为当前文档明确接受的 `low`、`medium`、`high`、`xhigh`；`none`、`max`、`ultra` 等值只有在 WorkBuddy/CodeBuddy 文档明确接受后才能进入输出。

图片、视频生成等非聊天模型继续排除。优先依据明确的模型类型；对 CLIProxyAPI 运行时注册但未写入快照的已知图片端点模型，保留最小安全匹配规则。该规则只用于阻止把非聊天端点写成 `/v1/chat/completions`，不能用于推断视觉输入能力。

## 命令与菜单

Windows：

```powershell
-Action client-config `
-Format workbuddy `
-Vendor "My Local Provider" `
-ModelIds "model-a,model-b" `
-ImageModelIds "model-b" `
-IncludeTokenLimits
```

macOS：

```bash
--client-config \
--format workbuddy \
--vendor "My Local Provider" \
--model-ids "model-a,model-b" \
--image-model-ids "model-b" \
--include-token-limits
```

菜单第 13 项改为“客户端模型配置”。第一阶段格式默认为 `workbuddy`；Vendor 默认为 `CLIProxyAPI`，允许输入任意非空显示名称。旧 `workbuddy-json` 入口内部转发到新入口，其 JSON stdout 必须与等价新命令完全一致，弃用提示只写 stderr。

## 错误处理

- 未知格式、无模型 ID、无法解析必要输入属于失败并返回非零状态。
- 快照同步失败属于非致命警告，且不得破坏已有文件。
- 未知模型、能力缺失和跨分组字段冲突属于可降级警告。
- 所有警告和弃用信息写 stderr，stdout 只包含最终 JSON。
- Vendor 空值使用默认值；自定义值必须正确转义。
- 生成动作不写客户端配置文件，也不把 API Key 写入日志或仓库。

## 清理与文档迁移

实现时删除：

- `data/workbuddy-model-capabilities.candidate.json`
- `docs/workbuddy-model-capabilities-prompt.md`
- Windows/macOS 内置 GPT 能力表及相关专用测试断言

README、`docs/design.md`、`AGENTS.md`、Windows/macOS 帮助、菜单和测试统一使用“客户端模型配置”术语，同时明确 `workbuddy` 是输出格式而不是通用 OpenAI-compatible 配置规范。

## 测试设计

### 快照与生命周期

- 仓库快照可解析并满足目录验证规则。
- 首次离线安装从仓库快照播种安装目录。
- 有效下载原子替换旧快照。
- 无效 JSON、无效 schema 和网络失败保留旧快照。
- 手动升级和计划任务升级调用相同同步逻辑。

### Normalizer

- 同 ID、同字段值可以合并。
- 同 ID、冲突字段被省略并产生警告。
- 未知模型只产生基础记录。
- token、tools、reasoning levels 和未来输入模态按契约映射。
- 不从 ID 名称推断常规模型能力。

### WorkBuddy adapter

- 自定义 Vendor、生僻字符和引号正确转义。
- 缺失能力字段不输出默认假值。
- token 上限保持 opt-in。
- 图片/视频生成模型不会作为聊天模型输出。
- 用户顺序稳定，默认不输出 `availableModels`。
- 旧别名与新命令 stdout 完全一致，且只在 stderr 出现弃用提示。

### 跨平台与文档

- Windows 行为测试覆盖新入口、离线生成和快照更新。
- macOS shell/static 测试覆盖同一参数、菜单、字段和降级语义。
- README、帮助文本、菜单编号和 lifecycle tests 同步更新。
- 运行仓库 `AGENTS.md` 要求的全部 PowerShell 测试；macOS 变更同时运行 shell 语法检查和全部 shell 测试。

## 验收标准

- 用户可以通过新入口生成可复制的 WorkBuddy/CodeBuddy JSON，并自定义 Vendor。
- 在线和离线使用同一份安装目录模型目录，不再依赖手写 GPT 表。
- 更新失败不会损坏快照或阻断 CLIProxyAPI 生命周期操作。
- 未知和冲突能力不会被猜测为支持。
- Windows、macOS、README 和测试对命名、参数和行为保持一致。
