param(
  [ValidateSet("menu", "status", "install", "config", "start", "stop", "health", "webui", "webui-info", "oauth", "device-login", "models", "workbuddy", "client-config", "workbuddy-json", "schedule-status", "schedule-enable", "schedule-disable", "cleanup")]
  [string] $Action = "menu",
  [string] $InstallDir,
  [string] $Format = "workbuddy",
  [string] $Vendor = "CLIProxyAPI",
  [string[]] $ModelIds = @(),
  [string[]] $ImageModelIds = @(),
  [switch] $IncludeTokenLimits,
  [switch] $Help
)

$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$Repo = "router-for-me/CLIProxyAPI"
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"
$ModelCatalogUrls = @(
  "https://raw.githubusercontent.com/router-for-me/models/refs/heads/main/models.json",
  "https://models.router-for.me/models.json"
)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRootCandidate = Resolve-Path -LiteralPath (Join-Path $ScriptDir "..\..") -ErrorAction SilentlyContinue
if ($ProjectRootCandidate) {
  $ProjectRoot = $ProjectRootCandidate.Path
} else {
  $ProjectRoot = $ScriptDir
}
$LegacyStatePath = Join-Path $ProjectRoot ".cliproxyapi-manager-state.windows.json"
$StatePath = $null
$DefaultInstallBase = $env:LOCALAPPDATA
if ([string]::IsNullOrWhiteSpace($DefaultInstallBase)) {
  $DefaultInstallBase = Join-Path $env:USERPROFILE "AppData\Local"
}
$DefaultInstallDir = Join-Path $DefaultInstallBase "Programs\CLIProxyAPI"
$MenuRightColumn = 46
$PanelValueColumn = 24

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

function Write-JsonWarn {
  param([string] $Message)
  [Console]::Error.WriteLine("[WARN] $Message")
}

function Set-OutputColumn {
  param([int] $Column)

  if ([Console]::IsOutputRedirected) {
    Write-Host "    " -NoNewline
    return
  }

  try {
    $target = [Math]::Max(0, $Column - 1)
    if ([Console]::CursorLeft -gt $target) {
      Write-Host ""
    }
    [Console]::CursorLeft = $target
  } catch {
    Write-Host "    " -NoNewline
  }
}

function Write-MenuDivider {
  Write-Host ("=" * 64) -ForegroundColor DarkCyan
}

function Write-PanelDivider {
  Write-Host ("-" * 64) -ForegroundColor DarkGray
}

function Write-Title {
  param([string] $Text)

  Write-Host ""
  Write-MenuDivider
  Write-Host $Text -ForegroundColor Cyan
  Write-MenuDivider
}

function Write-MenuSection {
  param([string] $Text)

  Write-PanelDivider
  Write-Host $Text -ForegroundColor Yellow
}

function Write-MenuItem {
  param(
    [string] $Key,
    [string] $Label
  )

  Write-Host "  $Key $Label"
}

function Write-MenuPair {
  param(
    [string] $LeftKey,
    [string] $LeftLabel,
    [string] $RightKey,
    [string] $RightLabel
  )

  Write-Host "  $LeftKey $LeftLabel" -NoNewline
  if (-not [string]::IsNullOrWhiteSpace($RightKey)) {
    Set-OutputColumn $MenuRightColumn
    Write-Host "$RightKey $RightLabel"
  } else {
    Write-Host ""
  }
}

function Write-PanelSection {
  param([string] $Text)

  Write-PanelDivider
  Write-Host $Text -ForegroundColor Yellow
}

function Write-PanelRow {
  param(
    [string] $Label,
    [string] $Value
  )

  Write-Host "  $Label" -NoNewline
  Set-OutputColumn $PanelValueColumn
  Write-Host ": $Value"
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

function New-BackupFileName {
  param(
    [string] $BaseName,
    [string] $Extension,
    [string] $ReleaseTag,
    [string] $Timestamp
  )

  $safeReleaseTag = $ReleaseTag
  if ([string]::IsNullOrWhiteSpace($safeReleaseTag)) {
    $safeReleaseTag = "unknown-version"
  } else {
    $safeReleaseTag = $safeReleaseTag.Trim() -replace '[\\/:*?"<>|\s]+', '-'
    $safeReleaseTag = $safeReleaseTag.Trim("-")
    if ([string]::IsNullOrWhiteSpace($safeReleaseTag)) {
      $safeReleaseTag = "unknown-version"
    }
  }

  $safeExtension = $Extension
  if (-not [string]::IsNullOrWhiteSpace($safeExtension) -and -not $safeExtension.StartsWith(".")) {
    $safeExtension = ".$safeExtension"
  }

  return "$BaseName-$safeReleaseTag-$Timestamp$safeExtension"
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
  stop          停止由本管理器启动并校验通过的 CLIProxyAPI
  health        API 可用性检查（GET /v1/models）
  webui-info    输出 WebUI 地址和 remote-management.secret-key
  webui         打开管理中心
  oauth         运行 Codex 浏览器 OAuth 登录
  device-login  运行 Codex 设备码登录
  models        查询 /v1/models
  workbuddy     输出 WorkBuddy 配置摘要
  client-config 输出客户端模型配置 JSON（当前支持 workbuddy）
  workbuddy-json 兼容别名；已弃用
  schedule-status  查看定时自动更新状态
  schedule-enable  开启或修改每日定时自动更新
  schedule-disable 关闭定时自动更新
  cleanup          清理更新下载缓存，并按类型仅保留最近 3 个备份

Options:
  -Format workbuddy                    客户端配置格式
  -Vendor "My Local Provider"          自定义客户端显示 Vendor
  -ModelIds "model-a,model-b"       只输出指定模型 ID
  -ImageModelIds "model-b"          将指定模型标记为 supportsImages=true；使用 * 表示全部
  -IncludeTokenLimits               输出 maxInputTokens/maxOutputTokens；默认不输出
"@
}

function Get-StatePath {
  param([string] $InstallDir)

  return (Join-Path $InstallDir ".cliproxyapi-manager-state.windows.json")
}

function Set-StateInstallDir {
  param([string] $InstallDir)

  $script:StatePath = Get-StatePath $InstallDir
}

function Read-StateFile {
  param([string] $Path)

  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return $null
  }
  try {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
  } catch {
    Write-Warn "状态文件不是有效 JSON，将忽略: $Path"
    return $null
  }
}

function Read-State {
  return (Read-StateFile $script:StatePath)
}

function Read-LegacyState {
  return (Read-StateFile $LegacyStatePath)
}

function Save-State {
  param(
    [string] $InstallDir,
    [string] $ReleaseTag
  )

  Set-StateInstallDir $InstallDir
  Ensure-InstallLayout $InstallDir
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
  if (Test-Path -LiteralPath $LegacyStatePath) {
    Remove-Item -LiteralPath $LegacyStatePath -Force
  }
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
  if (-not $state) {
    $state = Read-LegacyState
  }
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

function Resolve-InstallDir {
  param(
    [string] $RequestedInstallDir,
    [bool] $Interactive
  )

  if (-not [string]::IsNullOrWhiteSpace($RequestedInstallDir)) {
    $resolved = Expand-InstallPath $RequestedInstallDir
    Save-State -InstallDir $resolved -ReleaseTag ""
    return $resolved
  }

  $state = Read-LegacyState
  if ($state -and $state.installDir) {
    $resolved = Expand-InstallPath $state.installDir
    Save-State -InstallDir $resolved -ReleaseTag ""
    return $resolved
  }

  $defaultPaths = Get-Paths $DefaultInstallDir
  if ((Test-Path -LiteralPath $defaultPaths.Exe) -or (Test-Path -LiteralPath $defaultPaths.Config)) {
    $resolved = Expand-InstallPath $DefaultInstallDir
    Set-StateInstallDir $resolved
    return $resolved
  }

  if ($Interactive) {
    $resolved = Select-InstallDir
    Save-State -InstallDir $resolved -ReleaseTag ""
    return $resolved
  }

  $resolved = Expand-InstallPath $DefaultInstallDir
  Set-StateInstallDir $resolved
  return $resolved
}

function Get-Paths {
  param([string] $InstallDir)

  return [ordered]@{
    InstallDir = $InstallDir
    Exe = Join-Path $InstallDir "cli-proxy-api.exe"
    Config = Join-Path $InstallDir "config.yaml"
    Models = Join-Path $InstallDir "models.json"
    WebUIKey = Join-Path $InstallDir "webui-management-key.txt"
    Auth = Join-Path $InstallDir "auth"
    Backups = Join-Path $InstallDir "backups"
    Downloads = Join-Path $InstallDir "downloads"
    Logs = Join-Path $InstallDir "logs"
    StdoutLog = Join-Path (Join-Path $InstallDir "logs") "cli-proxy-api.stdout.log"
    StderrLog = Join-Path (Join-Path $InstallDir "logs") "cli-proxy-api.stderr.log"
    AutoUpdateStdoutLog = Join-Path (Join-Path $InstallDir "logs") "auto-update.stdout.log"
    AutoUpdateStderrLog = Join-Path (Join-Path $InstallDir "logs") "auto-update.stderr.log"
    AutoUpdatePs1 = Join-Path $InstallDir "auto-update-cliproxyapi.ps1"
    AutoUpdateScheduleFile = Join-Path $InstallDir "auto-update-schedule.txt"
    PidFile = Join-Path $InstallDir "cli-proxy-api.pid"
    StartPs1 = Join-Path $InstallDir "start-cliproxyapi.ps1"
    StartCmd = Join-Path $InstallDir "start-cliproxyapi.cmd"
  }
}

function Get-RepositoryModelCatalogPath {
  return (Join-Path $ProjectRoot "data\cliproxyapi-models.json")
}

function Test-ModelCatalogFile {
  param([string] $Path)

  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
    return $false
  }
  try {
    $catalog = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $groups = @($catalog.PSObject.Properties)
    if ($groups.Count -eq 0) { return $false }
    foreach ($group in $groups) {
      if ($group.Value -isnot [System.Array]) { return $false }
      $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
      $items = @($group.Value)
      if ($items.Count -eq 0) { continue }
      foreach ($item in $items) {
        if ($null -eq $item -or $null -eq $item.PSObject) { return $false }
        $idProperty = $item.PSObject.Properties["id"]
        if ($null -eq $idProperty -or -not ($idProperty.Value -is [string])) { return $false }
        $id = $idProperty.Value.Trim()
        if ([string]::IsNullOrWhiteSpace($id) -or -not $seen.Add($id)) { return $false }
      }
    }
    return $true
  } catch {
    return $false
  }
}

