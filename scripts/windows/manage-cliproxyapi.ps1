param(
  [ValidateSet("menu", "status", "install", "config", "start", "stop", "health", "webui", "webui-info", "oauth", "device-login", "models", "workbuddy")]
  [string] $Action = "menu",
  [string] $InstallDir,
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
  stop          停止由本管理器启动并校验通过的 CLIProxyAPI
  health        API 可用性检查（GET /v1/models）
  webui-info    输出 WebUI 地址和 remote-management.secret-key
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

  $state = Read-State
  if ($state -and $state.installDir) {
    return (Expand-InstallPath $state.installDir)
  }

  $defaultPaths = Get-Paths $DefaultInstallDir
  if ((Test-Path -LiteralPath $defaultPaths.Exe) -or (Test-Path -LiteralPath $defaultPaths.Config)) {
    return (Expand-InstallPath $DefaultInstallDir)
  }

  if ($Interactive) {
    return Select-InstallDir
  }

  return (Expand-InstallPath $DefaultInstallDir)
}

function Get-Paths {
  param([string] $InstallDir)

  return [ordered]@{
    InstallDir = $InstallDir
    Exe = Join-Path $InstallDir "cli-proxy-api.exe"
    Config = Join-Path $InstallDir "config.yaml"
    WebUIKey = Join-Path $InstallDir "webui-management-key.txt"
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
    }
  }

  if (-not [string]::IsNullOrWhiteSpace($info.ManagementKey) -and -not (Test-BcryptHash $info.ManagementKey)) {
    return [pscustomobject]@{
      PlainKey = $info.ManagementKey
      Source = $paths.Config
      ConfigSecretIsBcrypt = $false
      ConfigSecret = $info.ManagementKey
    }
  }

  return [pscustomobject]@{
    PlainKey = ""
    Source = ""
    ConfigSecretIsBcrypt = (Test-BcryptHash $info.ManagementKey)
    ConfigSecret = $info.ManagementKey
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
  $managementKeyStatus = if ([string]::IsNullOrWhiteSpace($info.ManagementKey)) { "未配置" } else { "已配置" }
  return "exe: $exeStatus | config: $configStatus | 服务: $($state.Status) | 端口: $($info.Port) | WebUI 密钥: $managementKeyStatus"
}

function Show-Status {
  param([string] $InstallDir)

  $paths = Get-Paths $InstallDir
  $info = Get-ConfigInfo $InstallDir
  $state = Get-ServiceState $InstallDir
  $managementKeyStatus = if ([string]::IsNullOrWhiteSpace($info.ManagementKey)) { "未配置" } else { "已配置" }
  Write-Host ""
  Write-Host "项目根目录: $ProjectRoot"
  Write-Host "状态文件:   $StatePath"
  Write-Host "安装目录:   $InstallDir"
  Write-Host "可执行文件: $($paths.Exe) [$((Test-Path -LiteralPath $paths.Exe))]"
  Write-Host "配置文件:   $($paths.Config) [$((Test-Path -LiteralPath $paths.Config))]"
  Write-Host "服务状态:   $($state.Status)"
  if ($state.Pid) {
    Write-Host "服务 PID:   $($state.Pid)"
  }
  Write-Host "WebUI 管理密钥: $managementKeyStatus"
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
  Write-Host ""
  Write-Host "WebUI:"
  Write-Host $url
  Write-Host ""
  Write-Host "WebUI 管理密钥:"
  if (-not [string]::IsNullOrWhiteSpace($webuiKeyInfo.PlainKey)) {
    Write-Host $webuiKeyInfo.PlainKey
  } elseif ($webuiKeyInfo.ConfigSecretIsBcrypt) {
    Write-Host "<config.yaml 中是 bcrypt 哈希，无法反推出明文；请使用首次生成时保存的管理密钥，或重新生成配置>"
  } else {
    Write-Host "<未配置>"
  }
  Write-Host ""
  Write-Host "config.yaml:"
  Write-Host $paths.Config
  Write-Host ""
  Write-Host "WebUI 明文密钥文件:"
  Write-Host $paths.WebUIKey
  Write-Host ""
  Write-Host "remote-management.secret-key:"
  if ([string]::IsNullOrWhiteSpace($info.ManagementKey)) {
    Write-Host "<未配置>"
  } elseif ($webuiKeyInfo.ConfigSecretIsBcrypt) {
    Write-Host "<bcrypt 哈希，非 WebUI 登录明文，已隐藏>"
  } else {
    Write-Host $info.ManagementKey
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
    "stop" { Stop-CLIProxyAPI $InstallDir }
    "health" { Test-Health $InstallDir }
    "webui-info" { Show-WebUIInfo $InstallDir }
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
    Write-Host "短路径: $(Get-ShortPath $InstallDir)"
    Write-Host "完整安装目录: $InstallDir"
    Write-Host "摘要: $(Get-InstallSummary $InstallDir)"
    Write-Host ""
    Write-Host "[安装配置]"
    Write-Host "  1. 安装或更新 CLIProxyAPI"
    Write-Host "  2. 生成本地 config.yaml"
    Write-Host "[服务运行]"
    Write-Host "  3. 启动服务"
    Write-Host "  4. 停止服务"
    Write-Host "  5. 运行状态"
    Write-Host "[WebUI]"
    Write-Host "  6. WebUI 信息"
    Write-Host "  7. 打开 WebUI"
    Write-Host "[登录]"
    Write-Host "  8. Codex 浏览器 OAuth 登录"
    Write-Host "  9. Codex 设备码登录"
    Write-Host "[检查集成]"
    Write-Host "  10. 健康检查"
    Write-Host "  11. 模型列表"
    Write-Host "  12. WorkBuddy 信息"
    Write-Host "[设置]"
    Write-Host "  D. 更改安装目录"
    Write-Host "  Q/0. 退出"
    $choice = Read-Host "请选择"

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
  Invoke-Action -SelectedAction $Action -InstallDir $installDir
}
