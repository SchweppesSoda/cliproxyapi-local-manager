$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$InstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-manager-workbuddy-json-" + [Guid]::NewGuid().ToString("N"))

function Start-ModelsServer {
  param(
    [string] $Body,
    [string] $ResultPath,
    [string] $ReadyPath
  )

  $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), 0)
  $listener.Start()
  $port = ([System.Net.IPEndPoint] $listener.LocalEndpoint).Port
  $listener.Stop()

  $job = Start-Job -ArgumentList $port, $Body, $ResultPath, $ReadyPath -ScriptBlock {
    param($Port, $Body, $ResultPath, $ReadyPath)
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), [int]$Port)
    $listener.Start()
    Set-Content -LiteralPath $ReadyPath -Encoding ASCII -Value "ready"
    $deadline = (Get-Date).AddSeconds(8)
    while (-not $listener.Pending()) {
      if ((Get-Date) -gt $deadline) {
        Set-Content -LiteralPath $ResultPath -Encoding UTF8 -Value @("NO_REQUEST", "")
        $listener.Stop()
        return
      }
      Start-Sleep -Milliseconds 50
    }
    $client = $listener.AcceptTcpClient()
    try {
      $stream = $client.GetStream()
      $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::ASCII)
      $requestLine = $reader.ReadLine()
      $authorization = ""
      while ($true) {
        $line = $reader.ReadLine()
        if ($null -eq $line -or $line -eq "") {
          break
        }
        if ($line -match '^Authorization:\s*(.+)$') {
          $authorization = $Matches[1]
        }
      }
      Set-Content -LiteralPath $ResultPath -Encoding UTF8 -Value @($requestLine, $authorization)
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
      $headers = "HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: $($bytes.Length)`r`nConnection: close`r`n`r`n"
      $headerBytes = [System.Text.Encoding]::ASCII.GetBytes($headers)
      $stream.Write($headerBytes, 0, $headerBytes.Length)
      $stream.Write($bytes, 0, $bytes.Length)
      $stream.Flush()
    } finally {
      $client.Close()
      $listener.Stop()
    }
  }

  $deadline = (Get-Date).AddSeconds(5)
  while (-not (Test-Path -LiteralPath $ReadyPath)) {
    if ((Get-Date) -gt $deadline) {
      throw "Mock server did not become ready"
    }
    Start-Sleep -Milliseconds 50
  }

  return [ordered]@{
    Port = $port
    Job = $job
  }
}

function ConvertFrom-OutputJson {
  param([string] $RawOutput)

  $jsonStart = $RawOutput.IndexOf("{")
  if ($jsonStart -lt 0) {
    throw "Output does not contain JSON:`n$RawOutput"
  }
  return $RawOutput.Substring($jsonStart) | ConvertFrom-Json
}

function Invoke-ManagerWithInput {
  param(
    [string] $InputText,
    [string[]] $Arguments
  )

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = "powershell.exe"
  $quotedArguments = foreach ($argument in @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $ScriptPath) + $Arguments) {
    if ($argument -match '[\s"]') {
      '"' + ($argument -replace '"', '\"') + '"'
    } else {
      $argument
    }
  }
  $psi.Arguments = $quotedArguments -join " "
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.UseShellExecute = $false
  $process = [System.Diagnostics.Process]::Start($psi)
  $process.StandardInput.Write($InputText)
  $process.StandardInput.Close()

  if (-not $process.WaitForExit(10000)) {
    $process.Kill()
    throw "Manager process timed out. Stdout:`n$($process.StandardOutput.ReadToEnd())`nStderr:`n$($process.StandardError.ReadToEnd())"
  }

  $stdout = $process.StandardOutput.ReadToEnd()
  $stderr = $process.StandardError.ReadToEnd()
  if ($process.ExitCode -ne 0) {
    throw "Manager process exited $($process.ExitCode). Stdout:`n$stdout`nStderr:`n$stderr"
  }
  return $stdout
}

