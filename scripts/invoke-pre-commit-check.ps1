[CmdletBinding()]
param(
  [switch]$SkipOptionalTools
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

function Invoke-Checked {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][scriptblock]$Action
  )

  Write-Host "`n==> $Name" -ForegroundColor Cyan
  & $Action
  if ($LASTEXITCODE -notin @(0, $null)) { throw "$Name failed with exit code $LASTEXITCODE." }
}

Push-Location $root
try {
  Invoke-Checked 'Terraform format' { terraform fmt -check -recursive -diff }
  Invoke-Checked 'Terraform initialization' { terraform init -backend=false -input=false -lockfile=readonly }
  Invoke-Checked 'Terraform validation' { terraform validate -no-color }
  Invoke-Checked 'Terraform mocked tests' { terraform test -no-color }
  Invoke-Checked 'Pester lifecycle tests' { pwsh -NoProfile -File (Join-Path $root 'scripts/invoke-pester-tests.ps1') }
  Invoke-Checked 'Go repository contracts' {
    Push-Location (Join-Path $root 'tests')
    try { go test ./... } finally { Pop-Location }
  }
  Invoke-Checked 'Local Markdown links' { & (Join-Path $root 'scripts/test-markdown-links.ps1') }

  if (-not $SkipOptionalTools) {
    Invoke-Checked 'TFLint' { tflint --recursive }
    Invoke-Checked 'Trivy configuration scan' { trivy config --exit-code 1 --severity HIGH,CRITICAL --ignorefile .trivyignore.yaml --skip-dirs .cache --skip-dirs .terraform . }
    Invoke-Checked 'Conftest policy (secure fixture)' { conftest test tests/fixtures/plan-secure.json --policy policy --all-namespaces }
    Invoke-Checked 'Conftest policy (insecure fixture denied)' {
      conftest test tests/fixtures/plan-insecure.json --policy policy --all-namespaces
      if ($LASTEXITCODE -eq 0) { throw 'The intentionally insecure fixture was not denied.' }
      $global:LASTEXITCODE = 0
    }
    Invoke-Checked 'Terraform documentation drift' { & (Join-Path $root 'scripts/generate-terraform-docs.ps1') -Check }
    Invoke-Checked 'GitHub Actions syntax' { actionlint }
  }
}
finally {
  Pop-Location
}

Write-Host "`nAll selected static checks passed." -ForegroundColor Green
