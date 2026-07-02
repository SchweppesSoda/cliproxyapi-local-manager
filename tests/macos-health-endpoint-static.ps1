$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\macos\manage-cliproxyapi.sh"
$text = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

$startIndex = $text.IndexOf("health_check()")
$nextIndex = $text.IndexOf("open_webui()", $startIndex)
if ($startIndex -lt 0 -or $nextIndex -lt $startIndex) {
  throw "Could not locate macOS health_check function body"
}
$body = $text.Substring($startIndex, $nextIndex - $startIndex)

if ($body -match '/health') {
  throw "macOS health_check should not request /health"
}
foreach ($required in @("/v1/models", "Authorization: Bearer")) {
  if ($body -notmatch [regex]::Escape($required)) {
    throw "macOS health_check is missing required API availability token: $required"
  }
}

Write-Output "MACOS_HEALTH_ENDPOINT_STATIC_OK"
