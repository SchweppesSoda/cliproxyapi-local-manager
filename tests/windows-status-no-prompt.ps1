$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$LegacyStatePath = Join-Path $RepoRoot ".cliproxyapi-manager-state.windows.json"
$LegacyStateBackupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-manager-state.windows.{0}.json" -f ([Guid]::NewGuid().ToString("N")))
$HadLegacyState = Test-Path -LiteralPath $LegacyStatePath
$InstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-status-install-{0}" -f ([Guid]::NewGuid().ToString("N")))
$ExplicitInstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-status-explicit-install-{0}" -f ([Guid]::NewGuid().ToString("N")))
$InstallStatePath = Join-Path $InstallDir ".cliproxyapi-manager-state.windows.json"
$ExplicitInstallStatePath = Join-Path $ExplicitInstallDir ".cliproxyapi-manager-state.windows.json"

function New-StringFromCodePoints {
  param([int[]] $CodePoints)

  return -join ($CodePoints | ForEach-Object { [char] $_ })
}

function Get-DefaultInstallDir {
  $defaultInstallBase = $env:LOCALAPPDATA
  if ([string]::IsNullOrWhiteSpace($defaultInstallBase)) {
    $defaultInstallBase = Join-Path $env:USERPROFILE "AppData\Local"
  }
  return (Join-Path $defaultInstallBase "Programs\CLIProxyAPI")
}

function Invoke-Manager {
  param(
    [string[]] $ManagerArguments,
    [int] $TimeoutSeconds = 10
  )

  $argumentsJson = ConvertTo-Json -Compress -InputObject @($ManagerArguments)
  $job = Start-Job -ScriptBlock {
    param(
      [string] $ManagerScriptPath,
      [string] $ArgumentsJson
    )

    $ErrorActionPreference = "Stop"
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    $OutputEncoding = [System.Text.Encoding]::UTF8

    $childArguments = @($ArgumentsJson | ConvertFrom-Json)
    $ErrorActionPreference = "Continue"
    $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ManagerScriptPath @childArguments 2>&1
    $managerExitCode = $LASTEXITCODE
    $ErrorActionPreference = "Stop"
    [pscustomobject]@{
      ExitCode = $managerExitCode
      Text = ($output -join "`n")
    }
  } -ArgumentList $ScriptPath, $argumentsJson

  if (-not (Wait-Job -Job $job -Timeout $TimeoutSeconds)) {
    Stop-Job -Job $job
    Remove-Job -Job $job -Force
    throw "manager command timed out; status may be prompting for input. Args: $($ManagerArguments -join ' ')"
  }

  try {
    return (Receive-Job -Job $job)
  } finally {
    Remove-Job -Job $job -Force
  }
}

function Assert-NoInstallDirPrompt {
  param([string] $Text)

  $promptFragments = @(
    (New-StringFromCodePoints @(0x4E0A, 0x6B21, 0x5B89, 0x88C5, 0x76EE, 0x5F55)),
    (New-StringFromCodePoints @(0x8BF7, 0x9009, 0x62E9)),
    (New-StringFromCodePoints @(0x56DE, 0x8F66, 0x4F7F, 0x7528))
  )

  foreach ($fragment in $promptFragments) {
    if ($Text.Contains($fragment)) {
      throw "status should not prompt for install directory when state exists. Output:`n$Text"
    }
  }
}

