$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$output = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Help 2>&1
$text = $output -join "`n"

foreach ($required in @("CLIProxyAPI 本地管理器", "后台启动", "API 可用性检查", "Codex 浏览器 OAuth 登录", "Codex 设备码登录")) {
  if ($text -notmatch [regex]::Escape($required)) {
    throw "Help output is missing localized text: $required`nActual output:`n$text"
  }
}

Write-Output "WINDOWS_HELP_LOCALIZED_OK"

