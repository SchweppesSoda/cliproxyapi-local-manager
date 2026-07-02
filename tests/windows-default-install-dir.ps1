$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$StatePath = Join-Path $RepoRoot ".cliproxyapi-manager-state.windows.json"
$StateBackupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-manager-state.windows.{0}.json" -f ([Guid]::NewGuid().ToString("N")))
$HadState = Test-Path -LiteralPath $StatePath
$OriginalLocalAppData = $env:LOCALAPPDATA
$TestLocalAppData = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-localappdata-{0}" -f ([Guid]::NewGuid().ToString("N")))

$expectedBase = $TestLocalAppData
$expected = Join-Path $expectedBase "Programs\CLIProxyAPI"

try {
  if ($HadState) {
    Move-Item -LiteralPath $StatePath -Destination $StateBackupPath -Force
  }

  New-Item -ItemType Directory -Force -Path $TestLocalAppData | Out-Null
  $env:LOCALAPPDATA = $TestLocalAppData
  $output = "`n" | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Action status 2>&1
  $text = $output -join "`n"

  if ($text -notmatch [regex]::Escape("Install dir:  $expected")) {
    Write-Error "Expected default install dir '$expected'. Actual output:`n$text"
  }
} finally {
  $env:LOCALAPPDATA = $OriginalLocalAppData
  if (Test-Path -LiteralPath $StatePath) {
    Remove-Item -LiteralPath $StatePath -Force
  }
  if ($HadState -and (Test-Path -LiteralPath $StateBackupPath)) {
    Copy-Item -LiteralPath $StateBackupPath -Destination $StatePath -Force
    Remove-Item -LiteralPath $StateBackupPath -Force
  }
  if (Test-Path -LiteralPath $TestLocalAppData) {
    Remove-Item -LiteralPath $TestLocalAppData -Recurse -Force
  }
}

Write-Output "WINDOWS_DEFAULT_INSTALL_DIR_OK"
