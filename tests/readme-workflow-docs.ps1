$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ReadmePath = Join-Path $RepoRoot "README.md"
$text = Get-Content -LiteralPath $ReadmePath -Raw -Encoding UTF8

foreach ($required in @("推荐操作顺序", "Codex 浏览器 OAuth 登录", "Codex 设备码登录", "两种方式都会使用当前安装目录", "/v1/models")) {
  if ($text -notmatch [regex]::Escape($required)) {
    throw "README is missing workflow/login documentation text: $required"
  }
}

Write-Output "README_WORKFLOW_DOCS_OK"

