$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$text = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

$startIndex = $text.IndexOf("function Start-CLIProxyAPI")
$healthIndex = $text.IndexOf("function Test-Health")
if ($startIndex -lt 0 -or $healthIndex -lt $startIndex) {
  throw "Could not locate Start-CLIProxyAPI function body"
}
$body = $text.Substring($startIndex, $healthIndex - $startIndex)

if ($body -match 'Start-Process\s+powershell\.exe') {
  throw "Start-CLIProxyAPI should not launch a new PowerShell window by default"
}
foreach ($required in @("-WindowStyle", "Hidden", "-RedirectStandardOutput", "-RedirectStandardError", "-PassThru", "PidFile")) {
  if ($body -notmatch [regex]::Escape($required)) {
    throw "Start-CLIProxyAPI is missing required background startup token: $required"
  }
}

Write-Output "WINDOWS_START_BACKGROUND_STATIC_OK"
