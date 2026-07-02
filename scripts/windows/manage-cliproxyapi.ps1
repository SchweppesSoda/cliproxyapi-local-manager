param(
  [ValidateSet("menu", "status", "install", "config", "start", "health", "webui", "oauth", "device-login", "models", "workbuddy")]
  [string] $Action = "menu",
  [switch] $Help
)

$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
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
$DefaultInstallBase = $env:LOCALAPPDATA
if ([string]::IsNullOrWhiteSpace($DefaultInstallBase)) {
  $DefaultInstallBase = Join-Path $env:USERPROFILE "AppData\Local"
}
$DefaultInstallDir = Join-Path $DefaultInstallBase "Programs\CLIProxyAPI"

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
CLIProxyAPI 本地管理器（Windows）

Usage:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\manage-cliproxyapi.ps1
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\manage-cliproxyapi.ps1 -Action status

Actions:
  menu          打开交互菜单
  status        显示本地状态
  install       安装或更新 CLIProxyAPI
  config        生成仅本机访问的 config.yaml
  start         后台启动 CLIProxyAPI（隐藏窗口，写入 logs）
  health        API 可用性检查（GET /v1/models）
  webui         打开管理中心
  oauth         运行 Codex 浏览器 OAuth 登录
  device-login  运行 Codex 设备码登录
  models        查询 /v1/models
  workbuddy     输出 WorkBuddy 配置摘要
"@
}

function Read-State {
  if (-not (Test-Path -LiteralPath $StatePath)) {
    return $null
  }
  try {
    return Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    Write-Warn "状态文件不是有效 JSON，将忽略: $StatePath"
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
    Write-Host "上次安装目录:"
    Write-Host "  $($state.installDir)"
    Write-Host "默认安装目录:"
    Write-Host "  $DefaultInstallDir"
    $inputPath = Read-Host "安装目录（回车使用上次目录，输入 default 使用默认目录，或输入自定义路径）"
    if ([string]::IsNullOrWhiteSpace($inputPath)) {
      return (Expand-InstallPath $state.installDir)
    }
    if ($inputPath.Trim().ToLowerInvariant() -eq "default") {
      return (Expand-InstallPath $DefaultInstallDir)
    }
    return (Expand-InstallPath $inputPath)
  }

  Write-Host ""
  Write-Host "默认安装目录:"
  Write-Host "  $DefaultInstallDir"
  $inputPath = Read-Host "安装目录（回车使用默认目录）"
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
    Logs = Join-Path $InstallDir "logs"
    StdoutLog = Join-Path (Join-Path $InstallDir "logs") "cli-proxy-api.stdout.log"
    StderrLog = Join-Path (Join-Path $InstallDir "logs") "cli-proxy-api.stderr.log"
    PidFile = Join-Path $InstallDir "cli-proxy-api.pid"
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
  New-Item -ItemType Directory -Force -Path $paths.Logs | Out-Null
}

function Get-ArchitectureRegex {
  $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
  if ($arch -match "Arm64") {
    return "arm64|aarch64"
  }
  return "amd64|x86_64|x64"
}

