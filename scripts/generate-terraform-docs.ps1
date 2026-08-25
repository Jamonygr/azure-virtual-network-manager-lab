[CmdletBinding()]
param(
  [switch]$Check
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$tool = Get-Command terraform-docs -ErrorAction SilentlyContinue
if (-not $tool) {
  throw 'terraform-docs 0.24.0 is required. See docs/testing.md for installation instructions.'
}

$targets = @(
  @{ Source = $root; Output = (Join-Path $root 'docs/generated/terraform.md') }
)
Get-ChildItem -LiteralPath (Join-Path $root 'modules') -Directory | Sort-Object Name | ForEach-Object {
  $targets += @{ Source = $_.FullName; Output = (Join-Path $_.FullName 'README.md') }
}

$drift = [System.Collections.Generic.List[string]]::new()
foreach ($target in $targets) {
  $generated = (& $tool.Source markdown table --hide modules $target.Source | Out-String).TrimEnd() + "`n"
  if ($LASTEXITCODE -ne 0) { throw "terraform-docs failed with exit code $LASTEXITCODE." }

  if ($Check) {
    $current = if (Test-Path -LiteralPath $target.Output) {
      (Get-Content -LiteralPath $target.Output -Raw).Replace("`r`n", "`n")
    }
    else { '' }
    if ($current -ne $generated.Replace("`r`n", "`n")) {
      $drift.Add([IO.Path]::GetRelativePath($root, $target.Output))
    }
  }
  else {
    [IO.File]::WriteAllText($target.Output, $generated, [Text.UTF8Encoding]::new($false))
    Write-Host "Generated $([IO.Path]::GetRelativePath($root, $target.Output))"
  }
}

if ($drift.Count -gt 0) {
  throw "terraform-docs output is stale: $($drift -join ', '). Run ./scripts/generate-terraform-docs.ps1."
}