function Install-ModelCatalogFile {
  param(
    [string] $SourcePath,
    [string] $DestinationPath
  )

  $temporaryPath = "$DestinationPath.tmp-$([Guid]::NewGuid().ToString('N'))"
  try {
    Copy-Item -LiteralPath $SourcePath -Destination $temporaryPath -Force
    if (-not (Test-ModelCatalogFile $temporaryPath)) {
      throw "模型目录校验失败: $SourcePath"
    }
    Move-Item -LiteralPath $temporaryPath -Destination $DestinationPath -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      Remove-Item -LiteralPath $temporaryPath -Force
    }
  }
}

function Ensure-ModelCatalog {
  param([string] $InstallDir)

  Ensure-InstallLayout $InstallDir
  $paths = Get-Paths $InstallDir
  if (Test-ModelCatalogFile $paths.Models) {
    return $paths.Models
  }
  $repositoryCatalog = Get-RepositoryModelCatalogPath
  if (Test-ModelCatalogFile $repositoryCatalog) {
    Install-ModelCatalogFile -SourcePath $repositoryCatalog -DestinationPath $paths.Models
    return $paths.Models
  }
  throw "没有可用的 CLIProxyAPI models.json。请联网执行安装/更新后重试。"
}

function Sync-ModelCatalog {
  param([string] $InstallDir)

  Ensure-InstallLayout $InstallDir
  $paths = Get-Paths $InstallDir
  foreach ($url in $ModelCatalogUrls) {
    $temporaryPath = Join-Path $paths.Downloads ("models-" + [Guid]::NewGuid().ToString("N") + ".json")
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $temporaryPath -TimeoutSec 30 -Headers @{ "User-Agent" = "cliproxyapi-manager" }
      if (-not (Test-ModelCatalogFile $temporaryPath)) {
        throw "下载内容不是有效模型目录"
      }
      Install-ModelCatalogFile -SourcePath $temporaryPath -DestinationPath $paths.Models
      Write-Ok "模型目录已更新: $($paths.Models)"
      return $true
    } catch {
      Write-Warn "模型目录源不可用，将尝试下一个源: $url ($($_.Exception.Message))"
    } finally {
      if (Test-Path -LiteralPath $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force
      }
    }
  }
  try {
    [void](Ensure-ModelCatalog $InstallDir)
  } catch {
    Write-Warn $_.Exception.Message
  }
  return $false
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

function Get-UpdateCacheSummary {
  param([string] $DownloadDir)

  if (-not (Test-Path -LiteralPath $DownloadDir)) {
    return [pscustomobject]@{ ItemCount = 0; TotalBytes = [int64]0 }
  }

  $items = @(Get-ChildItem -LiteralPath $DownloadDir -Recurse -Force)
  $totalBytes = [int64]0
  foreach ($item in $items) {
    if (-not $item.PSIsContainer) {
      $totalBytes += [int64]$item.Length
    }
  }
  return [pscustomobject]@{ ItemCount = $items.Count; TotalBytes = $totalBytes }
}

function Format-ManagedStorageSize {
  param([int64] $Bytes)

  if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
  if ($Bytes -ge 1MB) { return ("{0:N2} MB" -f ($Bytes / 1MB)) }
  if ($Bytes -ge 1KB) { return ("{0:N2} KB" -f ($Bytes / 1KB)) }
  return "$Bytes B"
}

