$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\macos\manage-cliproxyapi.sh"
$text = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

function Get-Section {
  param(
    [string] $StartToken,
    [string] $EndToken
  )

  $startIndex = $text.IndexOf($StartToken)
  $endIndex = $text.IndexOf($EndToken, [Math]::Max($startIndex, 0))
  if ($startIndex -lt 0 -or $endIndex -lt $startIndex) {
    throw "Could not locate section from '$StartToken' to '$EndToken'"
  }
  return $text.Substring($startIndex, $endIndex - $startIndex)
}

function Text-FromCodepoints {
  param([int[]] $Codepoints)
  return -join ($Codepoints | ForEach-Object { [char] $_ })
}

function Assert-Contains {
  param(
    [string] $Haystack,
    [string] $Needle,
    [string] $Message
  )

  if (-not $Haystack.Contains($Needle)) {
    throw $Message
  }
}

function Assert-Match {
  param(
    [string] $Haystack,
    [string] $Pattern,
    [string] $Message
  )

  if ($Haystack -notmatch $Pattern) {
    throw $Message
  }
}

$webUiKeyLabel = Text-FromCodepoints @(0x0057, 0x0065, 0x0062, 0x0055, 0x0049, 0x0020, 0x5bc6, 0x94a5)
$menuInstallConfig = Text-FromCodepoints @(0x5b89, 0x88c5, 0x914d, 0x7f6e)
$menuServiceRuntime = Text-FromCodepoints @(0x670d, 0x52a1, 0x8fd0, 0x884c)
$menuLogin = Text-FromCodepoints @(0x767b, 0x5f55)
$menuIntegrationChecks = Text-FromCodepoints @(0x68c0, 0x67e5, 0x96c6, 0x6210)
$menuSettings = Text-FromCodepoints @(0x8bbe, 0x7f6e)

$pathsBody = Get-Section "paths_for()" "ensure_install_layout()"
foreach ($token in @("webui_key)", "logs)", "stdout_log)", "stderr_log)", "pid_file)")) {
  Assert-Contains $pathsBody $token "paths_for is missing '$token'"
}
foreach ($token in @("cli-proxy-api.stdout.log", "cli-proxy-api.stderr.log", "cli-proxy-api.pid")) {
  Assert-Contains $pathsBody $token "paths_for is missing path token '$token'"
}
Assert-Contains $pathsBody "webui-management-key.txt" "paths_for is missing saved plaintext WebUI key path"

$layoutBody = Get-Section "ensure_install_layout()" "architecture_regex()"
Assert-Contains $layoutBody '$(paths_for "$install_dir" logs)' "ensure_install_layout should create logs directory"

$startBody = Get-Section "start_clip_proxy_api()" "health_check()"
Assert-Contains $startBody 'nohup "$exe" -config "$config" >"$stdout_log" 2>"$stderr_log" &' "start should use nohup with stdout/stderr logs"
Assert-Contains $startBody 'echo $! > "$pid_file"' "start should write pid file"
if ($startBody -match '\bopen\b') {
  throw "start_clip_proxy_api should not use open/Terminal for lifecycle start"
}

foreach ($functionName in @("managed_process_state", "service_status_text", "stop_clip_proxy_api")) {
  Assert-Match $text "(?m)^$functionName\(\) \{" "Missing function: $functionName"
}
foreach ($functionName in @("is_bcrypt_hash", "webui_plain_management_key")) {
  Assert-Match $text "(?m)^$functionName\(\) \{" "Missing WebUI key helper function: $functionName"
}

$managedBody = Get-Section "managed_process_state()" "service_status_text()"
foreach ($token in @(
  'exe=$(paths_for "$install_dir" exe)',
  'config=$(paths_for "$install_dir" config)',
  'process_command=$(ps -p "$pid" -o command= 2>/dev/null || true)',
  '"$exe "*',
  '" -config $config"'
)) {
  Assert-Contains $managedBody $token "managed_process_state must validate current executable and config token '$token'"
}
if ($managedBody.Contains('*cli-proxy-api*')) {
  throw "managed_process_state must not treat any cli-proxy-api command line as managed"
}

$statusBody = Get-Section "show_status()" "show_webui_info()"
foreach ($token in @("service_status_label", "pid_file", "logs", "webui_key_status_text", $webUiKeyLabel)) {
  Assert-Contains $statusBody $token "show_status is missing '$token'"
}
foreach ($forbidden in @('$management_key', 'config_value "$config" management_key', "secret-key")) {
  if ($statusBody.Contains($forbidden)) {
    throw "show_status must not print the full WebUI management key token: $forbidden"
  }
}

$managementHelperBody = Get-Section "has_management_key()" "assert_local_only_config()"
foreach ($token in @("remote-management", "secret-key")) {
  Assert-Contains $managementHelperBody $token "has_management_key should only inspect remote-management.secret-key using '$token'"
}

$runActionBody = Get-Section "run_action()" "show_menu()"
Assert-Contains $runActionBody 'stop) stop_clip_proxy_api "$install_dir" ;;' "run_action should dispatch stop"
Assert-Contains $runActionBody 'webui-info) show_webui_info "$install_dir" ;;' "run_action should dispatch webui-info"

foreach ($banned in @("pkill", "killall", "kill -9")) {
  if ($text.Contains($banned)) {
    throw "macOS manager must not use banned process termination command: $banned"
  }
}

$menuBody = Get-Section "show_menu()" 'ACTION="menu"'
foreach ($token in @("short_install_path", "webui_key_status_text", $menuInstallConfig, $menuServiceRuntime, "WebUI", $menuLogin, $menuIntegrationChecks, $menuSettings)) {
  Assert-Contains $menuBody $token "menu is missing '$token'"
}
foreach ($number in 1..12) {
  Assert-Match $menuBody "(?m)\s$number\)" "menu should map option $number"
}
foreach ($pattern in @("D|d)", "Q|q|0)")) {
  Assert-Contains $menuBody $pattern "menu should map '$pattern'"
}
Assert-Contains $menuBody 'if ! IFS= read -r choice; then' "menu should return cleanly when stdin reaches EOF"
Assert-Contains $menuBody 'return 0' "menu should return on EOF instead of looping"

Write-Output "MACOS_LIFECYCLE_STATIC_OK"
