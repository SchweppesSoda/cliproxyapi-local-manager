$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$text = Get-Content -LiteralPath $ScriptPath -Raw -Encoding UTF8

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref] $tokens, [ref] $parseErrors)
if ($parseErrors.Count -gt 0) {
  throw "manage-cliproxyapi.ps1 should parse without errors: $($parseErrors[0].Message)"
}

function New-StringFromCodePoints {
  param([int[]] $CodePoints)

  return -join ($CodePoints | ForEach-Object { [char] $_ })
}

$functions = @{}
$ast.FindAll({
  param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
}, $true) | ForEach-Object {
  $functions[$_.Name] = $_.Extent.Text
}

function Assert-Contains {
  param(
    [string] $Haystack,
    [string] $Needle,
    [string] $Message
  )

  if ($Haystack -notmatch [regex]::Escape($Needle)) {
    throw $Message
  }
}

foreach ($requiredFunction in @("Get-ManagedProcess", "Get-ServiceState", "Stop-CLIProxyAPI", "Test-BcryptHash", "Get-WebUIManagementKeyInfo")) {
  if (-not $functions.ContainsKey($requiredFunction)) {
    throw "Missing lifecycle function: $requiredFunction"
  }
}

$pathsBody = $functions["Get-Paths"]
Assert-Contains -Haystack $pathsBody -Needle "webui-management-key.txt" -Message "Get-Paths should expose the saved plaintext WebUI key file"

$configInfoBody = $functions["Get-ConfigInfo"]
foreach ($required in @('$inRemoteManagement', 'remote-management', 'secret-key', 'allow-remote')) {
  Assert-Contains -Haystack $configInfoBody -Needle $required -Message "Get-ConfigInfo should scope WebUI management settings to remote-management using $required"
}

$webuiKeyBody = $functions["Get-WebUIManagementKeyInfo"]
foreach ($required in @("WebUIKey", "Test-BcryptHash", "PlainKey", "ConfigSecretIsBcrypt")) {
  Assert-Contains -Haystack $webuiKeyBody -Needle $required -Message "Get-WebUIManagementKeyInfo should handle saved plaintext keys and bcrypt config secrets using $required"
}

foreach ($requiredFunction in @("ConvertTo-ProcessArgument", "Split-WindowsCommandLine", "Test-CommandLineConfigArgument")) {
  if (-not $functions.ContainsKey($requiredFunction)) {
    throw "Missing lifecycle helper function: $requiredFunction"
  }
}

Invoke-Expression @"
$($functions["ConvertTo-ProcessArgument"])
$($functions["Split-WindowsCommandLine"])
$($functions["Test-CommandLineConfigArgument"])
"@

