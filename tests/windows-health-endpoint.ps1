$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$StatePath = Join-Path $RepoRoot ".cliproxyapi-manager-state.windows.json"
$StateBackupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-manager-state.windows.{0}.json" -f ([Guid]::NewGuid().ToString("N")))
$HadState = Test-Path -LiteralPath $StatePath
$OriginalLocalAppData = $env:LOCALAPPDATA
$TestLocalAppData = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-health-localappdata-{0}" -f ([Guid]::NewGuid().ToString("N")))
$ResultPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-health-request-{0}.txt" -f ([Guid]::NewGuid().ToString("N")))
$ReadyPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-health-ready-{0}.txt" -f ([Guid]::NewGuid().ToString("N")))
$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), 0)
$listener.Start()
$port = ([System.Net.IPEndPoint] $listener.LocalEndpoint).Port
$listener.Stop()
$serverJob = $null

try {
  if ($HadState) {
    Move-Item -LiteralPath $StatePath -Destination $StateBackupPath -Force
  }

  New-Item -ItemType Directory -Force -Path $TestLocalAppData | Out-Null
  $env:LOCALAPPDATA = $TestLocalAppData
  $installDir = Join-Path $TestLocalAppData "Programs\CLIProxyAPI"
  New-Item -ItemType Directory -Force -Path $installDir | Out-Null
  Set-Content -LiteralPath (Join-Path $installDir "config.yaml") -Encoding UTF8 -Value @"
host: "127.0.0.1"
port: $port

api-keys:
  - "wb-local-testkey"

remote-management:
  allow-remote: false
  secret-key: "mgmt-local-testkey"
"@

  $serverJob = Start-Job -ArgumentList $port, $ResultPath, $ReadyPath -ScriptBlock {
    param($Port, $ResultPath, $ReadyPath)
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Parse("127.0.0.1"), [int]$Port)
    $listener.Start()
    Set-Content -LiteralPath $ReadyPath -Encoding ASCII -Value "ready"
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
      $body = '{"object":"list","data":[{"id":"gpt-test","object":"model"}]}'
      $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
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

  $output = "`n" | powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Action health 2>&1
  Wait-Job -Job $serverJob -Timeout 5 | Out-Null
  if (-not (Test-Path -LiteralPath $ResultPath)) {
    $text = $output -join "`n"
    throw "Manager did not send a request to the mock server. Output:`n$text"
  }

  $request = Get-Content -LiteralPath $ResultPath -Encoding UTF8
  if ($request[0] -ne "GET /v1/models HTTP/1.1") {
    throw "Expected health check to request /v1/models. Actual: $($request[0])"
  }
  if ($request[1] -ne "Bearer wb-local-testkey") {
    throw "Expected Authorization bearer token. Actual: $($request[1])"
  }
} finally {
  if ($serverJob) {
    Stop-Job -Job $serverJob -ErrorAction SilentlyContinue
    Remove-Job -Job $serverJob -Force -ErrorAction SilentlyContinue
  }
  $env:LOCALAPPDATA = $OriginalLocalAppData
  if (Test-Path -LiteralPath $StatePath) {
    Remove-Item -LiteralPath $StatePath -Force
  }
  if ($HadState -and (Test-Path -LiteralPath $StateBackupPath)) {
    Copy-Item -LiteralPath $StateBackupPath -Destination $StatePath -Force
    Remove-Item -LiteralPath $StateBackupPath -Force
  }
  foreach ($path in @($TestLocalAppData, $ResultPath, $ReadyPath)) {
    if (Test-Path -LiteralPath $path) {
      Remove-Item -LiteralPath $path -Recurse -Force
    }
  }
}

Write-Output "WINDOWS_HEALTH_ENDPOINT_OK"
