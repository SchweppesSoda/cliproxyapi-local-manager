# WorkBuddy Model Capabilities Refresh Prompt

这份 prompt 用于需要刷新 CLIProxyAPI -> WorkBuddy/CodeBuddy `models.json` 能力资料时，交给 Codex 或其他大模型辅助检索官方资料。它不是运行时脚本的一部分，也不要求管理器自动抓网页。

## Fixed Prompt

```text
你要帮我刷新 CLIProxyAPI 给 WorkBuddy/CodeBuddy models.json 使用的模型能力资料。

目标：
- 根据我提供的 CLIProxyAPI /v1/models 输出，以及 CLIProxyAPI 当前支持的 OAuth/provider 范围，整理候选 workbuddy-model-capabilities.json。
- 重点覆盖 OpenAI、Claude/Anthropic、Gemini/Google/Antigravity、Kimi/Moonshot、xAI/Grok 等 CLIProxyAPI 可能通过 OAuth 或兼容接口暴露的模型。
- 只输出官方资料明确支持的字段。没有明确官方来源的字段不要写，不要靠模型名猜。

输入：
1. 我会粘贴 CLIProxyAPI 的 /v1/models 输出。
2. 如果已有 workbuddy-model-capabilities.json，我会粘贴当前版本。
3. 如果需要，请先查看 CLIProxyAPI 官方仓库/文档，确认当前 provider/OAuth 支持范围。
4. 请查看 CodeBuddy/WorkBuddy models.json 官方文档，确认可用字段。

Research rules:
- Use official sources first and cite them: provider API docs, model docs, official changelog, official SDK docs, or official repository docs.
- Do not trust directly any AI/browser extraction result. Treat it as a lead only; verify each capability against official sources.
- Do not use blog posts, pricing mirrors, third-party model tables, Reddit, or provider-aggregator pages as authoritative evidence.
- If an official page is ambiguous, mark the field as omitted or needsReview; do not invent values.
- If a model appears in /v1/models but no official API documentation clearly describes its capability, keep only base WorkBuddy fields and omit reasoning/token/image/tool metadata.

Fields to consider:
- supportsToolCall
- supportsImages, meaning image input/vision for a chat model, not image generation.
- supportsReasoning
- reasoning.defaultEffort
- reasoning.supportedEfforts
- maxInputTokens
- maxOutputTokens
- useCustomProtocol only if CodeBuddy/WorkBuddy documentation or our local integration explicitly requires it.

Important output rules:
- Produce a candidate maintenance file named workbuddy-model-capabilities.json.
- The maintenance file may include sources, verifiedAt, provider, match, capabilities, and notes for audit.
- Do not write sources, verifiedAt, provider, match, or notes into actual WorkBuddy models.json output.
- The actual WorkBuddy models.json should contain only fields WorkBuddy/CodeBuddy consumes, such as id/name/vendor/url/apiKey/supportsToolCall/supportsImages/supportsReasoning/reasoning/maxInputTokens/maxOutputTokens when explicitly selected.
- Image generation/editing-only models such as gpt-image-* or DALL-E must not be emitted as chat models unless WorkBuddy has a documented image-generation custom protocol for them.

Preferred candidate format:
{
  "version": 1,
  "updatedAt": "YYYY-MM-DD",
  "entries": [
    {
      "provider": "OpenAI",
      "match": {
        "type": "exact|prefix|regex",
        "value": "model-id-or-pattern"
      },
      "capabilities": {
        "supportsImages": true,
        "supportsReasoning": true,
        "reasoning": {
          "defaultEffort": "medium",
          "supportedEfforts": ["low", "medium", "high", "xhigh"]
        },
        "maxInputTokens": 0,
        "maxOutputTokens": 0
      },
      "sources": [
        "https://official-source.example/path"
      ],
      "verifiedAt": "YYYY-MM-DD",
      "notes": "Short explanation of what the official source proves. Mention omitted fields if relevant."
    }
  ]
}

Output structure:
1. Summary of provider/model coverage.
2. Candidate JSON.
3. Evidence table with model/pattern, field, official source URL, and short reason.
4. Omitted/uncertain items and why they were not written.
5. A short patch plan for how to update this repository.

Quality bar:
- Every non-base capability must have at least one official source.
- Token limits must come from official model/API docs, not from memory.
- Reasoning effort values must match official API names where available. Do not add "none" to WorkBuddy supportedEfforts unless WorkBuddy/CodeBuddy documents that value for models.json.
- Preserve the order of models from the user selection when generating actual models.json.
```

## Notes

这份 prompt 生成的是候选资料，不是最终事实。落地到仓库前还要人工检查来源、字段含义和 WorkBuddy/CodeBuddy 实际接受的 schema。

`sources` 和 `verifiedAt` 只用于维护审计。生成给 WorkBuddy 的实际 `models.json` 不应包含这些字段。