try {
  if ($HadLegacyState) {
    Move-Item -LiteralPath $LegacyStatePath -Destination $LegacyStateBackupPath -Force
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
  Set-Content -LiteralPath (Join-Path $InstallDir "cli-proxy-api-test.exe") -Encoding ASCII -Value "placeholder"
  [ordered]@{
    installDir = $InstallDir
    lastReleaseTag = "test"
    updatedAt = (Get-Date).ToString("o")
  } | ConvertTo-Json | Set-Content -LiteralPath $LegacyStatePath -Encoding UTF8

  $result = Invoke-Manager -ManagerArguments @("-Action", "status")
  $text = $result.Text

  if ($result.ExitCode -ne 0) {
    throw "status should exit successfully when state exists. Exit code: $($result.ExitCode). Output:`n$text"
  }
  Assert-NoInstallDirPrompt -Text $text
  if ($text -match [regex]::Escape((Get-DefaultInstallDir))) {
    throw "status should not print default install dir while prompting. Output:`n$text"
  }
  if ($text -notmatch [regex]::Escape($InstallDir)) {
    throw "status should use saved install dir. Output:`n$text"
  }
  if ($text -match "mgmt-local-test") {
    throw "status must not print full WebUI management key. Output:`n$text"
  }
  if (-not (Test-Path -LiteralPath $InstallStatePath)) {
    throw "status should migrate legacy repo state into install dir state: $InstallStatePath"
  }

  $testStatusResult = Invoke-Manager -ManagerArguments @("-Action", "test-status", "-InstallDir", $InstallDir)
  if ($testStatusResult.ExitCode -ne 0) {
    throw "test-status should exit successfully. Exit code: $($testStatusResult.ExitCode). Output:`n$($testStatusResult.Text)"
  }
  Assert-NoInstallDirPrompt -Text $testStatusResult.Text
  foreach ($expectedTestPath in @("cli-proxy-api-test.exe", "cli-proxy-api-test.pid", "cli-proxy-api-test.stdout.log", "cli-proxy-api-test.stderr.log")) {
    if ($testStatusResult.Text -notmatch [regex]::Escape($expectedTestPath)) {
      throw "test-status should show $expectedTestPath. Output:`n$($testStatusResult.Text)"
    }
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

  $explicitResult = Invoke-Manager -ManagerArguments @("-Action", "status", "-InstallDir", $ExplicitInstallDir)
  $explicitText = $explicitResult.Text

  if ($explicitResult.ExitCode -ne 0) {
    throw "status should accept explicit -InstallDir. Exit code: $($explicitResult.ExitCode). Output:`n$explicitText"
  }
  if ($explicitText -notmatch [regex]::Escape($ExplicitInstallDir)) {
    throw "status should use explicit install dir. Output:`n$explicitText"
  }
  if ($explicitText -match "mgmt-explicit-test") {
    throw "status with explicit install dir must not print full WebUI management key. Output:`n$explicitText"
  }

  $missingTestStart = Invoke-Manager -ManagerArguments @("-Action", "test-start", "-InstallDir", $ExplicitInstallDir)
  if ($missingTestStart.ExitCode -eq 0 -or $missingTestStart.Text -notmatch [regex]::Escape("cli-proxy-api-test.exe")) {
    throw "test-start should reject a missing test core. Output:`n$($missingTestStart.Text)"
  }

  if (Test-Path -LiteralPath $LegacyStatePath) {
    throw "explicit -InstallDir should not write manager state to repo root: $LegacyStatePath"
  }
  if (-not (Test-Path -LiteralPath $ExplicitInstallStatePath)) {
    throw "explicit -InstallDir should save manager state inside install dir: $ExplicitInstallStatePath"
  }
  $state = Get-Content -LiteralPath $ExplicitInstallStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
  $expectedExplicitInstallDir = [System.IO.Path]::GetFullPath($ExplicitInstallDir)
  if (-not [string]::Equals($state.installDir, $expectedExplicitInstallDir, [StringComparison]::OrdinalIgnoreCase)) {
    throw "explicit -InstallDir should be saved to state. Expected: $expectedExplicitInstallDir. Actual: $($state.installDir)"
  }
} finally {
  if (Test-Path -LiteralPath $LegacyStatePath) {
    Remove-Item -LiteralPath $LegacyStatePath -Force
  }
  if ($HadLegacyState -and (Test-Path -LiteralPath $LegacyStateBackupPath)) {
    Move-Item -LiteralPath $LegacyStateBackupPath -Destination $LegacyStatePath -Force
  }
  if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
  }
  if (Test-Path -LiteralPath $ExplicitInstallDir) {
    Remove-Item -LiteralPath $ExplicitInstallDir -Recurse -Force
  }
}

Write-Output "WINDOWS_STATUS_NO_PROMPT_OK"
