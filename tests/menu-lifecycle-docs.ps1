$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ReadmePath = Join-Path $RepoRoot "README.md"
$DesignPath = Join-Path $RepoRoot "docs\design.md"
$WindowsScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$MacosScriptPath = Join-Path $RepoRoot "scripts\macos\manage-cliproxyapi.sh"
$text = @(
  Get-Content -LiteralPath $ReadmePath -Raw -Encoding UTF8
  Get-Content -LiteralPath $DesignPath -Raw -Encoding UTF8
) -join "`n"

foreach ($required in @(
  "自动复用安装目录",
  "菜单按功能分区",
  "WebUI 信息",
  "WebUI URL",
  "WebUI 管理密钥",
  "完整 WebUI 管理密钥",
  "webui-management-key.txt",
  "bcrypt 哈希",
  "status 不显示完整密钥",
  "受管 start/status/stop",
  "启动服务",
  "停止服务",
  "运行状态",
  "cli-proxy-api.pid",
  "logs/cli-proxy-api.stdout.log",
  "logs/cli-proxy-api.stderr.log",
  "管理器只停止自己验证过的 PID",
  "定时自动更新",
  "每日 04:00",
  "0 4 * * *",
  "HH:mm",
  "每日固定时间 cron",
  "logs/auto-update.stdout.log",
  "logs/auto-update.stderr.log"
)) {
  if ($text -notmatch [regex]::Escape($required)) {
    throw "docs are missing lifecycle/menu text: $required"
  }
}

$windowsMenu = Get-Content -LiteralPath $WindowsScriptPath -Raw -Encoding UTF8
$macosMenu = Get-Content -LiteralPath $MacosScriptPath -Raw -Encoding UTF8
$expectedMenuLines = @(
  "安装配置",
  "1)",
  "安装或更新 CLIProxyAPI",
  "2)",
  "生成本地 config.yaml",
  "服务运行",
  "3)",
  "启动服务",
  "4)",
  "停止服务",
  "5)",
  "运行状态",
  "WebUI",
  "6)",
  "WebUI 信息",
  "7)",
  "打开 WebUI",
  "登录",
  "8)",
  "Codex 浏览器 OAuth 登录",
  "9)",
  "Codex 设备码登录",
  "检查集成",
  "10)",
  "健康检查",
  "11)",
  "模型列表",
  "12)",
  "WorkBuddy 信息",
  "13)",
  "客户端模型配置",
  "自动更新",
  "14)",
  "查看定时更新",
  "15)",
  "开启/修改定时更新",
  "16)",
  "关闭定时更新",
  "设置"
)

foreach ($script in @(
  @{ Name = "windows"; Text = $windowsMenu },
  @{ Name = "macos"; Text = $macosMenu }
)) {
  foreach ($line in $expectedMenuLines) {
    if ($script.Text -notmatch [regex]::Escape($line)) {
      throw "$($script.Name) menu is missing expected grouped menu line: $line"
    }
  }
}

foreach ($expectedMapping in @(
  "1) install",
  "2) config",
  "3) start",
  "4) stop",
  "5) status",
  "6) webui-info",
  "7) webui",
  "8) oauth",
  "9) device-login",
  "10) health",
  "11) models",
  "12) workbuddy",
  "13) client-config",
  "14) schedule-status",
  "15) schedule-enable",
  "16) schedule-disable"
)) {
  $number = $expectedMapping.Split(")")[0]
  $action = $expectedMapping.Split(" ")[1]
  if ($windowsMenu -notmatch [regex]::Escape("`"$number`" {") -or $windowsMenu -notmatch [regex]::Escape("`"$action`"")) {
    throw "windows menu/action mapping is missing expected route: $expectedMapping"
  }
  if ($macosMenu -notmatch [regex]::Escape("$number)") -or $macosMenu -notmatch [regex]::Escape("$action)")) {
    throw "macos menu/action mapping is missing expected route: $expectedMapping"
  }
}

Write-Output "MENU_LIFECYCLE_DOCS_OK"
