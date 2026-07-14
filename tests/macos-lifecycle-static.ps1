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
$menuAutoUpdate = Text-FromCodepoints @(0x81ea, 0x52a8, 0x66f4, 0x65b0)
$menuSettings = Text-FromCodepoints @(0x8bbe, 0x7f6e)

$pathsBody = Get-Section "paths_for()" "ensure_install_layout()"
foreach ($token in @("webui_key)", "models)", "logs)", "stdout_log)", "stderr_log)", "pid_file)", "test_exe)", "test_stdout_log)", "test_stderr_log)", "test_pid_file)", "test_start_sh)", "test_start_command)", "auto_update_stdout_log)", "auto_update_stderr_log)", "auto_update_schedule)", "launch_agent_plist)")) {
  Assert-Contains $pathsBody $token "paths_for is missing '$token'"
}
foreach ($token in @("cli-proxy-api.stdout.log", "cli-proxy-api.stderr.log", "cli-proxy-api.pid", "cli-proxy-api-test", "cli-proxy-api-test.stdout.log", "cli-proxy-api-test.stderr.log", "cli-proxy-api-test.pid", "start-cliproxyapi-test.sh", "start-cliproxyapi-test.command", "auto-update.stdout.log", "auto-update.stderr.log", "auto-update-schedule.txt", "local.cliproxyapi.manager.autoupdate.plist")) {
  Assert-Contains $pathsBody $token "paths_for is missing path token '$token'"
}
Assert-Contains $pathsBody "webui-management-key.txt" "paths_for is missing saved plaintext WebUI key path"

$layoutBody = Get-Section "ensure_install_layout()" "architecture_regex()"
Assert-Contains $layoutBody '$(paths_for "$install_dir" logs)' "ensure_install_layout should create logs directory"

$startBody = Get-Section "start_clip_proxy_api()" "health_check()"
Assert-Contains $startBody 'nohup "$exe" -config "$config" >"$stdout_log" 2>"$stderr_log" &' "start should use nohup with stdout/stderr logs"
Assert-Contains $startBody 'echo $! > "$pid_file"' "start should write pid file"
foreach ($token in @('variant=${2:-stable}', '[ ! -x "$exe" ]', 'other_variant=', 'other_state_line=$(managed_process_state "$install_dir" "$other_variant")', 'cli-proxy-api-test', 'config.yaml')) {
  Assert-Contains $startBody $token "start should enforce stable/test mutual exclusion using '$token'"
}
if ($startBody -match '\bopen\b') {
  throw "start_clip_proxy_api should not use open/Terminal for lifecycle start"
}

foreach ($functionName in @("runtime_path", "runtime_label", "managed_process_state", "service_status_text", "stop_clip_proxy_api")) {
  Assert-Match $text "(?m)^$functionName\(\) \{" "Missing function: $functionName"
}
foreach ($functionName in @("validate_schedule_time", "schedule_input_to_daily_cron", "read_schedule_expression_or_default", "show_scheduled_update_status", "enable_scheduled_update", "disable_scheduled_update", "clear_update_cache", "old_managed_backups", "prune_old_managed_backups")) {
  Assert-Match $text "(?m)^$functionName\(\) \{" "Missing scheduled update helper function: $functionName"
}
foreach ($functionName in @("is_bcrypt_hash", "webui_plain_management_key")) {
  Assert-Match $text "(?m)^$functionName\(\) \{" "Missing WebUI key helper function: $functionName"
}
foreach ($functionName in @("validate_model_catalog", "ensure_model_catalog", "sync_model_catalog", "show_client_config", "show_workbuddy_models_json", "normalize_model_id_list", "json_escape", "show_model_choices", "resolve_model_id_selection", "is_image_generation_only_model", "model_info_json_for_id", "print_workbuddy_model_json")) {
  Assert-Match $text "(?m)^$functionName\(\) \{" "Missing WorkBuddy models.json helper function: $functionName"
}

foreach ($token in @("MENU_RIGHT_COLUMN=", "PANEL_VALUE_COLUMN=", "print_panel_value_column()")) {
  Assert-Contains $text $token "macOS console menu alignment should define fixed column token '$token'"
}

$panelValueColumnBody = Get-Section "print_panel_value_column()" "print_panel_row()"
Assert-Contains $panelValueColumnBody '\033[%sG' "print_panel_value_column should move to a fixed terminal column"

$panelRowBody = Get-Section "print_panel_row()" "show_help()"
foreach ($token in @("print_panel_value_column")) {
  Assert-Contains $panelRowBody $token "print_panel_row should align values using fixed terminal columns with '$token'"
}
foreach ($forbiddenPattern in @('%-18s', '%-34s')) {
  if ($panelRowBody.Contains($forbiddenPattern)) {
    throw "print_panel_row must not use character padding for Chinese labels: $forbiddenPattern"
  }
}