$configWithSpaces = "C:\Users\Test User\AppData\Local\Programs\CLIProxyAPI\config.yaml"
$quotedConfigWithSpaces = ConvertTo-ProcessArgument $configWithSpaces
if ($quotedConfigWithSpaces -ne "`"$configWithSpaces`"") {
  throw "ConvertTo-ProcessArgument should quote config paths with spaces. Actual: $quotedConfigWithSpaces"
}

$exeWithSpaces = "C:\Users\Test User\AppData\Local\Programs\CLIProxyAPI\cli-proxy-api.exe"
$quotedCommandLine = "`"$exeWithSpaces`" -config `"$configWithSpaces`""
if (-not (Test-CommandLineConfigArgument -CommandLine $quotedCommandLine -ExpectedConfig $configWithSpaces)) {
  throw "Test-CommandLineConfigArgument should accept an exact quoted -config argument"
}

$backupConfigCommandLine = "`"$exeWithSpaces`" -config `"$configWithSpaces.bak`""
if (Test-CommandLineConfigArgument -CommandLine $backupConfigCommandLine -ExpectedConfig $configWithSpaces) {
  throw "Test-CommandLineConfigArgument must reject config.yaml.bak false positives"
}

$embeddedConfigCommandLine = "`"$exeWithSpaces`" -other `"-config $configWithSpaces`""
if (Test-CommandLineConfigArgument -CommandLine $embeddedConfigCommandLine -ExpectedConfig $configWithSpaces) {
  throw "Test-CommandLineConfigArgument must require a real -config argument boundary"
}

foreach ($forbiddenPattern in @(
  'Stop-Process\s+-Name\b',
  'taskkill(?:\.exe)?\s+.*(?:/IM|\-im)\b'
)) {
  if ($text -match $forbiddenPattern) {
    throw "Windows lifecycle must not use broad process termination: $forbiddenPattern"
  }
}

$managedBody = $functions["Get-ManagedProcess"]
foreach ($required in @("PidFile", "ExecutablePath", "CommandLine", "Get-CimInstance")) {
  Assert-Contains -Haystack $managedBody -Needle $required -Message "Get-ManagedProcess should validate managed process identity using $required"
}
foreach ($required in @("Test-CommandLineConfigArgument")) {
  Assert-Contains -Haystack $managedBody -Needle $required -Message "Get-ManagedProcess should validate actual -config argument boundaries using $required"
}
if ($managedBody -match '\.IndexOf\(\$expectedConfig') {
  throw "Get-ManagedProcess must not use raw substring matching for the config path"
}

$configArgumentBody = $functions["Test-CommandLineConfigArgument"]
foreach ($required in @("Split-WindowsCommandLine", "-config", "OrdinalIgnoreCase")) {
  Assert-Contains -Haystack $configArgumentBody -Needle $required -Message "Test-CommandLineConfigArgument should validate actual -config argument boundaries using $required"
}

$stateBody = $functions["Get-ServiceState"]
foreach ($required in @("Get-ManagedProcess", "IsRunning", "Pid")) {
  Assert-Contains -Haystack $stateBody -Needle $required -Message "Get-ServiceState should expose $required"
}

$stopBody = $functions["Stop-CLIProxyAPI"]
foreach ($required in @("Get-ManagedProcess", "Stop-Process", "-Id", "PidFile")) {
  Assert-Contains -Haystack $stopBody -Needle $required -Message "Stop-CLIProxyAPI should stop only a verified managed process using $required"
}

$startBody = $functions["Start-CLIProxyAPI"]
foreach ($required in @(
  "Get-ServiceState",
  "IsRunning",
  (New-StringFromCodePoints @(0x5DF2, 0x5728, 0x8FD0, 0x884C)),
  "Start-Process",
  "ConvertTo-ProcessArgument"
)) {
  Assert-Contains -Haystack $startBody -Needle $required -Message "Start-CLIProxyAPI should be idempotent and include $required"
}

$statusBody = $functions["Show-Status"]
foreach ($required in @(
  "Get-ServiceState",
  (New-StringFromCodePoints @(0x670D, 0x52A1)),
  ("WebUI " + (New-StringFromCodePoints @(0x5BC6, 0x94A5))),
  (New-StringFromCodePoints @(0x5DF2, 0x914D, 0x7F6E)),
  (New-StringFromCodePoints @(0x672A, 0x914D, 0x7F6E))
)) {
  Assert-Contains -Haystack $statusBody -Needle $required -Message "Show-Status should include $required"
}
if ($statusBody -match 'Write-Host\s+\$info\.ManagementKey') {
  throw "Show-Status must not print the full WebUI management key"
}
if ($statusBody -match 'WebUI 管理密钥:.*ManagementKey') {
  throw "Show-Status must report configured/unconfigured instead of the full management key"
}

$actionBody = $functions["Invoke-Action"]
foreach ($required in @('"stop"', "Stop-CLIProxyAPI", '"webui-info"', "Show-WebUIInfo")) {
  Assert-Contains -Haystack $actionBody -Needle $required -Message "Invoke-Action should route $required"
}

$menuBody = $functions["Show-Menu"]
foreach ($required in @(
  (New-StringFromCodePoints @(0x77ED, 0x8DEF, 0x5F84)),
  (New-StringFromCodePoints @(0x672C, 0x673A, 0x72B6, 0x6001)),
  (New-StringFromCodePoints @(0x5B89, 0x88C5, 0x914D, 0x7F6E)),
  (New-StringFromCodePoints @(0x670D, 0x52A1, 0x8FD0, 0x884C)),
  "WebUI",
  (New-StringFromCodePoints @(0x767B, 0x5F55)),
  (New-StringFromCodePoints @(0x68C0, 0x67E5, 0x96C6, 0x6210)),
  (New-StringFromCodePoints @(0x8BBE, 0x7F6E))
)) {
  Assert-Contains -Haystack $menuBody -Needle $required -Message "Show-Menu should include menu header/section text: $required"
}
foreach ($choice in @("1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "D", "d", "Q", "q", "0")) {
  Assert-Contains -Haystack $menuBody -Needle "`"$choice`"" -Message "Show-Menu should map choice $choice"
}

foreach ($requiredHelp in @("stop", "webui-info")) {
  Assert-Contains -Haystack $text -Needle $requiredHelp -Message "Help/action text should include $requiredHelp"
}

Write-Output "WINDOWS_LIFECYCLE_STATIC_OK"
