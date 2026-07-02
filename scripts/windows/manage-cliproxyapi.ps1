param(
  [ValidateSet("menu", "status", "install", "config", "start", "health", "webui", "oauth", "device-login", "models", "workbuddy")]
  [string] $Action = "menu",
  [switch] $Help
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$Repo = "router-for-me/CLIProxyAPI"
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRootCandidate = Resolve-Path -LiteralPath (Join-Path $ScriptDir "..\..") -ErrorAction SilentlyContinue
if ($ProjectRootCandidate) {
  $ProjectRoot = $ProjectRootCandidate.Path
} else {
  $ProjectRoot = $ScriptDir
}
$StatePath = Join-Path $ProjectRoot ".cliproxyapi-manager-state.windows.json"
$DefaultInstallDir = Join-Path $env:USERPROFILE "Apps\CLIProxyAPI"

function Write-Info {
  param([string] $Message)
  Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Ok {
  param([string] $Message)
  Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Warn {
  param([string] $Message)
  Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Confirm-Yes {
  param(
    [string] $Prompt,
    [bool] $DefaultYes = $true
  )

  $suffix = if ($DefaultYes) { "[Y/n]" } else { "[y/N]" }
  $answer = Read-Host "$Prompt $suffix"
  if ([string]::IsNullOrWhiteSpace($answer)) {
    return $DefaultYes
  }
  return $answer -match "^(y|yes)$"
}

function Show-Help {
  Write-Host @"
CLIProxyAPI Local Manager for Windows

Usage:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\manage-cliproxyapi.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\manage-cliproxyapi.ps1 -Action status

Actions:
  menu          Interactive menu
  status        Show local status
  install       Install or update CLIProxyAPI
  config        Generate local-only config.yaml
  start         Start CLIProxyAPI in a new PowerShell window
  health        Check /health
  webui         Open Management Center
  oauth         Run Codex OAuth login
  device-login  Run Codex device-code login
  models        Query /v1/models
  workbuddy     Print WorkBuddy configuration summary
"@
}

function Read-State {
  if (-not (Test-Path -LiteralPath $StatePath)) {
    return $null
  }
  try {
    return Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    Write-Warn "State file is not valid JSON and will be ignored: $StatePath"
    return $null
  }
}

function Save-State {
  param(
    [string] $InstallDir,
    [string] $ReleaseTag
  )

  $state = [ordered]@{
    installDir = $InstallDir
    lastReleaseTag = $ReleaseTag
    updatedAt = (Get-Date).ToString("o")
  }
  if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
    $existingState = Read-State
    if ($existingState -and $existingState.lastReleaseTag) {
      $state.lastReleaseTag = $existingState.lastReleaseTag
    }
  }
  $state | ConvertTo-Json | Set-Content -LiteralPath $StatePath -Encoding UTF8
}

function Expand-InstallPath {
  param([string] $Path)

  $expanded = [Environment]::ExpandEnvironmentVariables($Path.Trim())
  if ($expanded -eq "~") {
    $expanded = $env:USERPROFILE
  } elseif ($expanded.StartsWith("~\")) {
    $expanded = Join-Path $env:USERPROFILE $expanded.Substring(2)
  }
  return [System.IO.Path]::GetFullPath($expanded)
}

function Select-InstallDir {
  $state = Read-State
  $candidate = $DefaultInstallDir

  if ($state -and $state.installDir) {
    Write-Host ""
    Write-Host "Previous install dir:"
    Write-Host "  $($state.installDir)"
    Write-Host "Default install dir:"
    Write-Host "  $DefaultInstallDir"
    $inputPath = Read-Host "Install dir (Enter for previous, type 'default' for default, or enter a custom path)"
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
      return (Expand-InstallPath $state.installDir)
    }
    if ($inputPath.Trim().ToLowerInvariant() -eq "default") {
      return (Expand-InstallPath $DefaultInstallDir)
    }
    return (Expand-InstallPath $inputPath)
  }

  Write-Host ""
  Write-Host "Default install dir:"
  Write-Host "  $DefaultInstallDir"
  $inputPath = Read-Host "Install dir (press Enter for default)"
  if ([string]::IsNullOrWhiteSpace($inputPath)) {
    $inputPath = $DefaultInstallDir
  }
  return (Expand-InstallPath $inputPath)
}

function Get-Paths {
  param([string] $InstallDir)

  return [ordered]@{
    InstallDir = $InstallDir
    Exe = Join-Path $InstallDir "cli-proxy-api.exe"
    Config = Join-Path $InstallDir "config.yaml"
    Auth = Join-Path $InstallDir "auth"
    Backups = Join-Path $InstallDir "backups"
    Downloads = Join-Path $InstallDir "downloads"
    StartPs1 = Join-Path $InstallDir "start-cliproxyapi.ps1"
    StartCmd = Join-Path $InstallDir "start-cliproxyapi.cmd"
  }
}

function Ensure-InstallLayout {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  New-Item -ItemType Directory -Force -Path $paths.InstallDir | Out-Null
  New-Item -ItemType Directory -Force -Path $paths.Auth | Out-Null
  New-Item -ItemType Directory -Force -Path $paths.Backups | Out-Null
  New-Item -ItemType Directory -Force -Path $paths.Downloads | Out-Null
}

function Get-ArchitectureRegex {
  $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
  if ($arch -match "Arm64") {
    return "arm64|aarch64"
  }
  return "amd64|x86_64|x64"
}

function Get-LatestRelease {
  Write-Info "Fetching latest release metadata from $Repo"
  return Invoke-RestMethod -UseBasicParsing -Uri $ApiUrl -Headers @{ "User-Agent" = "cliproxyapi-manager" }
}

function Select-WindowsAsset {
  param($Release)

  $archRegex = Get-ArchitectureRegex
  $asset = $Release.assets |
    Where-Object {
      $_.name -match "(?i)(windows|win)" -and
      $_.name -match "(?i)($archRegex)" -and
      $_.name -match "(?i)\.(zip|exe)$"
    } |
    Select-Object -First 1

  if (-not $asset) {
    $available = ($Release.assets | ForEach-Object { "  - $($_.name)" }) -join [Environment]::NewLine
    throw "No Windows asset matched this architecture ($archRegex). Available assets:$([Environment]::NewLine)$available$([Environment]::NewLine)Check $($Release.html_url)"
  }
  return $asset
}

function Find-ExtractedExe {
  param([string] $Root)

  return Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*.exe" |
    Where-Object { $_.Name -match "(?i)cli.*proxy.*api|cliproxyapi|cli-proxy-api" } |
    Select-Object -First 1
}

function Write-StartScripts {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $escapedInstallDir = $InstallDir.Replace("'", "''")
  $startPs1 = @"
`$ErrorActionPreference = "Stop"
Set-Location -LiteralPath '$escapedInstallDir'
& '.\cli-proxy-api.exe' -config '.\config.yaml'
"@
  $startPs1 | Set-Content -LiteralPath $paths.StartPs1 -Encoding UTF8

  $startCmd = @"
@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start-cliproxyapi.ps1"
echo.
pause
"@
  $startCmd | Set-Content -LiteralPath $paths.StartCmd -Encoding ASCII
  Write-Ok "Start scripts written:"
  Write-Host "  $($paths.StartPs1)"
  Write-Host "  $($paths.StartCmd)"
}

function Install-OrUpdate {
  param([string] $InstallDir)

  Ensure-InstallLayout $InstallDir
  $paths = Get-Paths $InstallDir
  $release = Get-LatestRelease
  $asset = Select-WindowsAsset $release
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $downloadPath = Join-Path $paths.Downloads $asset.name
  $extractDir = Join-Path $paths.Downloads "extract-$timestamp"

  Write-Info "Latest release: $($release.tag_name)"
  Write-Info "Downloading: $($asset.browser_download_url)"
  Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $downloadPath -Headers @{ "User-Agent" = "cliproxyapi-manager" }

  New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
  if ($asset.name -match "(?i)\.zip$") {
    Expand-Archive -LiteralPath $downloadPath -DestinationPath $extractDir -Force
    $newExe = Find-ExtractedExe $extractDir
  } elseif ($asset.name -match "(?i)\.exe$") {
    $newExe = Get-Item -LiteralPath $downloadPath
  } else {
    throw "Unsupported Windows asset type: $($asset.name)"
  }

  if (-not $newExe) {
    throw "Downloaded asset did not contain cli-proxy-api.exe"
  }

  if (Test-Path -LiteralPath $paths.Exe) {
    $backupPath = Join-Path $paths.Backups "cli-proxy-api-$timestamp.exe"
    Copy-Item -LiteralPath $paths.Exe -Destination $backupPath -Force
    Write-Info "Existing exe backed up to $backupPath"
  }

  Copy-Item -LiteralPath $newExe.FullName -Destination $paths.Exe -Force
  Write-Ok "Installed $($paths.Exe)"

  Write-StartScripts $InstallDir
  Save-State -InstallDir $InstallDir -ReleaseTag $release.tag_name

  Write-Info "Checking executable help output"
  $helpOutput = & $paths.Exe -h 2>&1
  $helpExitCode = $LASTEXITCODE
  $helpOutput | Select-Object -First 20
  if ($helpExitCode -ne 0) {
    throw "Installed executable failed help check with exit code $helpExitCode"
  }
}

function Generate-Config {
  param([string] $InstallDir)

  Ensure-InstallLayout $InstallDir
  $paths = Get-Paths $InstallDir
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

  if (Test-Path -LiteralPath $paths.Config) {
    if (-not (Confirm-Yes "config.yaml already exists. Back it up and overwrite?" $false)) {
      Write-Warn "Keeping existing config.yaml"
      Write-StartScripts $InstallDir
      return
    }
    $backupConfig = Join-Path $paths.Backups "config-$timestamp.yaml"
    Copy-Item -LiteralPath $paths.Config -Destination $backupConfig -Force
    Write-Info "Existing config backed up to $backupConfig"
  }

  $portText = Read-Host "Local port (press Enter for 8317)"
  if ([string]::IsNullOrWhiteSpace($portText)) {
    $portText = "8317"
  }
  if ($portText -notmatch "^\d+$") {
    throw "Port must be a number"
  }
  $portNumber = [int]$portText
  if ($portNumber -lt 1 -or $portNumber -gt 65535) {
    throw "Port must be between 1 and 65535"
  }

  $mgmtKey = "mgmt-local-" + ([Guid]::NewGuid().ToString("N").Substring(0, 24))
  $clientKey = "wb-local-" + ([Guid]::NewGuid().ToString("N").Substring(0, 24))

  $config = @"
host: "127.0.0.1"
port: $portText

auth-dir: "./auth"

api-keys:
  - "$clientKey"

remote-management:
  allow-remote: false
  secret-key: "$mgmtKey"
  disable-control-panel: false

debug: false
logging-to-file: true
request-retry: 3
max-retry-credentials: 1

routing:
  strategy: "fill-first"
  session-affinity: true
"@
  $config | Set-Content -LiteralPath $paths.Config -Encoding UTF8
  Write-Ok "Config written: $($paths.Config)"
  Write-Host ""
  Write-Host "Management Key (for WebUI):" -ForegroundColor Yellow
  Write-Host $mgmtKey
  Write-Host ""
  Write-Host "Client API Key (for WorkBuddy):" -ForegroundColor Yellow
  Write-Host $clientKey
  Write-Host ""
  Write-Warn "Save these keys in a local password manager. Do not commit or share them."

  Write-StartScripts $InstallDir
  Save-State -InstallDir $InstallDir -ReleaseTag ""
}

function Get-ConfigInfo {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  if (-not (Test-Path -LiteralPath $paths.Config)) {
    return [ordered]@{
      Host = "127.0.0.1"
      Port = "8317"
      ClientKey = ""
      ManagementKey = ""
      AllowRemote = "false"
    }
  }

  $hostValue = "127.0.0.1"
  $portValue = "8317"
  $clientKey = ""
  $managementKey = ""
  $allowRemote = "false"
  $inApiKeys = $false

  foreach ($line in Get-Content -LiteralPath $paths.Config -Encoding UTF8) {
    if ($line -match '^\s*host:\s*"?([^"]+)"?') {
      $hostValue = $Matches[1].Trim()
    } elseif ($line -match '^\s*port:\s*(\d+)') {
      $portValue = $Matches[1]
    } elseif ($line -match '^\s*api-keys:\s*$') {
      $inApiKeys = $true
    } elseif ($inApiKeys -and $line -match '^\s*-\s*"?([^"]+)"?') {
      $clientKey = $Matches[1].Trim()
      $inApiKeys = $false
    } elseif ($line -match '^\s*secret-key:\s*"?([^"]+)"?') {
      $managementKey = $Matches[1].Trim()
    } elseif ($line -match '^\s*allow-remote:\s*"?([^"]+)"?') {
      $allowRemote = $Matches[1].Trim().ToLowerInvariant()
    } elseif ($line -match '^\S') {
      $inApiKeys = $false
    }
  }

  return [ordered]@{
    Host = $hostValue
    Port = $portValue
    ClientKey = $clientKey
    ManagementKey = $managementKey
    AllowRemote = $allowRemote
  }
}

function Assert-LocalOnlyConfig {
  param([string] $InstallDir)

  $info = Get-ConfigInfo $InstallDir
  $allowedHosts = @("127.0.0.1", "localhost", "::1")
  if ($allowedHosts -notcontains $info.Host) {
    throw "Unsafe config host '$($info.Host)'. This manager only supports local loopback hosts."
  }
  if ($info.AllowRemote -eq "true") {
    throw "Unsafe config: remote-management.allow-remote is true. Set it to false before continuing."
  }
}

function Show-Status {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $info = Get-ConfigInfo $InstallDir
  Write-Host ""
  Write-Host "Project root: $ProjectRoot"
  Write-Host "State file:   $StatePath"
  Write-Host "Install dir:  $InstallDir"
  Write-Host "Exe:          $($paths.Exe) [$((Test-Path -LiteralPath $paths.Exe))]"
  Write-Host "Config:       $($paths.Config) [$((Test-Path -LiteralPath $paths.Config))]"
  Write-Host "Host:         $($info.Host)"
  Write-Host "Port:         $($info.Port)"
}

function Start-CLIProxyAPI {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  if (-not (Test-Path -LiteralPath $paths.Exe)) {
    throw "Executable not found. Run install/update first."
  }
  if (-not (Test-Path -LiteralPath $paths.Config)) {
    throw "config.yaml not found. Generate config first."
  }
  Assert-LocalOnlyConfig $InstallDir
  Write-StartScripts $InstallDir
  Write-Info "Opening CLIProxyAPI in a new PowerShell window"
  Start-Process powershell.exe -WorkingDirectory $InstallDir -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $paths.StartPs1)
}

function Test-Health {
  param([string] $InstallDir)

  $info = Get-ConfigInfo $InstallDir
  Assert-LocalOnlyConfig $InstallDir
  $url = "http://$($info.Host):$($info.Port)/health"
  Write-Info "GET $url"
  try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5
    Write-Ok "Health responded with HTTP $($response.StatusCode)"
    if ($response.Content) {
      Write-Host $response.Content
    }
  } catch {
    Write-Warn "Health check failed: $($_.Exception.Message)"
  }
}

function Open-WebUI {
  param([string] $InstallDir)

  $info = Get-ConfigInfo $InstallDir
  Assert-LocalOnlyConfig $InstallDir
  $url = "http://localhost:$($info.Port)/management.html"
  Write-Info "Opening $url"
  Start-Process $url
}

function Invoke-CodexLogin {
  param(
    [string] $InstallDir,
    [bool] $DeviceCode
  )

  $paths = Get-Paths $InstallDir
  if (-not (Test-Path -LiteralPath $paths.Exe)) {
    throw "Executable not found. Run install/update first."
  }
  if (-not (Test-Path -LiteralPath $paths.Config)) {
    throw "config.yaml not found. Generate config first."
  }
  Assert-LocalOnlyConfig $InstallDir

  Push-Location $InstallDir
  try {
    if ($DeviceCode) {
      & $paths.Exe -config $paths.Config -codex-device-login
    } else {
      & $paths.Exe -config $paths.Config -codex-login
    }
  } finally {
    Pop-Location
  }
}

function Query-Models {
  param([string] $InstallDir)

  $info = Get-ConfigInfo $InstallDir
  Assert-LocalOnlyConfig $InstallDir
  $clientKey = $info.ClientKey
  if ([string]::IsNullOrWhiteSpace($clientKey)) {
    $clientKey = Read-Host "Client API Key (wb-local-...)"
  }
  $url = "http://$($info.Host):$($info.Port)/v1/models"
  Write-Info "GET $url"
  $response = Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $clientKey" }
  $response | ConvertTo-Json -Depth 20
}

function Show-WorkBuddyInfo {
  param([string] $InstallDir)

  $info = Get-ConfigInfo $InstallDir
  Assert-LocalOnlyConfig $InstallDir
  Write-Host ""
  Write-Host "WorkBuddy Base URL:"
  Write-Host "http://127.0.0.1:$($info.Port)/v1"
  Write-Host ""
  Write-Host "WorkBuddy Chat Completions URL:"
  Write-Host "http://127.0.0.1:$($info.Port)/v1/chat/completions"
  Write-Host ""
  Write-Host "WorkBuddy API Key:"
  if ($info.ClientKey) {
    Write-Host $info.ClientKey
  } else {
    Write-Host "<read from config.yaml api-keys>"
  }
  Write-Host ""
  Write-Host "WebUI:"
  Write-Host "http://localhost:$($info.Port)/management.html"
  Write-Host ""
  Write-Host "Use /v1/models output as the Model value."
}

function Invoke-Action {
  param(
    [string] $SelectedAction,
    [string] $InstallDir
  )

  switch ($SelectedAction) {
    "status" { Show-Status $InstallDir }
    "install" { Install-OrUpdate $InstallDir }
    "config" { Generate-Config $InstallDir }
    "start" { Start-CLIProxyAPI $InstallDir }
    "health" { Test-Health $InstallDir }
    "webui" { Open-WebUI $InstallDir }
    "oauth" { Invoke-CodexLogin -InstallDir $InstallDir -DeviceCode $false }
    "device-login" { Invoke-CodexLogin -InstallDir $InstallDir -DeviceCode $true }
    "models" { Query-Models $InstallDir }
    "workbuddy" { Show-WorkBuddyInfo $InstallDir }
    default { throw "Unknown action: $SelectedAction" }
  }
}

function Show-Menu {
  param([string] $InstallDir)

  while ($true) {
    Write-Host ""
    Write-Host "CLIProxyAPI Local Manager"
    Write-Host "Install dir: $InstallDir"
    Write-Host ""
    Write-Host "1. Status"
    Write-Host "2. Install or update CLIProxyAPI"
    Write-Host "3. Generate local config.yaml"
    Write-Host "4. Start CLIProxyAPI"
    Write-Host "5. Health check"
    Write-Host "6. Open WebUI"
    Write-Host "7. Codex OAuth login"
    Write-Host "8. Codex device-code login"
    Write-Host "9. Query /v1/models"
    Write-Host "10. Print WorkBuddy settings"
    Write-Host "11. Change install dir"
    Write-Host "0. Exit"
    $choice = Read-Host "Select"

    try {
      switch ($choice) {
        "1" { Show-Status $InstallDir }
        "2" { Install-OrUpdate $InstallDir }
        "3" { Generate-Config $InstallDir }
        "4" { Start-CLIProxyAPI $InstallDir }
        "5" { Test-Health $InstallDir }
        "6" { Open-WebUI $InstallDir }
        "7" { Invoke-CodexLogin -InstallDir $InstallDir -DeviceCode $false }
        "8" { Invoke-CodexLogin -InstallDir $InstallDir -DeviceCode $true }
        "9" { Query-Models $InstallDir }
        "10" { Show-WorkBuddyInfo $InstallDir }
        "11" { $InstallDir = Select-InstallDir; Save-State -InstallDir $InstallDir -ReleaseTag "" }
        "0" { return }
        default { Write-Warn "Unknown choice: $choice" }
      }
    } catch {
      Write-Warn $_.Exception.Message
    }
  }
}

if ($Help) {
  Show-Help
  exit 0
}

$installDir = Select-InstallDir
if ($Action -eq "menu") {
  Show-Menu $installDir
} else {
  Invoke-Action -SelectedAction $Action -InstallDir $installDir
}