function Clear-UpdateCache {
  param(
    [string] $InstallDir,
    [switch] $Interactive
  )

  $paths = Get-Paths $InstallDir
  $downloadDir = [System.IO.Path]::GetFullPath($paths.Downloads)
  $expectedDownloadDir = [System.IO.Path]::GetFullPath((Join-Path $InstallDir "downloads"))
  if (-not [string]::Equals($downloadDir, $expectedDownloadDir, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "拒绝清理非安装目录 downloads 路径: $downloadDir"
  }
  if (-not (Test-Path -LiteralPath $downloadDir)) {
    Write-Info "没有可清理的更新下载缓存"
    return
  }

  $downloadItem = Get-Item -LiteralPath $downloadDir -Force
  if (-not $downloadItem.PSIsContainer) {
    throw "拒绝清理非目录更新缓存路径: $downloadDir"
  }
  if (($downloadItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "拒绝清理符号链接或重解析点目录: $downloadDir"
  }
  $children = @(Get-ChildItem -LiteralPath $downloadDir -Force)
  $reparsePointChildren = @(Get-ChildItem -LiteralPath $downloadDir -Recurse -Force |
    Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 })
  if ($reparsePointChildren.Count -gt 0) {
    throw "更新缓存中包含符号链接或重解析点，拒绝清理: $downloadDir"
  }

  $summary = Get-UpdateCacheSummary $downloadDir
  if ($summary.ItemCount -eq 0) {
    Write-Info "没有可清理的更新下载缓存"
    return
  }
  Write-Info "更新下载缓存: $($summary.ItemCount) 项，$(Format-ManagedStorageSize $summary.TotalBytes)"
  if ($Interactive -and -not (Confirm-Yes "清理上述更新下载缓存？不会删除 backups、auth、config.yaml、密钥或 logs。" $false)) {
    Write-Info "已取消清理更新下载缓存"
    return
  }

  foreach ($child in $children) {
    Remove-Item -LiteralPath $child.FullName -Recurse -Force
  }
  Write-Ok "已清理更新下载缓存: $downloadDir"
}

function Get-OldManagedBackups {
  param(
    [string] $InstallDir,
    [int] $KeepCount = 3
  )

  $paths = Get-Paths $InstallDir
  if (-not (Test-Path -LiteralPath $paths.Backups)) {
    return @()
  }
  $backupDirectory = Get-Item -LiteralPath $paths.Backups -Force
  if (-not $backupDirectory.PSIsContainer) {
    throw "拒绝清理非目录备份路径: $($paths.Backups)"
  }
  if (($backupDirectory.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "拒绝清理符号链接或重解析点目录: $($paths.Backups)"
  }

  $backupItems = @(Get-ChildItem -LiteralPath $paths.Backups -Force)
  $reparsePointBackups = @($backupItems | Where-Object { ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 })
  if ($reparsePointBackups.Count -gt 0) {
    throw "备份目录中包含符号链接或重解析点，拒绝清理: $($paths.Backups)"
  }
  $oldBackups = @()
  foreach ($pattern in @("cli-proxy-api-*", "config-*.yaml")) {
    $matchingBackups = @($backupItems |
      Where-Object { -not $_.PSIsContainer } |
      Where-Object { $_.Name -like $pattern } |
      Sort-Object LastWriteTimeUtc -Descending)
    $oldBackups += @($matchingBackups | Select-Object -Skip $KeepCount)
  }
  return $oldBackups
}

function Prune-OldManagedBackups {
  param(
    [string] $InstallDir,
    [switch] $Interactive
  )

  $oldBackups = @(Get-OldManagedBackups $InstallDir)
  if ($oldBackups.Count -eq 0) {
    Write-Info "无需清理旧备份（每类最多保留最近 3 个）"
    return
  }
  $totalBytes = [int64]0
  foreach ($backup in $oldBackups) {
    $totalBytes += [int64]$backup.Length
  }
  Write-Info "旧备份: $($oldBackups.Count) 个，$(Format-ManagedStorageSize $totalBytes)；每类保留最近 3 个"
  if ($Interactive -and -not (Confirm-Yes "清理上述旧备份？不会删除最近 3 个核心程序备份和最近 3 个配置备份。" $false)) {
    Write-Info "已取消清理旧备份"
    return
  }

  foreach ($backup in $oldBackups) {
    Remove-Item -LiteralPath $backup.FullName -Force
  }
  Write-Ok "已清理旧备份；每类保留最近 3 个"
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

function Invoke-ExecutableHelp {
  param([string] $ExePath)

  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $ExePath
  $startInfo.Arguments = "-h"
  $startInfo.UseShellExecute = $false
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  [void]$process.Start()
  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  $process.WaitForExit()

  return [ordered]@{
    ExitCode = $process.ExitCode
    Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
  }
}

function Install-OrUpdate {
  param([string] $InstallDir)

  Ensure-InstallLayout $InstallDir
  $paths = Get-Paths $InstallDir
  $initialState = Get-ServiceState $InstallDir
  $wasRunning = $initialState.IsRunning
  $state = Read-State
  $previousReleaseTag = "unknown-version"
  if ($state -and $state.lastReleaseTag) {
    $previousReleaseTag = [string]$state.lastReleaseTag
  }
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

  if ($wasRunning) {
    Write-Info "检测到 CLIProxyAPI 正在运行，升级前先停止服务"
    Stop-CLIProxyAPI $InstallDir
  }

  try {
    if (Test-Path -LiteralPath $paths.Exe) {
      $backupFileName = New-BackupFileName -BaseName "cli-proxy-api" -Extension ".exe" -ReleaseTag $previousReleaseTag -Timestamp $timestamp
      $backupPath = Join-Path $paths.Backups $backupFileName
      Copy-Item -LiteralPath $paths.Exe -Destination $backupPath -Force
      Write-Info "已有 exe 已备份到 $backupPath"
    }

    Copy-Item -LiteralPath $newExe.FullName -Destination $paths.Exe -Force
    Write-Ok "已安装 $($paths.Exe)"

    Write-StartScripts $InstallDir

    Write-Info "正在检查可执行文件帮助输出"
    $helpResult = Invoke-ExecutableHelp $paths.Exe
    if (-not [string]::IsNullOrWhiteSpace($helpResult.Output)) {
      $helpResult.Output -split "\r?\n" | Select-Object -First 20 | ForEach-Object { Write-Host $_ }
    }
    if ($helpResult.ExitCode -ne 0) {
      throw "已安装的可执行文件帮助检查失败，退出码 $($helpResult.ExitCode)"
    }

    Save-State -InstallDir $InstallDir -ReleaseTag $release.tag_name
  } catch {
    if ($wasRunning) {
      Write-Warn "升级未完成，正在尝试恢复启动原服务"
      try {
        Start-CLIProxyAPI $InstallDir
      } catch {
        Write-Warn "恢复启动失败: $($_.Exception.Message)"
      }
    }
    throw
  }

  if ($wasRunning) {
    Write-Info "升级完成，恢复启动 CLIProxyAPI"
    Start-CLIProxyAPI $InstallDir
  }
  [void](Sync-ModelCatalog $InstallDir)
  try {
    Clear-UpdateCache $InstallDir
  } catch {
    Write-Warn "更新已完成，但未能清理更新下载缓存: $($_.Exception.Message)"
  }
  try {
    Prune-OldManagedBackups $InstallDir
  } catch {
    Write-Warn "更新已完成，但未能清理旧备份: $($_.Exception.Message)"
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
  $mgmtKey | Set-Content -LiteralPath $paths.WebUIKey -Encoding UTF8
  Write-Ok "配置已写入: $($paths.Config)"
  Write-Ok "WebUI 明文管理密钥已保存: $($paths.WebUIKey)"
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

function ConvertFrom-YamlScalarText {
  param([string] $Value)

  if ($null -eq $Value) {
    return ""
  }
  $trimmed = $Value.Trim()
  if ($trimmed.Length -ge 2) {
    $first = $trimmed.Substring(0, 1)
    $last = $trimmed.Substring($trimmed.Length - 1, 1)
    if (($first -eq '"' -and $last -eq '"') -or ($first -eq "'" -and $last -eq "'")) {
      return $trimmed.Substring(1, $trimmed.Length - 2)
    }
  }
  return $trimmed
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
  $inRemoteManagement = $false

  foreach ($line in Get-Content -LiteralPath $paths.Config -Encoding UTF8) {
    if ($line -match '^\s*api-keys:\s*$') {
      $inApiKeys = $true
      $inRemoteManagement = $false
      continue
    }
    if ($line -match '^\s*remote-management:\s*$') {
      $inApiKeys = $false
      $inRemoteManagement = $true
      continue
    }
    if ($line -match '^\S') {
      $inApiKeys = $false
      $inRemoteManagement = $false
    }

    if ($line -match '^\s*host:\s*(.+?)\s*$') {
      $hostValue = ConvertFrom-YamlScalarText $Matches[1]
    } elseif ($line -match '^\s*port:\s*(\d+)') {
      $portValue = $Matches[1]
    } elseif ($inApiKeys -and $line -match '^\s*-\s*(.+?)\s*$') {
      $clientKey = ConvertFrom-YamlScalarText $Matches[1]
      $inApiKeys = $false
    } elseif ($inRemoteManagement -and $line -match '^\s*secret-key:\s*(.*?)\s*$') {
      $managementKey = ConvertFrom-YamlScalarText $Matches[1]
    } elseif ($inRemoteManagement -and $line -match '^\s*allow-remote:\s*(.+?)\s*$') {
      $allowRemote = (ConvertFrom-YamlScalarText $Matches[1]).ToLowerInvariant()
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

function Test-BcryptHash {
  param([string] $Value)

  return ($Value -match '^\$2[aby]\$\d{2}\$[./A-Za-z0-9]{53}$')
}

function Get-WebUIManagementKeyInfo {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $info = Get-ConfigInfo $InstallDir
  $savedPlainKey = ""

  if (Test-Path -LiteralPath $paths.WebUIKey) {
    $rawSavedPlainKey = Get-Content -LiteralPath $paths.WebUIKey -Raw -Encoding UTF8
    if ($null -ne $rawSavedPlainKey) {
      $savedPlainKey = $rawSavedPlainKey.Trim()
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($savedPlainKey)) {
    return [pscustomobject]@{
      PlainKey = $savedPlainKey
      Source = $paths.WebUIKey
      ConfigSecretIsBcrypt = (Test-BcryptHash $info.ManagementKey)
      ConfigSecret = $info.ManagementKey
      KeyFileExists = $true
    }
  }

  $keyFileExists = Test-Path -LiteralPath $paths.WebUIKey
  if (-not [string]::IsNullOrWhiteSpace($info.ManagementKey) -and -not (Test-BcryptHash $info.ManagementKey)) {
    return [pscustomobject]@{
      PlainKey = $info.ManagementKey
      Source = $paths.Config
      ConfigSecretIsBcrypt = $false
      ConfigSecret = $info.ManagementKey
      KeyFileExists = $keyFileExists
    }
  }

  return [pscustomobject]@{
    PlainKey = ""
    Source = ""
    ConfigSecretIsBcrypt = (Test-BcryptHash $info.ManagementKey)
    ConfigSecret = $info.ManagementKey
    KeyFileExists = $keyFileExists
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

function ConvertTo-ProcessArgument {
  param([string] $Argument)

  if ($null -eq $Argument) {
    return '""'
  }

  $escaped = $Argument -replace '(\\*)"', '$1$1\"'
  $escaped = $escaped -replace '(\\+)$', '$1$1'
  return "`"$escaped`""
}

function Split-WindowsCommandLine {
  param([string] $CommandLine)

  $arguments = [System.Collections.Generic.List[string]]::new()
  if ([string]::IsNullOrWhiteSpace($CommandLine)) {
    return $arguments.ToArray()
  }

  $current = [System.Text.StringBuilder]::new()
  $inQuotes = $false
  $hasToken = $false
  $index = 0

  while ($index -lt $CommandLine.Length) {
    $character = $CommandLine[$index]

    if ([char]::IsWhiteSpace($character) -and -not $inQuotes) {
      if ($hasToken) {
        $arguments.Add($current.ToString())
        [void]$current.Clear()
        $hasToken = $false
      }
      $index++
      continue
    }

    if ($character -eq "\") {
      $slashCount = 0
      while ($index -lt $CommandLine.Length -and $CommandLine[$index] -eq "\") {
        $slashCount++
        $index++
      }

      if ($index -lt $CommandLine.Length -and $CommandLine[$index] -eq '"') {
        for ($slashIndex = 0; $slashIndex -lt [Math]::Floor($slashCount / 2); $slashIndex++) {
          [void]$current.Append("\")
        }
        if (($slashCount % 2) -eq 0) {
          $inQuotes = -not $inQuotes
        } else {
          [void]$current.Append('"')
        }
        $hasToken = $true
        $index++
        continue
      }

      for ($slashIndex = 0; $slashIndex -lt $slashCount; $slashIndex++) {
        [void]$current.Append("\")
      }
      $hasToken = $true
      continue
    }

    if ($character -eq '"') {
      $inQuotes = -not $inQuotes
      $hasToken = $true
      $index++
      continue
    }

    [void]$current.Append($character)
    $hasToken = $true
    $index++
  }

  if ($hasToken) {
    $arguments.Add($current.ToString())
  }

  return $arguments.ToArray()
}

function Test-CommandLineConfigArgument {
  param(
    [string] $CommandLine,
    [string] $ExpectedConfig
  )

  if ([string]::IsNullOrWhiteSpace($CommandLine) -or [string]::IsNullOrWhiteSpace($ExpectedConfig)) {
    return $false
  }

  try {
    $expectedConfigPath = [System.IO.Path]::GetFullPath($ExpectedConfig)
  } catch {
    return $false
  }

  $arguments = @(Split-WindowsCommandLine $CommandLine)
  for ($index = 0; $index -lt $arguments.Count; $index++) {
    if (-not [string]::Equals($arguments[$index], "-config", [StringComparison]::OrdinalIgnoreCase)) {
      continue
    }
    if (($index + 1) -ge $arguments.Count) {
      return $false
    }

    try {
      $actualConfigPath = [System.IO.Path]::GetFullPath($arguments[$index + 1])
    } catch {
      return $false
    }

    if ([string]::Equals($actualConfigPath, $expectedConfigPath, [StringComparison]::OrdinalIgnoreCase)) {
      return $true
    }
  }

  return $false
}

function Get-ManagedProcess {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $result = [ordered]@{
    Pid = $null
    PidFile = $paths.PidFile
    Process = $null
    ExecutablePath = ""
    CommandLine = ""
    PathMatches = $false
    CommandLineMatches = $false
    IsRunning = $false
    IsManaged = $false
    Reason = "no-pid-file"
  }

  if (-not (Test-Path -LiteralPath $paths.PidFile)) {
    return [pscustomobject]$result
  }

  $pidText = (Get-Content -LiteralPath $paths.PidFile -Raw -Encoding ASCII).Trim()
  $pidNumber = 0
  if (-not [int]::TryParse($pidText, [ref] $pidNumber)) {
    $result["Reason"] = "invalid-pid-file"
    return [pscustomobject]$result
  }
  $result["Pid"] = $pidNumber

  $process = Get-Process -Id $pidNumber -ErrorAction SilentlyContinue
  if (-not $process) {
    $result["Reason"] = "process-not-running"
    return [pscustomobject]$result
  }

  $result["Process"] = $process
  $result["IsRunning"] = $true
  $cimProcess = Get-CimInstance -ClassName Win32_Process -Filter "ProcessId = $pidNumber" -ErrorAction SilentlyContinue
  if ($cimProcess) {
    $result["ExecutablePath"] = [string]$cimProcess.ExecutablePath
    $result["CommandLine"] = [string]$cimProcess.CommandLine
  }

  $expectedExe = [System.IO.Path]::GetFullPath($paths.Exe)
  $expectedConfig = [System.IO.Path]::GetFullPath($paths.Config)
  $result["PathMatches"] = [string]::Equals($result["ExecutablePath"], $expectedExe, [StringComparison]::OrdinalIgnoreCase)
  $commandLine = $result["CommandLine"]
  $result["CommandLineMatches"] = Test-CommandLineConfigArgument -CommandLine $commandLine -ExpectedConfig $expectedConfig
  $result["IsManaged"] = ($result["PathMatches"] -and $result["CommandLineMatches"])

  if ($result["IsManaged"]) {
    $result["Reason"] = "managed"
  } elseif (-not $result["PathMatches"]) {
    $result["Reason"] = "path-mismatch"
  } else {
    $result["Reason"] = "command-line-mismatch"
  }

  return [pscustomobject]$result
}

function Get-ServiceState {
  param([string] $InstallDir)

  $managedProcess = Get-ManagedProcess $InstallDir
  $status = "已停止"
  if ($managedProcess.IsManaged) {
    $status = "运行中"
  } elseif ($managedProcess.IsRunning) {
    $status = "PID 校验失败，未视为受管进程"
  } elseif ($managedProcess.Pid) {
    $status = "已停止（PID 已失效）"
  }

  return [pscustomobject]@{
    IsRunning = [bool]$managedProcess.IsManaged
    Pid = $managedProcess.Pid
    Status = $status
    Detail = $managedProcess.Reason
    ManagedProcess = $managedProcess
  }
}

function Get-ShortPath {
  param([string] $Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }
  $shortPath = $Path
  if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    $homePath = [System.IO.Path]::GetFullPath($env:USERPROFILE)
    $fullPath = [System.IO.Path]::GetFullPath($Path)
    if ($fullPath.StartsWith($homePath, [StringComparison]::OrdinalIgnoreCase)) {
      $shortPath = "~" + $fullPath.Substring($homePath.Length)
    }
  }
  if ($shortPath.Length -le 72) {
    return $shortPath
  }
  $leaf = Split-Path -Leaf $shortPath
  $parent = Split-Path -Parent $shortPath
  $parentLeaf = Split-Path -Leaf $parent
  if ([string]::IsNullOrWhiteSpace($parentLeaf)) {
    return "...\$leaf"
  }
  return "...\$parentLeaf\$leaf"
}

function Get-InstallSummary {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $info = Get-ConfigInfo $InstallDir
  $state = Get-ServiceState $InstallDir
  $exeStatus = if (Test-Path -LiteralPath $paths.Exe) { "有" } else { "无" }
  $configStatus = if (Test-Path -LiteralPath $paths.Config) { "有" } else { "无" }
  $webuiKeyInfo = Get-WebUIManagementKeyInfo $InstallDir
  $managementKeyStatus = if (-not [string]::IsNullOrWhiteSpace($webuiKeyInfo.PlainKey)) {
    "明文可用"
  } elseif ([string]::IsNullOrWhiteSpace($info.ManagementKey)) {
    "未配置"
  } elseif ($webuiKeyInfo.ConfigSecretIsBcrypt) {
    "未找到明文文件"
  } else {
    "已配置"
  }
  return "exe: $exeStatus | config: $configStatus | 服务: $($state.Status) | 端口: $($info.Port) | WebUI 密钥: $managementKeyStatus"
}

function Show-Status {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $info = Get-ConfigInfo $InstallDir
  $state = Get-ServiceState $InstallDir
  $webuiKeyInfo = Get-WebUIManagementKeyInfo $InstallDir
  $managementKeyStatus = if (-not [string]::IsNullOrWhiteSpace($webuiKeyInfo.PlainKey)) {
    "明文可用"
  } elseif ([string]::IsNullOrWhiteSpace($info.ManagementKey)) {
    "未配置"
  } elseif ($webuiKeyInfo.ConfigSecretIsBcrypt) {
    "未找到明文文件"
  } else {
    "已配置"
  }

  Write-Title "CLIProxyAPI 状态"
  Write-PanelSection "本机状态"
  Write-PanelRow "项目根目录" $ProjectRoot
  Write-PanelRow "状态文件" $StatePath
  Write-PanelRow "安装目录" $InstallDir
  Write-PanelRow "程序" ("{0} [{1}]" -f $paths.Exe, (Test-Path -LiteralPath $paths.Exe))
  Write-PanelRow "配置" ("{0} [{1}]" -f $paths.Config, (Test-Path -LiteralPath $paths.Config))
  Write-PanelRow "服务" $state.Status
  if ($state.Pid) {
    Write-PanelRow "PID" $state.Pid
  }
  Write-PanelRow "Host" $info.Host
  Write-PanelRow "端口" $info.Port
  Write-PanelRow "API" "http://127.0.0.1:$($info.Port)/v1"
  Write-PanelRow "WebUI" "http://localhost:$($info.Port)/management.html"
  Write-PanelRow "WebUI 密钥" $managementKeyStatus
  Write-PanelRow "PID 文件" $paths.PidFile
  Write-PanelRow "日志目录" $paths.Logs
  Write-PanelDivider
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
  $state = Get-ServiceState $InstallDir
  if ($state.IsRunning) {
    Write-Ok "CLIProxyAPI 已在运行，PID: $($state.Pid)"
    Write-Host "PID 文件: $($paths.PidFile)"
    Write-Host "stdout 日志: $($paths.StdoutLog)"
    Write-Host "stderr 日志: $($paths.StderrLog)"
    Write-Host "前台排障脚本: $($paths.StartCmd)"
    return
  }
  Write-Info "后台启动 CLIProxyAPI（隐藏窗口）"
  $configArgument = ConvertTo-ProcessArgument $paths.Config
  $process = Start-Process -FilePath $paths.Exe `
    -WorkingDirectory $InstallDir `
    -ArgumentList @("-config", $configArgument) `
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

function Stop-CLIProxyAPI {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $managedProcess = Get-ManagedProcess $InstallDir
  $state = Get-ServiceState $InstallDir
  if (-not $state.IsRunning) {
    if ($managedProcess.IsRunning) {
      Write-Warn "PID 文件指向的进程未通过路径和命令行校验，不会停止。"
      Write-Host "PID: $($state.Pid)"
      Write-Host "校验结果: $($state.Detail)"
      return
    }
    if (Test-Path -LiteralPath $paths.PidFile) {
      Remove-Item -LiteralPath $paths.PidFile -Force
    }
    Write-Ok "CLIProxyAPI 未运行"
    return
  }

  Stop-Process -Id $state.Pid -ErrorAction Stop
  if (Test-Path -LiteralPath $paths.PidFile) {
    Remove-Item -LiteralPath $paths.PidFile -Force
  }
  Write-Ok "CLIProxyAPI 已停止，PID: $($state.Pid)"
}

function Test-ScheduleTime {
  param([string] $Time)

  if ($Time -notmatch '^\d{2}:\d{2}$') {
    return $false
  }
  $parts = $Time.Split(":")
  $hour = [int]$parts[0]
  $minute = [int]$parts[1]
  if ($hour -lt 0 -or $hour -gt 23) {
    return $false
  }
  if ($minute -lt 0 -or $minute -gt 59) {
    return $false
  }
  return $true
}

function Read-ScheduleTimeOrDefault {
  $timeText = Read-Host "每日更新时间（HH:mm，回车使用 04:00）"
  if ([string]::IsNullOrWhiteSpace($timeText)) {
    return "04:00"
  }
  $timeText = $timeText.Trim()
  if (-not (Test-ScheduleTime $timeText)) {
    throw "时间格式必须是 HH:mm，例如 04:00 或 23:30。"
  }
  return $timeText
}

function Convert-ScheduleInputToDailyCron {
  param([string] $InputText)

  $value = $InputText
  if ([string]::IsNullOrWhiteSpace($value)) {
    $value = "0 4 * * *"
  } else {
    $value = $value.Trim()
  }

  if (Test-ScheduleTime $value) {
    $parts = $value.Split(":")
    $hour = [int]$parts[0]
    $minute = [int]$parts[1]
    return [ordered]@{
      CronExpression = ("{0} {1} * * *" -f $minute, $hour)
      Time = ("{0:D2}:{1:D2}" -f $hour, $minute)
    }
  }

  $fields = $value -split '\s+'
  if ($fields.Count -ne 5) {
    throw "请输入 HH:mm，或 5 字段 cron：0 4 * * *。"
  }
  if ($fields[2] -ne "*" -or $fields[3] -ne "*" -or $fields[4] -ne "*") {
    throw "当前只支持每日固定时间 cron：M H * * *。"
  }
  if ($fields[0] -notmatch '^\d{1,2}$' -or $fields[1] -notmatch '^\d{1,2}$') {
    throw "cron 的分钟和小时必须是数字，例如 0 4 * * *。"
  }

  $minute = [int]$fields[0]
  $hour = [int]$fields[1]
  if ($minute -lt 0 -or $minute -gt 59 -or $hour -lt 0 -or $hour -gt 23) {
    throw "cron 的分钟必须是 0-59，小时必须是 0-23。"
  }

  return [ordered]@{
    CronExpression = ("{0} {1} * * *" -f $minute, $hour)
    Time = ("{0:D2}:{1:D2}" -f $hour, $minute)
  }
}

function Read-ScheduleExpressionOrDefault {
  $scheduleText = Read-Host "每日更新 cron（5 字段，回车使用 0 4 * * *；也可输入 HH:mm）"
  return Convert-ScheduleInputToDailyCron $scheduleText
}

function Get-ScheduledUpdateTaskName {
  return "CLIProxyAPI Local Manager Auto Update"
}

function Get-ScheduledUpdateLogPaths {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  return [ordered]@{
    Stdout = Join-Path $paths.Logs "auto-update.stdout.log"
    Stderr = Join-Path $paths.Logs "auto-update.stderr.log"
    Schedule = Join-Path $paths.InstallDir "auto-update-schedule.txt"
  }
}

function ConvertTo-PowerShellSingleQuotedArgument {
  param([string] $Value)

  return "'" + $Value.Replace("'", "''") + "'"
}

function Show-ScheduledUpdateStatus {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $logs = Get-ScheduledUpdateLogPaths $InstallDir
  $taskName = "CLIProxyAPI Local Manager Auto Update"
  $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

  Write-Title "定时自动更新"
  Write-PanelRow "任务名" $taskName
  Write-PanelRow "安装目录" $InstallDir
  Write-PanelRow "stdout 日志" (Join-Path $paths.Logs "auto-update.stdout.log")
  Write-PanelRow "stderr 日志" (Join-Path $paths.Logs "auto-update.stderr.log")
  Write-PanelRow "计划文件" (Join-Path $paths.InstallDir "auto-update-schedule.txt")
  if (Test-Path -LiteralPath $paths.AutoUpdateScheduleFile) {
    $cronLine = Get-Content -LiteralPath $paths.AutoUpdateScheduleFile -Encoding UTF8 |
      Where-Object { $_ -like "cron=*" } |
      Select-Object -First 1
    if ($cronLine) {
      Write-PanelRow "cron" $cronLine.Substring(5)
    }
  }

  if (-not $task) {
    Write-PanelRow "状态" "未开启"
    Write-PanelDivider
    return
  }

  $trigger = $task.Triggers | Select-Object -First 1
  $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
  Write-PanelRow "状态" $task.State
  if ($trigger -and $trigger.StartBoundary) {
    Write-PanelRow "计划" ("每日 " + ([datetime]$trigger.StartBoundary).ToString("HH:mm"))
  }
  if ($taskInfo) {
    Write-PanelRow "上次运行" $taskInfo.LastRunTime
    Write-PanelRow "下次运行" $taskInfo.NextRunTime
    Write-PanelRow "上次结果" $taskInfo.LastTaskResult
  }
  Write-PanelDivider
}

function Enable-ScheduledUpdate {
  param([string] $InstallDir)

  Ensure-InstallLayout $InstallDir
  $paths = Get-Paths $InstallDir
  $schedule = Read-ScheduleExpressionOrDefault
  $scheduleTime = $schedule.Time
  $at = [DateTime]::ParseExact($scheduleTime, "HH:mm", [Globalization.CultureInfo]::InvariantCulture)
  $taskName = "CLIProxyAPI Local Manager Auto Update"
  $stdoutLog = Join-Path $paths.Logs "auto-update.stdout.log"
  $stderrLog = Join-Path $paths.Logs "auto-update.stderr.log"
  $managerScript = Join-Path $ScriptDir "manage-cliproxyapi.ps1"
  $managerScriptArg = ConvertTo-PowerShellSingleQuotedArgument $managerScript
  $installDirArg = ConvertTo-PowerShellSingleQuotedArgument $InstallDir
  $stdoutArg = ConvertTo-PowerShellSingleQuotedArgument $stdoutLog
  $stderrArg = ConvertTo-PowerShellSingleQuotedArgument $stderrLog
  $installArguments = "-Action install -InstallDir $InstallDir"
  @(
    "cron=$($schedule.CronExpression)"
    "time=$scheduleTime"
  ) | Set-Content -LiteralPath $paths.AutoUpdateScheduleFile -Encoding UTF8

  $autoUpdateScript = @"
`$ErrorActionPreference = "Stop"
& $managerScriptArg -Action install -InstallDir $installDirArg > $stdoutArg 2> $stderrArg
if (`$LASTEXITCODE -ne `$null) {
  exit `$LASTEXITCODE
}
"@
  $autoUpdateScript | Set-Content -LiteralPath $paths.AutoUpdatePs1 -Encoding UTF8

  $taskAction = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument ("-NoProfile -ExecutionPolicy Bypass -File {0}" -f (ConvertTo-ProcessArgument $paths.AutoUpdatePs1))
  $taskTrigger = New-ScheduledTaskTrigger -Daily -At $at
  $taskSettings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew
  Register-ScheduledTask `
    -TaskName $taskName `
    -Action $taskAction `
    -Trigger $taskTrigger `
    -Settings $taskSettings `
    -Description "Daily CLIProxyAPI Local Manager auto update. CronExpression: $($schedule.CronExpression). $installArguments" `
    -Force | Out-Null

  Write-Ok "已开启定时自动更新：$($schedule.CronExpression)（每日 $scheduleTime）"
  Write-Host "任务名: $taskName"
  Write-Host "stdout 日志: $stdoutLog"
  Write-Host "stderr 日志: $stderrLog"
}

function Disable-ScheduledUpdate {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $taskName = "CLIProxyAPI Local Manager Auto Update"
  $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  if ($task) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Ok "已关闭定时自动更新"
  } else {
    Write-Ok "定时自动更新未开启"
  }
  if (Test-Path -LiteralPath $paths.AutoUpdatePs1) {
    Remove-Item -LiteralPath $paths.AutoUpdatePs1 -Force
  }
  if (Test-Path -LiteralPath $paths.AutoUpdateScheduleFile) {
    Remove-Item -LiteralPath $paths.AutoUpdateScheduleFile -Force
  }
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

function Show-WebUIInfo {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $info = Get-ConfigInfo $InstallDir
  $webuiKeyInfo = Get-WebUIManagementKeyInfo $InstallDir
  Assert-LocalOnlyConfig $InstallDir
  $url = "http://localhost:$($info.Port)/management.html"

  Write-Title "WebUI 信息"
  Write-PanelSection "访问入口"
  Write-PanelRow "WebUI" $url
  Write-PanelRow "config.yaml" $paths.Config
  Write-PanelSection "管理密钥"
  if (-not [string]::IsNullOrWhiteSpace($webuiKeyInfo.PlainKey)) {
    Write-PanelRow "WebUI 管理密钥" $webuiKeyInfo.PlainKey
  } elseif ($webuiKeyInfo.ConfigSecretIsBcrypt) {
    Write-PanelRow "WebUI 管理密钥" "<未找到 WebUI 明文密钥文件>"
  } else {
    Write-PanelRow "WebUI 管理密钥" "<未配置>"
  }

  if ($webuiKeyInfo.KeyFileExists) {
    Write-PanelRow "明文密钥文件" $paths.WebUIKey
  } else {
    Write-PanelRow "明文密钥文件" "<未找到>"
  }

  if ([string]::IsNullOrWhiteSpace($info.ManagementKey)) {
    Write-PanelRow "remote-management.secret-key" "<未配置>"
  } elseif ($webuiKeyInfo.ConfigSecretIsBcrypt) {
    Write-PanelRow "remote-management.secret-key" "<bcrypt 哈希，已隐藏>"
  } else {
    Write-PanelRow "remote-management.secret-key" $info.ManagementKey
  }
  Write-PanelDivider
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

function Split-ModelIdList {
  param([string[]] $Values)

  $result = [System.Collections.Generic.List[string]]::new()
  foreach ($value in $Values) {
    if ([string]::IsNullOrWhiteSpace($value)) {
      continue
    }
    foreach ($part in ($value -split ",")) {
      $modelId = $part.Trim()
      if (-not [string]::IsNullOrWhiteSpace($modelId) -and -not $result.Contains($modelId)) {
        $result.Add($modelId)
      }
    }
  }
  return @($result.ToArray())
}

function Get-ModelItemsFromModelsResponse {
  param($Response)

  $items = @()
  if ($null -ne $Response -and $null -ne $Response.PSObject.Properties["data"]) {
    $items = @($Response.data)
  } else {
    $items = @($Response)
  }

  return @($items)
}

function Get-ModelIdsFromModelsResponse {
  param($Response)

  $items = @(Get-ModelItemsFromModelsResponse $Response)
  $result = [System.Collections.Generic.List[string]]::new()
  foreach ($item in $items) {
    $modelId = $null
    if ($item -is [string]) {
      $modelId = $item
    } elseif ($null -ne $item -and $null -ne $item.PSObject.Properties["id"]) {
      $modelId = [string] $item.id
    }
    if (-not [string]::IsNullOrWhiteSpace($modelId) -and -not $result.Contains($modelId)) {
      $result.Add($modelId)
    }
  }
  return @($result.ToArray())
}

function Get-ModelInfoMapFromModelsResponse {
  param($Response)

  $map = @{}
  foreach ($item in @(Get-ModelItemsFromModelsResponse $Response)) {
    if ($item -is [string] -or $null -eq $item -or $null -eq $item.PSObject.Properties["id"]) {
      continue
    }
    $modelId = [string] $item.id
    if (-not [string]::IsNullOrWhiteSpace($modelId) -and -not $map.ContainsKey($modelId)) {
      $map[$modelId] = $item
    }
  }
  return $map
}

function Get-ModelPropertyValue {
  param(
    $ModelInfo,
    [string[]] $Names
  )

  if ($null -eq $ModelInfo) {
    return $null
  }

  foreach ($name in $Names) {
    if ($ModelInfo -is [System.Collections.IDictionary] -and $ModelInfo.Contains($name)) {
      return $ModelInfo[$name]
    }
    $property = $ModelInfo.PSObject.Properties[$name]
    if ($null -ne $property) {
      return $property.Value
    }
  }
  return $null
}

function ConvertTo-OptionalBoolean {
  param($Value)

  if ($null -eq $Value) {
    return $null
  }
  if ($Value -is [bool]) {
    return [bool] $Value
  }
  if ($Value -is [int] -or $Value -is [long]) {
    return [bool] $Value
  }
  if ($Value -is [string]) {
    if ($Value -match '^(?i:true|yes|1)$') {
      return $true
    }
    if ($Value -match '^(?i:false|no|0)$') {
      return $false
    }
  }
  return $null
}

function Test-ImageGenerationOnlyModel {
  param([string] $ModelId)

  $normalized = $ModelId.Trim().ToLowerInvariant()
  if ($normalized -match '^(gpt-image|dall-e)(-|$)') { return $true }
  return $normalized -in @(
    "grok-imagine-image",
    "grok-imagine-image-quality",
    "grok-imagine-video",
    "grok-imagine-video-1.5-preview"
  )
}

function Show-ModelChoices {
  param([string[]] $AvailableModelIds)

  Write-Host ""
  Write-Host "可选模型:"
  for ($i = 0; $i -lt $AvailableModelIds.Count; $i++) {
    $modelId = $AvailableModelIds[$i]
    $suffix = if (Test-ImageGenerationOnlyModel $modelId) { "  (图片生成专用，跳过)" } else { "" }
    Write-Host ("  {0}) {1}{2}" -f ($i + 1), $modelId, $suffix)
  }
}

function Resolve-ModelIdSelection {
  param(
    [string[]] $Values,
    [string[]] $AvailableModelIds,
    [bool] $DefaultAll = $false
  )

  $tokens = @(Split-ModelIdList $Values)
  if ($tokens.Count -eq 0) {
    if ($DefaultAll) {
      return @($AvailableModelIds)
    }
    return @()
  }

  $result = [System.Collections.Generic.List[string]]::new()
  foreach ($token in $tokens) {
    if ($token -eq "*" -or $token -eq "all") {
      foreach ($modelId in $AvailableModelIds) {
        if (-not $result.Contains($modelId)) {
          $result.Add($modelId)
        }
      }
      continue
    }

    if ($token -match '^(\d+)\s*-\s*(\d+)$') {
      $start = [int] $Matches[1]
      $end = [int] $Matches[2]
      if ($start -gt $end) {
        throw "无效的模型范围: $token"
      }
      for ($number = $start; $number -le $end; $number++) {
        if ($number -lt 1 -or $number -gt $AvailableModelIds.Count) {
          throw "模型编号超出范围: $number"
        }
        $modelId = $AvailableModelIds[$number - 1]
        if (-not $result.Contains($modelId)) {
          $result.Add($modelId)
        }
      }
      continue
    }

    if ($token -match '^\d+$') {
      $number = [int] $token
      if ($number -lt 1 -or $number -gt $AvailableModelIds.Count) {
        throw "模型编号超出范围: $number"
      }
      $modelId = $AvailableModelIds[$number - 1]
      if (-not $result.Contains($modelId)) {
        $result.Add($modelId)
      }
      continue
    }

    if (-not $result.Contains($token)) {
      $result.Add($token)
    }
  }

  return @($result.ToArray())
}

function Get-CatalogModelCandidates {
  param(
    $Catalog,
    [string] $ModelId
  )

  $result = [System.Collections.Generic.List[object]]::new()
  foreach ($group in @($Catalog.PSObject.Properties)) {
    foreach ($item in @($group.Value)) {
      if ($null -eq $item) { continue }
      $id = Get-ModelPropertyValue -ModelInfo $item -Names @("id")
      if ($id -is [string] -and $id.Trim() -ceq $ModelId) {
        $result.Add($item)
      }
    }
  }
  return @($result.ToArray())
}

function ConvertTo-CatalogInteger {
  param(
    $Value,
    [switch] $Positive
  )

  if ($null -eq $Value -or $Value -is [bool]) { return $null }
  if ($Value -isnot [byte] -and $Value -isnot [int16] -and $Value -isnot [int32] -and $Value -isnot [int64]) {
    return $null
  }
  $number = [int64]$Value
  if ($Positive -and $number -le 0) { return $null }
  return $number
}

function Get-CandidateTokenValue {
  param(
    $Candidate,
    [string] $ModelId,
    [string] $FieldName,
    [string] $PrimaryName,
    [string] $AliasName
  )

  $primaryRaw = Get-ModelPropertyValue -ModelInfo $Candidate -Names @($PrimaryName)
  $aliasRaw = Get-ModelPropertyValue -ModelInfo $Candidate -Names @($AliasName)
  $primary = ConvertTo-CatalogInteger -Value $primaryRaw -Positive
  $alias = ConvertTo-CatalogInteger -Value $aliasRaw -Positive
  if ($null -ne $primary -and $null -ne $alias -and $primary -ne $alias) {
    Write-JsonWarn "$ModelId 的 $FieldName 字段别名冲突，已省略"
    return $null
  }
  if ($null -ne $primary) { return $primary }
  return $alias
}

function Get-NormalizedStringArray {
  param(
    $Value,
    [switch] $Sort
  )

  if ($null -eq $Value -or $Value -is [string]) { return $null }
  $values = [System.Collections.Generic.List[string]]::new()
  $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  foreach ($item in @($Value)) {
    if ($item -isnot [string]) { return $null }
    $normalized = $item.Trim().ToLowerInvariant()
    if ($normalized -and $seen.Add($normalized)) { $values.Add($normalized) }
  }
  $result = @($values.ToArray())
  if ($Sort) { $result = @($result | Sort-Object) }
  return ,$result
}

function Merge-NormalizedField {
  param(
    [object[]] $Records,
    [string] $FieldName,
    [string] $ModelId
  )

  $values = [System.Collections.Generic.List[object]]::new()
  $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  foreach ($record in $Records) {
    $property = $record.PSObject.Properties[$FieldName]
    if ($null -eq $property) { continue }
    $key = $property.Value | ConvertTo-Json -Compress -Depth 10
    if ($keys.Add($key)) { $values.Add($property.Value) }
  }
  if ($values.Count -gt 1) {
    Write-JsonWarn "$ModelId 的 $FieldName 字段在模型目录中冲突，已省略"
    return [pscustomobject]@{ HasValue = $false; Value = $null }
  }
  if ($values.Count -eq 1) {
    return [pscustomobject]@{ HasValue = $true; Value = $values[0] }
  }
  return [pscustomobject]@{ HasValue = $false; Value = $null }
}

function Get-NormalizedCatalogModel {
  param(
    $Catalog,
    [string] $ModelId
  )

  $candidates = @(Get-CatalogModelCandidates -Catalog $Catalog -ModelId $ModelId)
  $records = [System.Collections.Generic.List[object]]::new()
  foreach ($candidate in $candidates) {
    $record = [ordered]@{}
    $displayName = Get-ModelPropertyValue -ModelInfo $candidate -Names @("display_name")
    if ($displayName -is [string] -and -not [string]::IsNullOrWhiteSpace($displayName)) {
      $record.displayName = $displayName.Trim()
    }
    $contextTokens = Get-CandidateTokenValue -Candidate $candidate -ModelId $ModelId -FieldName "contextTokens" -PrimaryName "context_length" -AliasName "inputTokenLimit"
    if ($null -ne $contextTokens) { $record.contextTokens = $contextTokens }
    $outputTokens = Get-CandidateTokenValue -Candidate $candidate -ModelId $ModelId -FieldName "outputTokens" -PrimaryName "max_completion_tokens" -AliasName "outputTokenLimit"
    if ($null -ne $outputTokens) { $record.outputTokens = $outputTokens }

    $supportedParametersProperty = $candidate.PSObject.Properties["supported_parameters"]
    $supportedParameters = if ($null -ne $supportedParametersProperty) { Get-NormalizedStringArray -Value $supportedParametersProperty.Value } else { $null }
    if ($null -ne $supportedParameters -and $supportedParameters -contains "tools") {
      $record.toolCall = $true
    }

    $modalitiesProperty = $candidate.PSObject.Properties["supportedInputModalities"]
    $modalitiesRaw = if ($null -ne $modalitiesProperty) { $modalitiesProperty.Value } else { $null }
    $modalities = Get-NormalizedStringArray -Value $modalitiesRaw -Sort
    if ($null -ne $modalities) {
      $record.inputModalities = @($modalities)
      $record.supportsImages = [bool]($modalities -contains "image")
    }

    $thinking = Get-ModelPropertyValue -ModelInfo $candidate -Names @("thinking")
    if ($null -ne $thinking -and $null -ne $thinking.PSObject) {
      $levelsProperty = $thinking.PSObject.Properties["levels"]
      $levels = if ($null -ne $levelsProperty) { Get-NormalizedStringArray -Value $levelsProperty.Value } else { $null }
      $min = ConvertTo-CatalogInteger (Get-ModelPropertyValue -ModelInfo $thinking -Names @("min"))
      $max = ConvertTo-CatalogInteger (Get-ModelPropertyValue -ModelInfo $thinking -Names @("max"))
      $validRange = -not ($null -ne $min -and $null -ne $max -and $min -gt $max)
      if ($validRange -and (($null -ne $levels -and @($levels).Count -gt 0) -or $null -ne $min -or $null -ne $max)) {
        $record.reasoningSupported = $true
        if ($null -ne $levels -and @($levels).Count -gt 0) { $record.reasoningLevels = @($levels) }
      }
    }
    $records.Add([pscustomobject]$record)
  }

  $normalized = [ordered]@{ Found = ($candidates.Count -gt 0) }
  foreach ($fieldName in @("displayName", "contextTokens", "outputTokens", "toolCall", "supportsImages", "inputModalities", "reasoningSupported", "reasoningLevels")) {
    $merged = Merge-NormalizedField -Records @($records.ToArray()) -FieldName $fieldName -ModelId $ModelId
    if ($merged.HasValue) { $normalized[$fieldName] = $merged.Value }
  }
  $normalized.nonChat = Test-ImageGenerationOnlyModel $ModelId
  return [pscustomobject]$normalized
}

function New-WorkBuddyModelEntry {
  param(
    [string] $ModelId,
    [string] $Url,
    [string] $ApiKey,
    [string] $Vendor,
    [bool] $ExplicitSupportsImages,
    [bool] $IncludeTokenLimits = $false,
    $ModelInfo
  )

  $entry = [ordered]@{
    id = $ModelId
    name = if ($ModelInfo.displayName) { $ModelInfo.displayName } else { $ModelId }
    vendor = $Vendor
    url = $Url
    apiKey = $ApiKey
  }

  if ($ModelInfo.toolCall) { $entry.supportsToolCall = $true }
  if ($ExplicitSupportsImages) {
    $entry.supportsImages = $true
  } elseif ($null -ne $ModelInfo.PSObject.Properties["supportsImages"]) {
    $entry.supportsImages = [bool]$ModelInfo.supportsImages
  }
  if ($ModelInfo.reasoningSupported) {
    $entry.supportsReasoning = $true
    $allowedEfforts = @("low", "medium", "high", "xhigh")
    $efforts = @($ModelInfo.reasoningLevels | Where-Object { $allowedEfforts -contains $_ })
    if ($efforts.Count -gt 0) {
      $entry.reasoning = [ordered]@{ supportedEfforts = $efforts }
    }
  }

  if ($IncludeTokenLimits) {
    if ($null -ne $ModelInfo.PSObject.Properties["contextTokens"]) { $entry.maxInputTokens = $ModelInfo.contextTokens }
    if ($null -ne $ModelInfo.PSObject.Properties["outputTokens"]) { $entry.maxOutputTokens = $ModelInfo.outputTokens }
  }

  return $entry
}

function Show-WorkBuddyModelsJson {
  param(
    [string] $InstallDir,
    [string] $Vendor = "CLIProxyAPI",
    [string[]] $ModelIds = @(),
    [string[]] $ImageModelIds = @(),
    [switch] $IncludeTokenLimits
  )

  $info = Get-ConfigInfo $InstallDir
  Assert-LocalOnlyConfig $InstallDir
  $catalogPath = Ensure-ModelCatalog $InstallDir
  $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ([string]::IsNullOrWhiteSpace($Vendor)) { $Vendor = "CLIProxyAPI" }

  $selectedModelIds = @(Split-ModelIdList $ModelIds)
  $availableModelIds = @()
  $promptedForModelIds = $false
  $clientKey = $info.ClientKey
  if ($selectedModelIds.Count -eq 0) {
    if ([string]::IsNullOrWhiteSpace($clientKey)) {
      $clientKey = Read-Host "客户端 API Key（用于读取 /v1/models）"
    }
    $url = "http://$($info.Host):$($info.Port)/v1/models"
    $response = Invoke-RestMethod -Uri $url -Headers @{ Authorization = "Bearer $clientKey" }
    $availableModelIds = @(Get-ModelIdsFromModelsResponse $response)
    if ($availableModelIds.Count -eq 0) {
      throw "/v1/models 没有返回可用模型。"
    }
    Show-ModelChoices $availableModelIds
    $inputModelIds = Read-Host "选择模型（编号/范围/ID，逗号分隔；留空=全部）"
    $selectedModelIds = @(Resolve-ModelIdSelection -Values @($inputModelIds) -AvailableModelIds $availableModelIds -DefaultAll $true)
    $IncludeTokenLimits = Confirm-Yes "输出 maxInputTokens/maxOutputTokens？" $false
    $promptedForModelIds = $true
  }

  if ($selectedModelIds.Count -eq 0) {
    throw "没有可输出的模型 ID。请先查询 /v1/models，或使用 -ModelIds 指定。"
  }

  $selectedImageModelIds = @(Split-ModelIdList $ImageModelIds)
  if ($promptedForModelIds -and $selectedImageModelIds.Count -gt 0) {
    $selectedImageModelIds = @(Resolve-ModelIdSelection -Values $ImageModelIds -AvailableModelIds $availableModelIds -DefaultAll $false)
  }

  $apiKeyForJson = $info.ClientKey
  if ([string]::IsNullOrWhiteSpace($apiKeyForJson)) {
    $apiKeyForJson = $clientKey
  }
  if ([string]::IsNullOrWhiteSpace($apiKeyForJson)) {
    $apiKeyForJson = Read-Host "WorkBuddy API Key（留空使用占位符）"
  }
  if ([string]::IsNullOrWhiteSpace($apiKeyForJson)) {
    $apiKeyForJson = "<从 config.yaml api-keys 读取>"
  }

  $allImageInputModels = $selectedImageModelIds -contains "*" -or $selectedImageModelIds -contains "all"
  $models = [System.Collections.Generic.List[object]]::new()
  $chatUrl = "http://127.0.0.1:$($info.Port)/v1/chat/completions"
  foreach ($modelId in $selectedModelIds) {
    $modelInfo = Get-NormalizedCatalogModel -Catalog $catalog -ModelId $modelId
    if ($modelInfo.nonChat) {
      Write-JsonWarn "跳过 $modelId：这是图片/视频生成专用模型，不适合作为 WorkBuddy 聊天模型。"
      continue
    }
    if (-not $modelInfo.Found) {
      Write-JsonWarn "$modelId 不在本地模型目录中，仅输出基础连接字段"
    }
    $supportsImageInput = [bool]($allImageInputModels -or ($selectedImageModelIds -contains $modelId))
    $models.Add((New-WorkBuddyModelEntry -ModelId $modelId -Url $chatUrl -ApiKey $apiKeyForJson -Vendor $Vendor -ExplicitSupportsImages $supportsImageInput -IncludeTokenLimits ([bool]$IncludeTokenLimits) -ModelInfo $modelInfo))
  }

  if ($models.Count -eq 0) {
    throw "没有可输出的 WorkBuddy 聊天模型。gpt-image-* 只能走 /v1/images/generations 或 /v1/images/edits。"
  }

  [ordered]@{
    models = @($models.ToArray())
  } | ConvertTo-Json -Depth 20
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

function Show-ClientConfig {
  param(
    [string] $InstallDir,
    [string] $Format = "workbuddy",
    [string] $Vendor = "CLIProxyAPI",
    [string[]] $ModelIds = @(),
    [string[]] $ImageModelIds = @(),
    [switch] $IncludeTokenLimits
  )

  $normalizedFormat = $Format.Trim().ToLowerInvariant()
  switch ($normalizedFormat) {
    "workbuddy" {
      Show-WorkBuddyModelsJson -InstallDir $InstallDir -Vendor $Vendor -ModelIds $ModelIds -ImageModelIds $ImageModelIds -IncludeTokenLimits:$IncludeTokenLimits
    }
    default { throw "不支持的客户端配置格式: $Format。当前支持: workbuddy" }
  }
}

function Invoke-Action {
  param(
    [string] $SelectedAction,
    [string] $InstallDir,
    [string] $Format = "workbuddy",
    [string] $Vendor = "CLIProxyAPI",
    [string[]] $ModelIds = @(),
    [string[]] $ImageModelIds = @(),
    [switch] $IncludeTokenLimits
  )

  switch ($SelectedAction) {
    "status" { Show-Status $InstallDir }
    "install" { Install-OrUpdate $InstallDir }
    "config" { Generate-Config $InstallDir }
    "start" { Start-CLIProxyAPI $InstallDir }
    "stop" { Stop-CLIProxyAPI $InstallDir }
    "health" { Test-Health $InstallDir }
    "webui-info" { Show-WebUIInfo $InstallDir }
    "webui" { Open-WebUI $InstallDir }
    "oauth" { Invoke-CodexLogin -InstallDir $InstallDir -DeviceCode $false }
    "device-login" { Invoke-CodexLogin -InstallDir $InstallDir -DeviceCode $true }
    "models" { Query-Models $InstallDir }
    "workbuddy" { Show-WorkBuddyInfo $InstallDir }
    "client-config" { Show-ClientConfig -InstallDir $InstallDir -Format $Format -Vendor $Vendor -ModelIds $ModelIds -ImageModelIds $ImageModelIds -IncludeTokenLimits:$IncludeTokenLimits }
    "workbuddy-json" {
      Write-JsonWarn "workbuddy-json 已弃用；请改用 client-config -Format workbuddy"
      Show-ClientConfig -InstallDir $InstallDir -Format "workbuddy" -Vendor $Vendor -ModelIds $ModelIds -ImageModelIds $ImageModelIds -IncludeTokenLimits:$IncludeTokenLimits
    }
    "schedule-status" { Show-ScheduledUpdateStatus $InstallDir }
    "schedule-enable" { Enable-ScheduledUpdate $InstallDir }
    "schedule-disable" { Disable-ScheduledUpdate $InstallDir }
    "cleanup" {
      Clear-UpdateCache -InstallDir $InstallDir
      Prune-OldManagedBackups -InstallDir $InstallDir
    }
    default { throw "未知 action: $SelectedAction" }
  }
}

function Show-Menu {
  param([string] $InstallDir)

  while ($true) {
    $paths = Get-Paths $InstallDir
    $info = Get-ConfigInfo $InstallDir
    $state = Get-ServiceState $InstallDir
    $webuiKeyInfo = Get-WebUIManagementKeyInfo $InstallDir
    $exeStatus = if (Test-Path -LiteralPath $paths.Exe) { "已安装" } else { "未安装" }
    $configStatus = if (Test-Path -LiteralPath $paths.Config) { "已配置" } else { "未配置" }
    $managementKeyStatus = if (-not [string]::IsNullOrWhiteSpace($webuiKeyInfo.PlainKey)) {
      "明文可用"
    } elseif ([string]::IsNullOrWhiteSpace($info.ManagementKey)) {
      "未配置"
    } elseif ($webuiKeyInfo.ConfigSecretIsBcrypt) {
      "未找到明文文件"
    } else {
      "已配置"
    }

    Write-Title "CLIProxyAPI 本地管理器"
    Write-PanelSection "本机状态"
    Write-PanelRow "短路径" (Get-ShortPath $InstallDir)
    Write-PanelRow "安装目录" $InstallDir
    Write-PanelRow "程序" $exeStatus
    Write-PanelRow "配置" $configStatus
    Write-PanelRow "服务" $state.Status
    Write-PanelRow "API" "http://127.0.0.1:$($info.Port)/v1"
    Write-PanelRow "WebUI" "http://localhost:$($info.Port)/management.html"
    Write-PanelRow "WebUI 密钥" $managementKeyStatus

    Write-MenuSection "安装配置"
    Write-MenuPair "1)" "安装或更新 CLIProxyAPI" "2)" "生成本地 config.yaml"
    Write-MenuSection "服务运行"
    Write-MenuPair "3)" "启动服务" "4)" "停止服务"
    Write-MenuItem "5)" "运行状态"
    Write-MenuSection "WebUI"
    Write-MenuPair "6)" "WebUI 信息" "7)" "打开 WebUI"
    Write-MenuSection "登录"
    Write-MenuPair "8)" "Codex 浏览器 OAuth 登录" "9)" "Codex 设备码登录"
    Write-MenuSection "检查集成"
    Write-MenuPair "10)" "健康检查" "11)" "模型列表"
    Write-MenuPair "12)" "WorkBuddy 信息" "13)" "客户端模型配置"
    Write-MenuSection "自动更新"
    Write-MenuPair "14)" "查看定时更新" "15)" "开启/修改定时更新"
    Write-MenuItem "16)" "关闭定时更新"
    Write-MenuSection "存储清理"
    Write-MenuItem "17)" "清理下载缓存和旧备份"
    Write-MenuSection "设置"
    Write-MenuPair "D)" "更改安装目录" "Q/0)" "退出"
    Write-PanelDivider
    $choice = Read-Host "请选择操作 [0-17/D]"

    try {
      switch ($choice) {
        "1" { Install-OrUpdate $InstallDir }
        "2" { Generate-Config $InstallDir }
        "3" { Start-CLIProxyAPI $InstallDir }
        "4" { Stop-CLIProxyAPI $InstallDir }
        "5" { Show-Status $InstallDir }
        "6" { Show-WebUIInfo $InstallDir }
        "7" { Open-WebUI $InstallDir }
        "8" { Invoke-CodexLogin -InstallDir $InstallDir -DeviceCode $false }
        "9" { Invoke-CodexLogin -InstallDir $InstallDir -DeviceCode $true }
        "10" { Test-Health $InstallDir }
        "11" { Query-Models $InstallDir }
        "12" { Show-WorkBuddyInfo $InstallDir }
        "13" {
          $menuVendor = Read-Host "Vendor（回车使用 CLIProxyAPI）"
          if ([string]::IsNullOrWhiteSpace($menuVendor)) { $menuVendor = "CLIProxyAPI" }
          Show-ClientConfig -InstallDir $InstallDir -Format "workbuddy" -Vendor $menuVendor
        }
        "14" { Show-ScheduledUpdateStatus $InstallDir }
        "15" { Enable-ScheduledUpdate $InstallDir }
        "16" { Disable-ScheduledUpdate $InstallDir }
        "17" {
          Clear-UpdateCache -InstallDir $InstallDir -Interactive
          Prune-OldManagedBackups -InstallDir $InstallDir -Interactive
        }
        "D" { $InstallDir = Select-InstallDir; Save-State -InstallDir $InstallDir -ReleaseTag "" }
        "d" { $InstallDir = Select-InstallDir; Save-State -InstallDir $InstallDir -ReleaseTag "" }
        "Q" { return }
        "q" { return }
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

$installDir = Resolve-InstallDir -RequestedInstallDir $InstallDir -Interactive ($Action -eq "menu")
if ($Action -eq "menu") {
  Show-Menu $installDir
} else {
  Invoke-Action -SelectedAction $Action -InstallDir $installDir -Format $Format -Vendor $Vendor -ModelIds $ModelIds -ImageModelIds $ImageModelIds -IncludeTokenLimits:$IncludeTokenLimits
}
