[CmdletBinding()]
param(
  [string]$OutputFile = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $OutputFile) {
  $cacheDirectory = Join-Path $root '.cache'
  New-Item -ItemType Directory -Force -Path $cacheDirectory | Out-Null
  $OutputFile = Join-Path $cacheDirectory 'pester-results.xml'
}

$configuration = New-PesterConfiguration
$configuration.Run.Path = Join-Path $root 'tests/pester'
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'
$configuration.TestResult.Enabled = $true
$configuration.TestResult.OutputPath = $OutputFile

$result = Invoke-Pester -Configuration $configuration
if ($result.FailedCount -gt 0 -or $result.FailedContainersCount -gt 0) {
  throw "Pester failed: $($result.FailedCount) failed tests and $($result.FailedContainersCount) failed containers."
}

