$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$PromptPath = Join-Path $RepoRoot "docs\workbuddy-model-capabilities-prompt.md"
$ReadmePath = Join-Path $RepoRoot "README.md"

if (-not (Test-Path -LiteralPath $PromptPath)) {
  throw "Missing WorkBuddy model capabilities refresh prompt: $PromptPath"
}

$promptText = Get-Content -LiteralPath $PromptPath -Raw -Encoding UTF8
$readmeText = Get-Content -LiteralPath $ReadmePath -Raw -Encoding UTF8

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

Write-Output "WORKBUDDY_CAPABILITIES_PROMPT_DOCS_OK"
