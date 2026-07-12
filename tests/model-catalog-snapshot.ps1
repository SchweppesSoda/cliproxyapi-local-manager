$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")
$CatalogPath = Join-Path $RepoRoot "data\cliproxyapi-models.json"
if (-not (Test-Path -LiteralPath $CatalogPath)) {
  throw "Missing official CLIProxyAPI model catalog snapshot: $CatalogPath"
}

$catalog = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
$groups = @($catalog.PSObject.Properties)
if ($groups.Count -lt 1) {
  throw "Model catalog snapshot must contain provider/plan groups"
}

$modelCount = 0
foreach ($group in $groups) {
  if ($group.Value -isnot [System.Array]) {
    throw "Catalog group '$($group.Name)' must be a JSON array"
  }
  $items = @($group.Value)
  $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
  foreach ($model in $items) {
    if ($null -eq $model -or $null -eq $model.PSObject.Properties["id"] -or $model.id -isnot [string] -or [string]::IsNullOrWhiteSpace($model.id)) {
      throw "Catalog group '$($group.Name)' contains a model without a non-empty string id"
    }
    if (-not $seen.Add($model.id.Trim())) {
      throw "Catalog group '$($group.Name)' contains duplicate id '$($model.id)'"
    }
    $modelCount++
  }
}
if ($modelCount -lt 1) {
  throw "Model catalog snapshot must contain at least one model"
}

$raw = Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8
foreach ($forbidden in @('"apiKey"', '"api_key"', '"access_token"', '"refresh_token"', '"management_key"')) {
  if ($raw -match [regex]::Escape($forbidden)) {
    throw "Official snapshot must not contain local secret field $forbidden"
  }
}

Write-Output "MODEL_CATALOG_SNAPSHOT_OK"
