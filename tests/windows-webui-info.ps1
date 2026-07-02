$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$ScriptPath = Join-Path $RepoRoot "scripts\windows\manage-cliproxyapi.ps1"
$StatePath = Join-Path $RepoRoot ".cliproxyapi-manager-state.windows.json"
$StateBackupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-manager-state.windows.{0}.json" -f ([Guid]::NewGuid().ToString("N")))
$HadState = Test-Path -LiteralPath $StatePath
$InstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-webui-info-{0}" -f ([Guid]::NewGuid().ToString("N")))
$BcryptInstallDir = Join-Path ([System.IO.Path]::GetTempPath()) ("cliproxyapi-webui-bcrypt-{0}" -f ([Guid]::NewGuid().ToString("N")))

function New-StringFromCodePoints {
  param([int[]] $CodePoints)

  return -join ($CodePoints | ForEach-Object { [char] $_ })
}

try {
  if ($HadState) {
    Move-Item -LiteralPath $StatePath -Destination $StateBackupPath -Force
  }

  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Set-Content -LiteralPath (Join-Path $InstallDir "config.yaml") -Encoding UTF8 -Value @"
host: "127.0.0.1"
port: 9234

api-keys:
  - "wb-local-webui-test"

remote-management:
  allow-remote: false
  secret-key: "mgmt-local-webui-test-secret"

unrelated-secret:
  secret-key: "not-the-webui-management-secret"
"@

  $output = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Action webui-info -InstallDir $InstallDir 2>&1
  $text = $output -join "`n"

  if ($LASTEXITCODE -ne 0) {
    throw "webui-info should exit successfully. Exit code: $LASTEXITCODE. Output:`n$text"
  }
  foreach ($required in @(
    "http://localhost:9234/management.html",
    ("WebUI " + (New-StringFromCodePoints @(0x7BA1, 0x7406, 0x5BC6, 0x94A5))),
    "remote-management.secret-key",
    "mgmt-local-webui-test-secret"
  )) {
    if ($text -notmatch [regex]::Escape($required)) {
      throw "webui-info output is missing required text: $required`nActual output:`n$text"
    }
  }
  if ($text -match [regex]::Escape("not-the-webui-management-secret")) {
    throw "webui-info must only print remote-management.secret-key. Actual output:`n$text"
  }

  New-Item -ItemType Directory -Force -Path $BcryptInstallDir | Out-Null
  $BcryptHash = '$2a$10$Fzf5MdYAPAKPE1BtOfaLHubwrAspqK0.oCcQ4ExtavLwM7JA9Xp6u'
  $PlainWebUIKey = "mgmt-local-plain-secret-for-webui"
  Set-Content -LiteralPath (Join-Path $BcryptInstallDir "config.yaml") -Encoding UTF8 -Value @"
host: "127.0.0.1"
port: 9235

api-keys:
  - "wb-local-webui-test"

remote-management:
  allow-remote: false
  secret-key: '$BcryptHash'
"@
  Set-Content -LiteralPath (Join-Path $BcryptInstallDir "webui-management-key.txt") -Encoding UTF8 -Value $PlainWebUIKey

  $bcryptOutput = powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -Action webui-info -InstallDir $BcryptInstallDir 2>&1
  $bcryptText = $bcryptOutput -join "`n"
  if ($LASTEXITCODE -ne 0) {
    throw "webui-info should exit successfully for bcrypt config with local plaintext key. Exit code: $LASTEXITCODE. Output:`n$bcryptText"
  }
  if ($bcryptText -notmatch [regex]::Escape($PlainWebUIKey)) {
    throw "webui-info should print the saved plaintext WebUI key, not the bcrypt hash. Output:`n$bcryptText"
  }
  if ($bcryptText -match [regex]::Escape($BcryptHash)) {
    throw "webui-info must not print bcrypt hash as the WebUI management key. Output:`n$bcryptText"
  }
} finally {
  if (Test-Path -LiteralPath $StatePath) {
    Remove-Item -LiteralPath $StatePath -Force
  }
  if ($HadState -and (Test-Path -LiteralPath $StateBackupPath)) {
    Move-Item -LiteralPath $StateBackupPath -Destination $StatePath -Force
  }
  if (Test-Path -LiteralPath $InstallDir) {
    Remove-Item -LiteralPath $InstallDir -Recurse -Force
  }
  if (Test-Path -LiteralPath $BcryptInstallDir) {
    Remove-Item -LiteralPath $BcryptInstallDir -Recurse -Force
  }
}

Write-Output "WINDOWS_WEBUI_INFO_OK"
