$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$Manager = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$InstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-test-runtime-{0}" -f ([Guid]::NewGuid().ToString("N")))
$TestPidPath = Join-Path $InstallDir "cli-proxy-api-test.pid"
$TestStartManager = $null

function Invoke-ManagerAction {
  param([string] $Action)

  $previousPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Manager -Action $Action -InstallDir $InstallDir 2>&1
    return [pscustomobject]@{
      ExitCode = $LASTEXITCODE
      Text = ($output -join "`n")
    }
  } finally {
    $ErrorActionPreference = $previousPreference
  }
}

try {
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Set-Content -LiteralPath (Join-Path $InstallDir "config.yaml") -Encoding UTF8 -Value @"
host: "127.0.0.1"
port: 58317

api-keys:
  - "wb-local-test"

remote-management:
  allow-remote: false
  secret-key: "mgmt-local-test"
"@

  $testCorePath = Join-Path $InstallDir "cli-proxy-api-test.exe"
  $stableCorePath = Join-Path $InstallDir "cli-proxy-api.exe"
  Add-Type -TypeDefinition @"
using System;
using System.Threading;
public static class TestCoreProgram {
    public static void Main(string[] args) {
        Thread.Sleep(TimeSpan.FromMinutes(2));
    }
}
"@ -Language CSharp -OutputAssembly $testCorePath -OutputType ConsoleApplication
  Copy-Item -LiteralPath $testCorePath -Destination $stableCorePath -Force

  $managerStdout = Join-Path $InstallDir "test-start-manager.stdout.log"
  $managerStderr = Join-Path $InstallDir "test-start-manager.stderr.log"
  $TestStartManager = Start-Process -FilePath "powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Manager, "-Action", "test-start", "-InstallDir", $InstallDir) `
    -RedirectStandardOutput $managerStdout `
    -RedirectStandardError $managerStderr `
    -WindowStyle Hidden `
    -PassThru
  $deadline = (Get-Date).AddSeconds(10)
  while (-not (Test-Path -LiteralPath $TestPidPath) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 100
  }
  if (-not (Test-Path -LiteralPath $TestPidPath)) {
    $startOutput = if (Test-Path -LiteralPath $managerStdout) { Get-Content -LiteralPath $managerStdout -Raw -Encoding UTF8 } else { "" }
    $startError = if (Test-Path -LiteralPath $managerStderr) { Get-Content -LiteralPath $managerStderr -Raw -Encoding UTF8 } else { "" }
    throw "test-start should write cli-proxy-api-test.pid. Output:`n$startOutput`n$startError"
  }
  $testPid = [int](Get-Content -LiteralPath $TestPidPath -Raw -Encoding ASCII).Trim()
  Start-Sleep -Milliseconds 300
  if (-not (Get-Process -Id $testPid -ErrorAction SilentlyContinue)) {
    throw "test-start process exited unexpectedly"
  }

  foreach ($expectedPath in @(
    "logs\cli-proxy-api-test.stdout.log",
    "logs\cli-proxy-api-test.stderr.log",
    "start-cliproxyapi-test.ps1",
    "start-cliproxyapi-test.cmd"
  )) {
    if (-not (Test-Path -LiteralPath (Join-Path $InstallDir $expectedPath))) {
      throw "test-start should create $expectedPath"
    }
  }
  $testLauncher = Get-Content -LiteralPath (Join-Path $InstallDir "start-cliproxyapi-test.ps1") -Raw -Encoding UTF8
  if ($testLauncher -notmatch [regex]::Escape("cli-proxy-api-test.exe")) {
    throw "test launcher should run cli-proxy-api-test.exe"
  }

  $stableStart = Invoke-ManagerAction -Action "start"
  if ($stableStart.ExitCode -eq 0) {
    throw "stable start should fail while the managed test core is running"
  }
  if (-not (Get-Process -Id $testPid -ErrorAction SilentlyContinue)) {
    throw "stable start must not stop the running test core"
  }
  if (Test-Path -LiteralPath (Join-Path $InstallDir "cli-proxy-api.pid")) {
    throw "stable start must not write a stable PID while the test core is running"
  }

  $testStatus = Invoke-ManagerAction -Action "test-status"
  if ($testStatus.ExitCode -ne 0 -or $testStatus.Text -notmatch [regex]::Escape("cli-proxy-api-test.pid")) {
    throw "test-status should report the test runtime. Output:`n$($testStatus.Text)"
  }

  $testStop = Invoke-ManagerAction -Action "test-stop"
  if ($testStop.ExitCode -ne 0) {
    throw "test-stop failed. Output:`n$($testStop.Text)"
  }
  if (Get-Process -Id $testPid -ErrorAction SilentlyContinue) {
    throw "test-stop should terminate the managed test core"
  }
  if (Test-Path -LiteralPath $TestPidPath) {
    throw "test-stop should remove cli-proxy-api-test.pid"
  }
  if ($TestStartManager -and -not $TestStartManager.HasExited) {
    [void]$TestStartManager.WaitForExit(5000)
  }
} finally {
  if (Test-Path -LiteralPath $TestPidPath) {
    $remainingPid = 0
    [void][int]::TryParse((Get-Content -LiteralPath $TestPidPath -Raw -Encoding ASCII).Trim(), [ref]$remainingPid)
    if ($remainingPid -gt 0) {
      Stop-Process -Id $remainingPid -Force -ErrorAction SilentlyContinue
    }
  }
  if ($TestStartManager -and -not $TestStartManager.HasExited) {
    Stop-Process -Id $TestStartManager.Id -Force -ErrorAction SilentlyContinue
  }
  $resolvedInstallDir = [System.IO.Path]::GetFullPath($InstallDir)
  $resolvedTempDir = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  if ((Test-Path -LiteralPath $resolvedInstallDir) -and $resolvedInstallDir.StartsWith($resolvedTempDir, [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $resolvedInstallDir -Recurse -Force
  }
}

Write-Output "WINDOWS_TEST_RUNTIME_OK"