New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
$serverJob = $null
try {
  @"
host: "127.0.0.1"
port: 8317

api-keys:
  - "wb-local-test-key"

remote-management:
  allow-remote: false
  secret-key: "mgmt-local-test-key"
"@ | Set-Content -LiteralPath (Join-Path $InstallDir "config.yaml") -Encoding UTF8

  $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath `
    -Action workbuddy-json `
    -InstallDir $InstallDir `
    -ModelIds "chat-model,image-model" `
    -ImageModelIds "image-model"

  $json = ConvertFrom-OutputJson ($output | Out-String)
  if ($null -ne $json.PSObject.Properties["availableModels"]) {
    throw "WorkBuddy JSON generator must not emit availableModels by default"
  }
  if ($null -eq $json.PSObject.Properties["models"]) {
    throw "WorkBuddy JSON generator should emit a models object root"
  }
  if ($json.models.Count -ne 2) {
    throw "Expected 2 WorkBuddy models. Actual: $($json.models.Count)"
  }
  if ($json.models[0].id -ne "chat-model" -or $json.models[1].id -ne "image-model") {
    throw "WorkBuddy model array should preserve the requested order"
  }

  $chatModel = $json.models | Where-Object { $_.id -eq "chat-model" }
  $imageModel = $json.models | Where-Object { $_.id -eq "image-model" }
  if (-not $chatModel -or -not $imageModel) {
    throw "Expected both requested model entries"
  }
  if ($chatModel.url -ne "http://127.0.0.1:8317/v1/chat/completions") {
    throw "Expected WorkBuddy chat completions URL. Actual: $($chatModel.url)"
  }
  if ($chatModel.apiKey -ne "wb-local-test-key") {
    throw "Expected apiKey from config.yaml"
  }
  if ($chatModel.vendor -ne "CLIProxyAPI") {
    throw "Expected WorkBuddy vendor=CLIProxyAPI"
  }
  if ($null -ne $chatModel.PSObject.Properties["supportsToolCall"]) {
    throw "Unknown chat model should omit supportsToolCall"
  }
  foreach ($unsupportedCapabilityField in @("supportsReasoning", "reasoning", "useCustomProtocol")) {
    if ($null -ne $chatModel.PSObject.Properties[$unsupportedCapabilityField]) {
      throw "WorkBuddy JSON generator must not emit unverified field '$unsupportedCapabilityField' by default"
    }
  }
  if ($null -ne $chatModel.PSObject.Properties["supportsImages"]) {
    throw "Unknown chat model should omit supportsImages"
  }
  if ($imageModel.supportsImages -ne $true) {
    throw "Expected image-model supportsImages=true"
  }

  $singleOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath `
    -Action workbuddy-json `
    -InstallDir $InstallDir `
    -ModelIds "single-model" `
    -ImageModelIds "*"

  $singleRaw = $singleOutput | Out-String
  if (-not $singleRaw.TrimStart().StartsWith("{")) {
    throw "Single-model output should be a WorkBuddy models object"
  }
  $singleJson = ConvertFrom-OutputJson $singleRaw
  if ($singleJson.models[0].id -ne "single-model" -or $singleJson.models[0].supportsImages -ne $true) {
    throw "Single-model output should preserve id and wildcard image support"
  }

  $mixedOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath `
    -Action workbuddy-json `
    -InstallDir $InstallDir `
    -ModelIds "gpt-image-2,gpt-5.5" `
    -ImageModelIds "*"

  $mixedJson = ConvertFrom-OutputJson ($mixedOutput | Out-String)
  if ($mixedJson.models.Count -ne 1 -or $mixedJson.models[0].id -ne "gpt-5.5") {
    throw "Image-generation-only models should be skipped from WorkBuddy chat model output"
  }
  if ($mixedJson.models[0].url -match 'images/generations|images/edits') {
    throw "WorkBuddy chat model output must not use Image API endpoints"
  }

  $fallbackOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath `
    -Action workbuddy-json `
    -InstallDir $InstallDir `
    -ModelIds "gpt-5.5,gpt-5.4,gpt-5.4-mini,gpt-5.3-codex-spark,codex-auto-review"

  $fallbackJson = ConvertFrom-OutputJson ($fallbackOutput | Out-String)
  foreach ($fallbackModelId in @("gpt-5.5", "gpt-5.4", "gpt-5.4-mini")) {
    $fallbackModel = $fallbackJson.models | Where-Object { $_.id -eq $fallbackModelId }
    foreach ($tokenLimitField in @("maxInputTokens", "maxOutputTokens")) {
      if ($null -ne $fallbackModel.PSObject.Properties[$tokenLimitField]) {
        throw "Token limit field '$tokenLimitField' should be omitted by default for $fallbackModelId"
      }
    }
    if ($fallbackModel.supportsReasoning -ne $true) {
      throw "Expected built-in reasoning fallback for $fallbackModelId"
    }
    if ($null -ne $fallbackModel.reasoning.PSObject.Properties["defaultEffort"]) {
      throw "$fallbackModelId should omit defaultEffort in phase one"
    }
    foreach ($expectedEffort in @("low", "medium", "high", "xhigh")) {
      if (-not ($fallbackModel.reasoning.supportedEfforts -contains $expectedEffort)) {
        throw "Expected built-in supported effort '$expectedEffort' for $fallbackModelId"
      }
    }
    if ($fallbackModel.reasoning.supportedEfforts -contains "none") {
      throw "WorkBuddy supportedEfforts should not include none"
    }
  }
  $tokenLimitOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath `
    -Action workbuddy-json `
    -InstallDir $InstallDir `
    -ModelIds "gpt-5.5,gpt-5.4-mini" `
    -IncludeTokenLimits

  $tokenLimitJson = ConvertFrom-OutputJson ($tokenLimitOutput | Out-String)
  $gpt55 = $tokenLimitJson.models | Where-Object { $_.id -eq "gpt-5.5" }
  if ($gpt55.maxInputTokens -ne 272000 -or $gpt55.maxOutputTokens -ne 128000) {
    throw "Explicit -IncludeTokenLimits should emit CLIProxyAPI catalog limits for gpt-5.5"
  }
  $gpt54Mini = $tokenLimitJson.models | Where-Object { $_.id -eq "gpt-5.4-mini" }
  if ($gpt54Mini.maxInputTokens -ne 400000 -or $gpt54Mini.maxOutputTokens -ne 128000) {
    throw "Explicit -IncludeTokenLimits should emit official token limits for gpt-5.4-mini"
  }

  $interactiveInstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-manager-workbuddy-json-interactive-" + [Guid]::NewGuid().ToString("N"))
  New-Item -ItemType Directory -Path $interactiveInstallDir -Force | Out-Null
  $resultPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-workbuddy-json-request-" + [Guid]::NewGuid().ToString("N") + ".txt")
  $readyPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-workbuddy-json-ready-" + [Guid]::NewGuid().ToString("N") + ".txt")
  $server = Start-ModelsServer `
    -Body '{"object":"list","data":[{"id":"chat-model","supportsReasoning":true,"reasoning":{"defaultEffort":"medium","supportedEfforts":["low","medium","high"]},"maxInputTokens":12345,"maxOutputTokens":678},{"id":"fast-model","supportsReasoning":false},{"id":"vision-model","supportsImages":true,"maxInputTokens":23456,"maxOutputTokens":789}]}' `
    -ResultPath $resultPath `
    -ReadyPath $readyPath
  $serverJob = $server.Job

  @"
host: "127.0.0.1"
port: $($server.Port)

api-keys:
  - "wb-local-test-key"

remote-management:
  allow-remote: false
  secret-key: "mgmt-local-test-key"
"@ | Set-Content -LiteralPath (Join-Path $interactiveInstallDir "config.yaml") -Encoding UTF8

  $interactiveRaw = Invoke-ManagerWithInput `
    -InputText "3,1`n`n" `
    -Arguments @("-Action", "workbuddy-json", "-InstallDir", $interactiveInstallDir)

  Wait-Job -Job $serverJob -Timeout 5 | Out-Null
  foreach ($expectedListItem in @("1) chat-model", "2) fast-model", "3) vision-model")) {
    if ($interactiveRaw -notmatch [regex]::Escape($expectedListItem)) {
      throw "Interactive output should show selectable model item '$expectedListItem'. Output:`n$interactiveRaw"
    }
  }
  $interactiveJson = ConvertFrom-OutputJson $interactiveRaw
  if ($interactiveRaw -match 'none=') {
    throw 'Interactive output should not ask users to guess image-input support'
  }
  if ($interactiveJson.models.Count -ne 2 -or $interactiveJson.models[0].id -ne "vision-model" -or $interactiveJson.models[1].id -ne "chat-model") {
    throw "Interactive numeric selection should preserve the requested order"
  }
  if ($null -ne $interactiveJson.PSObject.Properties["availableModels"]) {
    throw "Interactive output must not emit availableModels by default"
  }
  $selectedChatModel = $interactiveJson.models | Where-Object { $_.id -eq "chat-model" }
  if ($null -ne $selectedChatModel.PSObject.Properties["supportsReasoning"] -or $null -ne $selectedChatModel.PSObject.Properties["reasoning"]) {
    throw "Interactive output must not copy nonstandard capability metadata from /v1/models"
  }
  foreach ($tokenLimitField in @("maxInputTokens", "maxOutputTokens")) {
    if ($null -ne $selectedChatModel.PSObject.Properties[$tokenLimitField]) {
      throw "Interactive output should omit '$tokenLimitField' by default"
    }
  }
  if ($null -ne $selectedChatModel.PSObject.Properties["supportsImages"]) {
    throw "Interactive output should omit unknown image input support"
  }
  if ($null -ne $selectedChatModel.PSObject.Properties["useCustomProtocol"]) {
    throw "Interactive output should not emit undocumented useCustomProtocol when /v1/models does not return it"
  }
  $selectedVisionModel = $interactiveJson.models | Where-Object { $_.id -eq "vision-model" }
  if ($null -ne $selectedVisionModel.PSObject.Properties["supportsImages"]) {
    throw "Interactive output must not copy vision metadata from /v1/models"
  }
  if ((Get-Content -LiteralPath $resultPath -Encoding UTF8)[0] -ne "GET /v1/models HTTP/1.1") {
    throw "Interactive mode should query /v1/models before asking for numeric selection"
  }
} finally {
  if ($serverJob) {
    Stop-Job -Job $serverJob -ErrorAction SilentlyContinue
    Remove-Job -Job $serverJob -Force -ErrorAction SilentlyContinue
  }
  if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
  }
  foreach ($path in @($interactiveInstallDir, $resultPath, $readyPath)) {
    if ($path -and (Test-Path -LiteralPath $path)) {
      Remove-Item -LiteralPath $path -Recurse -Force
    }
  }
}

Write-Output "WINDOWS_WORKBUDDY_JSON_OK"
