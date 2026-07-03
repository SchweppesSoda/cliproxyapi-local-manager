$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$CheckedFiles = @(
  "manage-cliproxyapi.command",
  "manage-cliproxyapi.sh",
  "scripts/macos/manage-cliproxyapi.sh"
)

function New-StringFromCodePoint {
  param([int] $CodePoint)
  return [string][char]$CodePoint
}

function New-StringFromCodePoints {
  param([int[]] $CodePoints)
  return -join ($CodePoints | ForEach-Object { [char] $_ })
}

$ForbiddenFragments = @(
  (New-StringFromCodePoint 0x951B),
  (New-StringFromCodePoint 0x93C8),
  (New-StringFromCodePoint 0x9429),
  (New-StringFromCodePoint 0x7039),
  (New-StringFromCodePoint 0x93B5),
  (New-StringFromCodePoint 0x5A34),
  (New-StringFromCodePoint 0x8930),
  (New-StringFromCodePoint 0x95B0),
  (New-StringFromCodePoint 0x9363),
  (New-StringFromCodePoint 0x93C2),
  (New-StringFromCodePoint 0x9418),
  (New-StringFromCodePoint 0x93B8),
  (New-StringFromCodePoint 0x6D16),
  (New-StringFromCodePoint 0x20AC),
  (New-StringFromCodePoint 0xFFFD)
)

foreach ($relativePath in $CheckedFiles) {
  $path = Join-Path $RepoRoot $relativePath
  $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
  foreach ($fragment in $ForbiddenFragments) {
    if ($text.Contains($fragment)) {
      throw "Found mojibake fragment '$fragment' in $relativePath"
    }
  }
}

$ExpectedTexts = @{
  "manage-cliproxyapi.command" = @(
    (New-StringFromCodePoints @(0x6309, 0x56DE, 0x8F66, 0x5173, 0x95ED, 0x6B64, 0x7A97, 0x53E3))
  )
  "scripts/macos/manage-cliproxyapi.sh" = @(
    ("CLIProxyAPI " + (New-StringFromCodePoints @(0x672C, 0x5730, 0x7BA1, 0x7406, 0x5668, 0xFF08)) + "macOS" + (New-StringFromCodePoints @(0xFF09))),
    (New-StringFromCodePoints @(0x663E, 0x793A, 0x672C, 0x5730, 0x72B6, 0x6001))
  )
}

foreach ($entry in $ExpectedTexts.GetEnumerator()) {
  $path = Join-Path $RepoRoot $entry.Key
  $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
  foreach ($expected in $entry.Value) {
    if (-not $text.Contains($expected)) {
      throw "Missing expected UTF-8 Chinese text '$expected' in $($entry.Key)"
    }
  }
}

Write-Output "MACOS_NO_MOJIBAKE_OK"