function Get-LatestRelease {
  Write-Info "正在从 $Repo 获取最新发布信息"
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
    throw "没有找到匹配当前架构 ($archRegex) 的 Windows 发布资产。可用资产:$([Environment]::NewLine)$available$([Environment]::NewLine)请检查 $($Release.html_url)"
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
  Write-Ok "前台排障启动脚本已写入:"
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

  Write-Info "最新版本: $($release.tag_name)"
  Write-Info "正在下载: $($asset.browser_download_url)"
  Invoke-WebRequest -UseBasicParsing -Uri $asset.browser_download_url -OutFile $downloadPath -Headers @{ "User-Agent" = "cliproxyapi-manager" }

  New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
  if ($asset.name -match "(?i)\.zip$") {
    Expand-Archive -LiteralPath $downloadPath -DestinationPath $extractDir -Force
    $newExe = Find-ExtractedExe $extractDir
  } elseif ($asset.name -match "(?i)\.exe$") {
    $newExe = Get-Item -LiteralPath $downloadPath
  } else {
    throw "不支持的 Windows 发布资产类型: $($asset.name)"
  }

  if (-not $newExe) {
    throw "下载的发布资产中没有找到 cli-proxy-api.exe"
  }

  if (Test-Path -LiteralPath $paths.Exe) {
    $backupPath = Join-Path $paths.Backups "cli-proxy-api-$timestamp.exe"
    Copy-Item -LiteralPath $paths.Exe -Destination $backupPath -Force
    Write-Info "已有 exe 已备份到 $backupPath"
  }

  Copy-Item -LiteralPath $newExe.FullName -Destination $paths.Exe -Force
  Write-Ok "已安装 $($paths.Exe)"

  Write-StartScripts $InstallDir
  Save-State -InstallDir $InstallDir -ReleaseTag $release.tag_name

  Write-Info "正在检查可执行文件帮助输出"
  $helpOutput = & $paths.Exe -h 2>&1
  $helpExitCode = $LASTEXITCODE
  $helpOutput | Select-Object -First 20
  if ($helpExitCode -ne 0) {
    throw "已安装的可执行文件帮助检查失败，退出码 $helpExitCode"
  }
}

function Generate-Config {
  param([string] $InstallDir)

  Ensure-InstallLayout $InstallDir
  $paths = Get-Paths $InstallDir
  $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

  if (Test-Path -LiteralPath $paths.Config) {
    if (-not (Confirm-Yes "config.yaml 已存在，是否先备份再覆盖？" $false)) {
      Write-Warn "保留现有 config.yaml"
      Write-StartScripts $InstallDir
      return
    }
    $backupConfig = Join-Path $paths.Backups "config-$timestamp.yaml"
    Copy-Item -LiteralPath $paths.Config -Destination $backupConfig -Force
    Write-Info "现有配置已备份到 $backupConfig"
  }

  $portText = Read-Host "本地端口（回车使用 8317）"
  if ([string]::IsNullOrWhiteSpace($portText)) {
    $portText = "8317"
  }
  if ($portText -notmatch "^\d+$") {
    throw "端口必须是数字"
  }
  $portNumber = [int]$portText
  if ($portNumber -lt 1 -or $portNumber -gt 65535) {
    throw "端口必须在 1 到 65535 之间"
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
  Write-Ok "配置已写入: $($paths.Config)"
  Write-Host ""
  Write-Host "管理密钥（用于 WebUI）:" -ForegroundColor Yellow
  Write-Host $mgmtKey
  Write-Host ""
  Write-Host "客户端 API Key（用于 WorkBuddy）:" -ForegroundColor Yellow
  Write-Host $clientKey
  Write-Host ""
  Write-Warn "请把这些密钥保存到本地密码管理器，不要提交或分享。"

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
    throw "不安全的配置 host '$($info.Host)'。此管理器只支持本机回环地址。"
  }
  if ($info.AllowRemote -eq "true") {
    throw "不安全的配置: remote-management.allow-remote 为 true。继续前请改为 false。"
  }
}

function Show-Status {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $info = Get-ConfigInfo $InstallDir
  Write-Host ""
  Write-Host "项目根目录: $ProjectRoot"
  Write-Host "状态文件:   $StatePath"
  Write-Host "安装目录:   $InstallDir"
  Write-Host "可执行文件: $($paths.Exe) [$((Test-Path -LiteralPath $paths.Exe))]"
  Write-Host "配置文件:   $($paths.Config) [$((Test-Path -LiteralPath $paths.Config))]"
  Write-Host "Host:       $($info.Host)"
  Write-Host "端口:       $($info.Port)"
  Write-Host "PID 文件:   $($paths.PidFile)"
  Write-Host "日志目录:   $($paths.Logs)"
}

