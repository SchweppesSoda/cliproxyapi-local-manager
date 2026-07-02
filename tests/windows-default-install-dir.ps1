$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$StatePath = Join-Path $RepoRoot ".cliproxyapi-manager-state.windows.json"
$StateBackupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-manager-state.windows.{0}.json" -f ([Guid]::NewGuid().ToString("N")))
$HadState = Test-Path -LiteralPath $StatePath

$expectedBase = $env:LOCALAPPDATA
if ([string]::IsNullOrWhiteSpace($expectedBase)) {
  $expectedBase = Join-Path $env:USERPROFILE "AppData\Local"
}
$expected = Join-Path $expectedBase "Programs\CLIProxyAPI"

try {
  if ($HadState) {
    Move-Item -LiteralPath $StatePath -Destination $StateBackupPath -Force
  }

  $output = "`n" | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Action status 2>&1
  $text = $output -join "`n"

  if ($text -notmatch [regex]::Escape("Install dir:  $expected")) {
    Write-Error "Expected default install dir '$expected'. Actual output:`n$text"
  }
} finally {
  if (Test-Path -LiteralPath $StatePath) {
    Remove-Item -LiteralPath $StatePath -Force
  }
  if ($HadState -and (Test-Path -LiteralPath $StateBackupPath)) {
    Move-Item -LiteralPath $StateBackupPath -Destination $StatePath -Force
  }
}

Write-Output "WINDOWS_DEFAULT_INSTALL_DIR_OK"
