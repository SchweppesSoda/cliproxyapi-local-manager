$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$InstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-manager-client-config-" + [Guid]::NewGuid().ToString("N"))

function Invoke-Manager {
  param([string[]] $Arguments)

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = "powershell.exe"
  $quoted = foreach ($argument in @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $Arguments) {
    if ($argument -match '[\s"]') { '"' + ($argument -replace '"', '\"') + '"' } else { $argument }
  }
  $psi.Arguments = $quoted -join " "
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $process = [System.Diagnostics.Process]::Start($psi)
  if (-not $process.WaitForExit(15000)) {
    $process.Kill()
    throw "Manager process timed out"
  }
  return [pscustomobject]@{
    ExitCode = $process.ExitCode
    Stdout = $process.StandardOutput.ReadToEnd()
    Stderr = $process.StandardError.ReadToEnd()
  }
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
try {
  @'
host: "127.0.0.1"
port: 8317

api-keys:
  - "wb-local-test-key"

remote-management:
  allow-remote: false
  secret-key: "mgmt-local-test-key"
'@ | Set-Content -LiteralPath (Join-Path $InstallDir "config.yaml") -Encoding UTF8

  @'
{
  "codex-plus": [
    {
      "id": "tool-model",
      "display_name": "Tool Model",
      "context_length": 1000,
      "max_completion_tokens": 200,
      "supported_parameters": ["tools"],
      "thinking": { "levels": ["low", "medium", "none"] }
    },
    { "id": "gpt-image-2", "type": "openai" }
  ],
  "gemini": [
    {
      "id": "vision-model",
      "inputTokenLimit": 3000,
      "outputTokenLimit": 400,
      "supportedInputModalities": ["TEXT", "IMAGE"],
      "thinking": { "min": 1, "max": 100 }
    },
    { "id": "conflict-model", "context_length": 100 }
  ],
  "vertex": [
    { "id": "conflict-model", "context_length": 200 }
  ]
}
'@ | Set-Content -LiteralPath (Join-Path $InstallDir "models.json") -Encoding UTF8

  $result = Invoke-Manager @(
    "-Action", "client-config",
    "-InstallDir", $InstallDir,
    "-Format", "workbuddy",
    "-Vendor", "My Local Provider",
    "-ModelIds", "tool-model,vision-model,conflict-model,gpt-image-2,unknown-model",
    "-IncludeTokenLimits"
  )
  if ($result.ExitCode -ne 0) {
    throw "client-config failed. Stdout:`n$($result.Stdout)`nStderr:`n$($result.Stderr)"
  }
  if (-not $result.Stdout.TrimStart().StartsWith("{")) {
    throw "stdout must contain JSON only. Actual:`n$($result.Stdout)"
  }
  $legacy = Invoke-Manager @(
    "-Action", "workbuddy-json",
    "-InstallDir", $InstallDir,
    "-Vendor", "My Local Provider",
    "-ModelIds", "tool-model,vision-model,conflict-model,gpt-image-2,unknown-model",
    "-IncludeTokenLimits"
  )
  if ($legacy.ExitCode -ne 0 -or $legacy.Stdout -ne $result.Stdout) {
    throw "Deprecated workbuddy-json must forward to equivalent client-config stdout"
  }
  if ($legacy.Stderr -notmatch "workbuddy-json" -or $legacy.Stderr -notmatch "client-config") {
    throw "Deprecated alias warning must be written to stderr"
  }
  $json = $result.Stdout | ConvertFrom-Json
  if ($json.models.Count -ne 4) {
    throw "Expected four chat models after excluding gpt-image-2. Actual: $($json.models.Count)"
  }

  $tool = $json.models | Where-Object id -eq "tool-model"
  if ($tool.name -ne "Tool Model" -or $tool.vendor -ne "My Local Provider") {
    throw "Catalog display name and custom vendor should be mapped"
  }
  if ($tool.supportsToolCall -ne $true -or $tool.supportsReasoning -ne $true) {
    throw "Tool and reasoning capabilities should come from the catalog. JSON:`n$($result.Stdout)"
  }
  if (($tool.reasoning.supportedEfforts -join ",") -ne "low,medium") {
    throw "WorkBuddy efforts should be filtered to documented values"
  }
  if ($null -ne $tool.reasoning.PSObject.Properties["defaultEffort"]) {
    throw "Phase one must omit reasoning.defaultEffort"
  }
  if ($tool.maxInputTokens -ne 1000 -or $tool.maxOutputTokens -ne 200) {
    throw "Token aliases should map when explicitly requested"
  }

  $vision = $json.models | Where-Object id -eq "vision-model"
  if ($vision.supportsImages -ne $true -or $vision.supportsReasoning -ne $true) {
    throw "Explicit input modalities and token-budget thinking should map"
  }
  if ($null -ne $vision.PSObject.Properties["reasoning"]) {
    throw "Token-budget thinking must not invent effort levels"
  }
  if ($null -ne $vision.PSObject.Properties["supportsToolCall"]) {
    throw "Unknown tool capability must be omitted"
  }

  $conflict = $json.models | Where-Object id -eq "conflict-model"
  if ($null -ne $conflict.PSObject.Properties["maxInputTokens"]) {
    throw "Conflicting catalog values must be omitted"
  }
  if ($result.Stderr -notmatch "conflict-model" -or $result.Stderr -notmatch "contextTokens") {
    throw "Catalog conflicts should be reported on stderr"
  }

  $unknown = $json.models | Where-Object id -eq "unknown-model"
  foreach ($field in @("supportsToolCall", "supportsImages", "supportsReasoning", "reasoning", "maxInputTokens", "maxOutputTokens")) {
    if ($null -ne $unknown.PSObject.Properties[$field]) {
      throw "Unknown model must omit capability field '$field'"
    }
  }

  '{"bad":{"id":"not-an-array"}}' | Set-Content -LiteralPath (Join-Path $InstallDir "models.json") -Encoding UTF8
  $seeded = Invoke-Manager @(
    "-Action", "client-config",
    "-InstallDir", $InstallDir,
    "-Format", "workbuddy",
    "-ModelIds", "gpt-5.5"
  )
  if ($seeded.ExitCode -ne 0) {
    throw "client-config should replace an invalid installed catalog with the repository snapshot. Stderr:`n$($seeded.Stderr)"
  }
  $seededJson = $seeded.Stdout | ConvertFrom-Json
  if ($seededJson.models[0].supportsReasoning -ne $true) {
    throw "Seeded repository snapshot should provide gpt-5.5 reasoning metadata"
  }
  $installedCatalog = Get-Content -LiteralPath (Join-Path $InstallDir "models.json") -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($null -eq $installedCatalog.PSObject.Properties["codex-plus"]) {
    throw "Invalid installed catalog should be atomically replaced by the official repository snapshot"
  }
} finally {
  if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
  }
}

Write-Output "WINDOWS_CLIENT_CONFIG_OK"
