$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$PromptPath = Join-Path $RepoRoot "docs\workbuddy-model-capabilities-prompt.md"
$ReadmePath = Join-Path $RepoRoot "README.md"
$AgentsPath = Join-Path $RepoRoot "AGENTS.md"

if (-not (Test-Path -LiteralPath $PromptPath)) {
  throw "Missing WorkBuddy model capabilities refresh prompt: $PromptPath"
}
if (-not (Test-Path -LiteralPath $AgentsPath)) {
  throw "Missing repository agent instructions: $AgentsPath"
}

$promptText = Get-Content -LiteralPath $PromptPath -Raw -Encoding UTF8
$readmeText = Get-Content -LiteralPath $ReadmePath -Raw -Encoding UTF8
$agentsText = Get-Content -LiteralPath $AgentsPath -Raw -Encoding UTF8

foreach ($required in @(
  "official sources",
  "do not trust directly",
  "CLIProxyAPI",
  "WorkBuddy",
  "CodeBuddy",
  "workbuddy-model-capabilities.json",
  "sources",
  "verifiedAt",
  "Do not write sources",
  "actual WorkBuddy models.json",
  "supportsReasoning",
  "supportsImages",
  "supportedEfforts",
  "maxInputTokens",
  "maxOutputTokens",
  "OpenAI",
  "Claude",
  "Gemini",
  "Kimi",
  "xAI"
)) {
  if ($promptText -notmatch [regex]::Escape($required)) {
    throw "WorkBuddy capabilities prompt is missing required guidance: $required"
  }
}

if ($promptText -match '(?i)trust AI extraction directly|trust browser extraction directly') {
  throw "WorkBuddy capabilities prompt must explicitly avoid trusting AI/browser extraction directly"
}

if ($readmeText -notmatch [regex]::Escape("docs/workbuddy-model-capabilities-prompt.md")) {
  throw "README should link the WorkBuddy model capabilities refresh prompt"
}

foreach ($requiredAgentText in @(
  "docs/workbuddy-model-capabilities-prompt.md",
  "data/workbuddy-model-capabilities.candidate.json",
  "/v1/models",
  "official sources",
  "sources",
  "verifiedAt",
  "Never copy them into generated WorkBuddy / CodeBuddy",
  "gpt-image-*"
)) {
  if ($agentsText -notmatch [regex]::Escape($requiredAgentText)) {
    throw "AGENTS.md is missing WorkBuddy model capability maintenance guidance: $requiredAgentText"
  }
}

Write-Output "WORKBUDDY_CAPABILITIES_PROMPT_DOCS_OK"