$menuPairBody = Get-Section "print_menu_pair()" "print_panel_section()"
foreach ($token in @("MENU_RIGHT_COLUMN", '\033[%sG')) {
  Assert-Contains $menuPairBody $token "print_menu_pair should align the right item using fixed terminal columns with '$token'"
}
foreach ($forbiddenPattern in @('%-18s', '%-34s')) {
  if ($menuPairBody.Contains($forbiddenPattern)) {
    throw "print_menu_pair must not use character padding for Chinese labels: $forbiddenPattern"
  }
}

$installBody = Get-Section "install_or_update()" "generate_uuid_key()"
foreach ($token in @(
  'service_status=$(service_status_text "$install_dir")',
  'was_running=0',
  'stop_clip_proxy_api "$install_dir"',
  'start_clip_proxy_api "$install_dir"',
  'backup_file_name',
  'last_release_tag=$(read_state_value "lastReleaseTag" || true)',
  'unknown-version',
  'sync_model_catalog "$install_dir"',
  'clear_update_cache "$install_dir"',
  'prune_old_managed_backups "$install_dir"'
)) {
  Assert-Contains $installBody $token "install_or_update should manage running upgrades and versioned backups using '$token'"
}
$managedBody = Get-Section "managed_process_state()" "service_status_text()"
foreach ($token in @(
  'variant=${2:-stable}',
  'exe=$(runtime_path "$install_dir" "$variant" exe)',
  'config=$(runtime_path "$install_dir" "$variant" config)',
  'pid_file=$(runtime_path "$install_dir" "$variant" pid_file)',
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
foreach ($token in @("service_status_label", "runtime_path", "variant", "pid_file", "stdout_log", "stderr_log", "webui_key_status_text", $webUiKeyLabel)) {
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
Assert-Contains $runActionBody 'test-start) start_clip_proxy_api "$install_dir" test ;;' "run_action should dispatch test-start"
Assert-Contains $runActionBody 'test-stop) stop_clip_proxy_api "$install_dir" test ;;' "run_action should dispatch test-stop"
Assert-Contains $runActionBody 'test-status) show_status "$install_dir" test ;;' "run_action should dispatch test-status"
Assert-Contains $runActionBody 'webui-info) show_webui_info "$install_dir" ;;' "run_action should dispatch webui-info"
Assert-Contains $runActionBody "workbuddy-json)" "run_action should retain the workbuddy-json compatibility alias"
Assert-Contains $runActionBody 'client-config) show_client_config "$install_dir" ;;' "run_action should dispatch client-config"
Assert-Contains $runActionBody 'warn "workbuddy-json' "run_action should warn for deprecated workbuddy-json"
Assert-Contains $runActionBody 'schedule-status) show_scheduled_update_status "$install_dir" ;;' "run_action should dispatch schedule-status"
Assert-Contains $runActionBody 'schedule-enable) enable_scheduled_update "$install_dir" ;;' "run_action should dispatch schedule-enable"
Assert-Contains $runActionBody 'schedule-disable) disable_scheduled_update "$install_dir" ;;' "run_action should dispatch schedule-disable"
Assert-Contains $runActionBody 'cleanup)' "run_action should dispatch cleanup"
Assert-Contains $runActionBody 'clear_update_cache "$install_dir"' "run_action cleanup should clear downloads"
Assert-Contains $runActionBody 'prune_old_managed_backups "$install_dir"' "run_action cleanup should prune old backups"

$validateScheduleBody = Get-Section "validate_schedule_time()" "schedule_input_to_daily_cron()"
foreach ($token in @('^[0-9][0-9]:[0-9][0-9]$', 'hour=${schedule_time%:*}', 'minute=${schedule_time#*:}', '[ "$hour" -gt 23 ]', '[ "$minute" -gt 59 ]')) {
  Assert-Contains $validateScheduleBody $token "validate_schedule_time should validate HH:mm with '$token'"
}

$scheduleParserBody = Get-Section "schedule_input_to_daily_cron()" "read_schedule_expression_or_default()"
$dailyCronOnlyText = (Text-FromCodepoints @(0x5F53, 0x524D, 0x53EA, 0x652F, 0x6301, 0x6BCF, 0x65E5, 0x56FA, 0x5B9A, 0x65F6, 0x95F4)) + " cron"
foreach ($token in @('0 4 * * *', 'cron_expression', $dailyCronOnlyText, 'HH:mm', 'set -f', '"$3" != "*"')) {
  Assert-Contains $scheduleParserBody $token "schedule_input_to_daily_cron should support daily cron input with '$token'"
}

$scheduleStatusBody = Get-Section "show_scheduled_update_status()" "enable_scheduled_update()"
foreach ($token in @("local.cliproxyapi.manager.autoupdate", "launch_agent_plist", "auto_update_stdout_log", "auto_update_stderr_log", "auto_update_schedule", "cron", $menuAutoUpdate)) {
  Assert-Contains $scheduleStatusBody $token "show_scheduled_update_status should report LaunchAgent state with '$token'"
}

$scheduleEnableBody = Get-Section "enable_scheduled_update()" "disable_scheduled_update()"
foreach ($token in @("launchctl unload", "launchctl load", "StartCalendarInterval", "Hour", "Minute", "--install", "--install-dir", "StandardOutPath", "StandardErrorPath", "local.cliproxyapi.manager.autoupdate", "cron_expression", "auto_update_schedule")) {
  Assert-Contains $scheduleEnableBody $token "enable_scheduled_update should write a daily LaunchAgent with '$token'"
}

$scheduleDisableBody = Get-Section "disable_scheduled_update()" "show_model_choices()"
foreach ($token in @("launchctl unload", "rm -f", "launch_agent_plist", "local.cliproxyapi.manager.autoupdate")) {
  Assert-Contains $scheduleDisableBody $token "disable_scheduled_update should remove the LaunchAgent with '$token'"
}

foreach ($banned in @("pkill", "killall", "kill -9")) {
  if ($text.Contains($banned)) {
    throw "macOS manager must not use banned process termination command: $banned"
  }
}

$menuBody = Get-Section "show_menu()" 'ACTION="menu"'
foreach ($token in @("short_install_path", "webui_key_status_text", $menuInstallConfig, $menuServiceRuntime, "WebUI", $menuLogin, $menuIntegrationChecks, $menuAutoUpdate, $menuSettings)) {
  Assert-Contains $menuBody $token "menu is missing '$token'"
}
foreach ($number in 1..17) {
  Assert-Match $menuBody "(?m)\s$number\)" "menu should map option $number"
}
foreach ($pattern in @("D|d)", "Q|q|0)")) {
  Assert-Contains $menuBody $pattern "menu should map '$pattern'"
}

$writeStartScriptsBody = Get-Section "write_start_scripts()" "install_or_update()"
foreach ($token in @('variant=${2:-stable}', 'runtime_path', 'exe_name=$(basename "$exe")', 'start_sh_name=$(basename "$start_sh")')) {
  Assert-Contains $writeStartScriptsBody $token "write_start_scripts should generate variant-specific launcher using '$token'"
}
foreach ($pattern in @("T1|t1)", "T2|t2)", "T3|t3)")) {
  Assert-Contains $menuBody $pattern "menu should map test runtime choice '$pattern'"
}
Assert-Contains $menuBody 'if ! IFS= read -r choice; then' "menu should return cleanly when stdin reaches EOF"
Assert-Contains $menuBody 'return 0' "menu should return on EOF instead of looping"

$workBuddyJsonBody = Get-Section "show_workbuddy_models_json()" "run_action()"
foreach ($token in @('"models"', '/v1/chat/completions', 'gpt-image-*', 'model_info_json_for_id', 'print_workbuddy_model_json')) {
  Assert-Contains $workBuddyJsonBody $token "show_workbuddy_models_json should output WorkBuddy models.json token '$token'"
}
foreach ($token in @('CLIProxyAPI', '"supportsToolCall"', '"supportsImages"', 'MODEL_CATALOG_PATH', 'MODEL_INCLUDE_TOKEN_LIMITS', '"supportsReasoning"', '"reasoning"', 'supported_parameters', 'supportedInputModalities', 'context_length', 'inputTokenLimit', 'max_completion_tokens', 'outputTokenLimit', '"xhigh"')) {
  Assert-Contains $text $token "WorkBuddy models.json generation should support metadata token '$token'"
}
foreach ($token in @('"none"', "'none'")) {
  if ($text.Contains($token)) {
    throw "WorkBuddy models.json generation should not include none in WorkBuddy supportedEfforts"
  }
}
foreach ($token in @('--test-start', '--test-stop', '--test-status', 'cli-proxy-api-test', '--client-config', '--format', '--vendor', '--workbuddy-json', '--schedule-status', '--schedule-enable', '--schedule-disable', '--cleanup', '--model-ids', '--image-model-ids', '--include-token-limits')) {
  Assert-Contains $text $token "help/argument parsing should include $token"
}

Write-Output "MACOS_LIFECYCLE_STATIC_OK"