function Start-CLIProxyAPI {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  Ensure-InstallLayout $InstallDir
  if (-not (Test-Path -LiteralPath $paths.Exe)) {
    throw "未找到 cli-proxy-api.exe，请先运行 install。"
  }
  if (-not (Test-Path -LiteralPath $paths.Config)) {
    throw "未找到 config.yaml，请先运行 config。"
  }
  Assert-LocalOnlyConfig $InstallDir
  Write-StartScripts $InstallDir
  Write-Info "后台启动 CLIProxyAPI（隐藏窗口）"
  $process = Start-Process -FilePath $paths.Exe `
    -WorkingDirectory $InstallDir `
    -ArgumentList @("-config", $paths.Config) `
    -WindowStyle Hidden `
    -RedirectStandardOutput $paths.StdoutLog `
    -RedirectStandardError $paths.StderrLog `
    -PassThru
  $process.Id | Set-Content -LiteralPath $paths.PidFile -Encoding ASCII
  Write-Ok "CLIProxyAPI 已后台启动，PID: $($process.Id)"
  Write-Host "PID 文件: $($paths.PidFile)"
  Write-Host "stdout 日志: $($paths.StdoutLog)"
  Write-Host "stderr 日志: $($paths.StderrLog)"
  Write-Host "前台排障脚本: $($paths.StartCmd)"
}

function Test-Health {
  param([string] $InstallDir)

  $info = Get-ConfigInfo $InstallDir
  Assert-LocalOnlyConfig $InstallDir
  $clientKey = $info.ClientKey
  if ([string]::IsNullOrWhiteSpace($clientKey)) {
    $clientKey = Read-Host "Client API Key（config.yaml api-keys）"
  }
  $url = "http://$($info.Host):$($info.Port)/v1/models"
  Write-Info "GET $url"
  try {
    $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5 -Headers @{ Authorization = "Bearer $clientKey" }
    Write-Ok "API 可用性检查通过，HTTP $($response.StatusCode)"
    if ($response.Content) {
      Write-Host $response.Content
    }
  } catch {
    Write-Warn "API 可用性检查失败: $($_.Exception.Message)"
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
    throw "未找到 cli-proxy-api.exe，请先运行 install。"
  }
  if (-not (Test-Path -LiteralPath $paths.Config)) {
    throw "未找到 config.yaml，请先运行 config。"
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
    $clientKey = Read-Host "客户端 API Key（config.yaml api-keys）"
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
    Write-Host "<从 config.yaml api-keys 读取>"
  }
  Write-Host ""
  Write-Host "WebUI:"
  Write-Host "http://localhost:$($info.Port)/management.html"
  Write-Host ""
  Write-Host "请使用 /v1/models 输出中的模型名作为 Model。"
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
    default { throw "未知 action: $SelectedAction" }
  }
}

function Show-Menu {
  param([string] $InstallDir)

  while ($true) {
    Write-Host ""
    Write-Host "CLIProxyAPI 本地管理器"
    Write-Host "安装目录: $InstallDir"
    Write-Host ""
    Write-Host "1. status - 显示本地状态"
    Write-Host "2. install - 安装或更新 CLIProxyAPI"
    Write-Host "3. config - 生成本地 config.yaml"
    Write-Host "4. start - 后台启动 CLIProxyAPI"
    Write-Host "5. health - API 可用性检查"
    Write-Host "6. webui - 打开管理中心"
    Write-Host "7. oauth - Codex 浏览器 OAuth 登录"
    Write-Host "8. device-login - Codex 设备码登录"
    Write-Host "9. models - 查询 /v1/models"
    Write-Host "10. workbuddy - 输出 WorkBuddy 设置"
    Write-Host "11. 更改安装目录"
    Write-Host "0. 退出"
    $choice = Read-Host "请选择"

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
        default { Write-Warn "未知选项: $choice" }
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
