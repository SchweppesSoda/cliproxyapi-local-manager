$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$StatePath = Join-Path $RepoRoot ".cliproxyapi-manager-state.windows.json"
$StateBackupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-manager-state.windows.{0}.json" -f ([Guid]::NewGuid().ToString("N")))
$HadState = Test-Path -LiteralPath $StatePath
$InstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-status-install-{0}" -f ([Guid]::NewGuid().ToString("N")))
$ExplicitInstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-status-explicit-install-{0}" -f ([Guid]::NewGuid().ToString("N")))

try {
  if ($HadState) {
    Move-Item -LiteralPath $StatePath -Destination $StateBackupPath -Force
  }

  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Set-Content -LiteralPath (Join-Path $InstallDir "config.yaml") -Encoding UTF8 -Value @"
host: "127.0.0.1"
port: 8317

api-keys:
  - "wb-local-test"

remote-management:
  allow-remote: false
  secret-key: "mgmt-local-test"
"@
  Set-Content -LiteralPath (Join-Path $InstallDir "cli-proxy-api.exe") -Encoding ASCII -Value "placeholder"
  [ordered]@{
    installDir = $InstallDir
    lastReleaseTag = "test"
    updatedAt = (Get-Date).ToString("o")
  } | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding UTF8

  $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Action status 2>&1
  $text = $output -join "`n"

  if ($text -match "安装目录（|上次安装目录|请选择安装目录") {
    throw "status should not prompt for install directory when state exists. Output:`n$text"
  }
  if ($text -notmatch [regex]::Escape($InstallDir)) {
    throw "status should use saved install dir. Output:`n$text"
  }
  if ($text -match "mgmt-local-test") {
    throw "status must not print full WebUI management key. Output:`n$text"
  }

  New-Item -ItemType Directory -Force -Path $ExplicitInstallDir | Out-Null
  Set-Content -LiteralPath (Join-Path $ExplicitInstallDir "config.yaml") -Encoding UTF8 -Value @"
host: "127.0.0.1"
port: 8318

api-keys:
  - "wb-explicit-test"

remote-management:
  allow-remote: false
  secret-key: "mgmt-explicit-test"
"@
  Set-Content -LiteralPath (Join-Path $ExplicitInstallDir "cli-proxy-api.exe") -Encoding ASCII -Value "placeholder"

  $explicitOutput = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Action status -InstallDir $ExplicitInstallDir 2>&1
  $explicitExitCode = $LASTEXITCODE
  $explicitText = $explicitOutput -join "`n"

  if ($explicitExitCode -ne 0) {
    throw "status should accept explicit -InstallDir. Exit code: $explicitExitCode. Output:`n$explicitText"
  }
  if ($explicitText -notmatch [regex]::Escape($ExplicitInstallDir)) {
    throw "status should use explicit install dir. Output:`n$explicitText"
  }
  if ($explicitText -match "mgmt-explicit-test") {
    throw "status with explicit install dir must not print full WebUI management key. Output:`n$explicitText"
  }
} finally {
  if (Test-Path -LiteralPath $StatePath) {
    Remove-Item -LiteralPath $StatePath -Force
  }
  if ($HadState -and (Test-Path -LiteralPath $StateBackupPath)) {
    Move-Item -LiteralPath $StateBackupPath -Destination $StatePath -Force
  }
  if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
  }
  if (Test-Path -LiteralPath $ExplicitInstallDir) {
    Remove-Item -LiteralPath $ExplicitInstallDir -Recurse -Force
  }
}

Write-Output "WINDOWS_STATUS_NO_PROMPT_OK"
