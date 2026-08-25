Set-StrictMode -Version Latest

function ConvertTo-IPv4UInt32 {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Address)

  $bytes = [System.Net.IPAddress]::Parse($Address).GetAddressBytes()
  if ($bytes.Count -ne 4) { throw "Only IPv4 addresses are supported: $Address" }
  return [uint64]($bytes[0] * [math]::Pow(256, 3) + $bytes[1] * [math]::Pow(256, 2) + $bytes[2] * 256 + $bytes[3])
}

function Get-CidrRange {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Cidr)

  $parts = $Cidr -split '/'
  if ($parts.Count -ne 2) { throw "Invalid CIDR: $Cidr" }
  $prefixLength = [int]$parts[1]
  if ($prefixLength -lt 0 -or $prefixLength -gt 32) { throw "Invalid IPv4 prefix length: $Cidr" }

  $address = ConvertTo-IPv4UInt32 -Address $parts[0]
  $size = [uint64][math]::Pow(2, 32 - $prefixLength)
  $first = [uint64]([math]::Floor($address / $size) * $size)

  [pscustomobject]@{
    Cidr         = $Cidr
    PrefixLength = $prefixLength
    First        = $first
    Last         = $first + $size - 1
    Size         = $size
  }
}

function Test-CidrContains {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Parent,
    [Parameter(Mandatory)][string]$Child
  )

  $parentRange = Get-CidrRange -Cidr $Parent
  $childRange = Get-CidrRange -Cidr $Child
  return $childRange.First -ge $parentRange.First -and $childRange.Last -le $parentRange.Last
}

function Test-CidrOverlap {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Left,
    [Parameter(Mandatory)][string]$Right
  )

  $leftRange = Get-CidrRange -Cidr $Left
  $rightRange = Get-CidrRange -Cidr $Right
  return -not ($leftRange.Last -lt $rightRange.First -or $rightRange.Last -lt $leftRange.First)
}

function Get-PlanChangeViolations {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Plan,
    [Parameter(Mandatory)][string[]]$AllowedAddresses,
    [hashtable]$AllowedActionsByAddress = @{}
  )

  $violations = [System.Collections.Generic.List[string]]::new()
  foreach ($change in @($Plan.resource_changes)) {
    $actions = @($change.change.actions)
    if ($actions.Count -eq 0 -or ($actions.Count -eq 1 -and $actions[0] -in @('no-op', 'read'))) { continue }
    if ($change.address -notin $AllowedAddresses) {
      $violations.Add("$($change.address): $($actions -join ',')")
    }
    elseif ($AllowedActionsByAddress.ContainsKey([string]$change.address)) {
      $expectedActions = @($AllowedActionsByAddress[[string]$change.address])
      if (($actions -join ',') -cne ($expectedActions -join ',')) {
        $violations.Add("$($change.address): planned $($actions -join ','); expected $($expectedActions -join ',')")
      }
    }
    elseif ($actions.Count -ne 1 -or $actions[0] -ne 'update') {
      $violations.Add("$($change.address): only an in-place update is allowed; planned $($actions -join ',')")
    }
  }
  return @($violations)
}

function Get-DeploymentDisposition {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]$Records,
    [Parameter(Mandatory)][string]$ConfigurationId,
    [datetime]$NotBefore = [datetime]::MinValue
  )

  $matching = @($Records | Where-Object {
      $json = $_ | ConvertTo-Json -Depth 30 -Compress
      $json -match [regex]::Escape($ConfigurationId)
    })

  if ($matching.Count -eq 0) {
    return [pscustomobject]@{ State = 'Pending'; Message = 'No matching deployment record yet.'; Record = $null }
  }

  $latest = $matching | Sort-Object {
    $candidate = $_.commitTime
    if (-not $candidate) { $candidate = $_.deploymentTime }
    if (-not $candidate) { $candidate = $_.createdTime }
    if ($candidate) { [datetime]$candidate } else { [datetime]::MinValue }
  } -Descending | Select-Object -First 1

  $timeText = $latest.commitTime
  if (-not $timeText) { $timeText = $latest.deploymentTime }
  if (-not $timeText) { $timeText = $latest.createdTime }
  if ($timeText -and [datetime]$timeText -lt $NotBefore) {
    return [pscustomobject]@{ State = 'Stale'; Message = "Latest matching deployment predates $($NotBefore.ToString('o'))."; Record = $latest }
  }

  $status = [string]$latest.deploymentStatus
  if (-not $status) { $status = [string]$latest.status }
  if ($status -match '^(?i)(Deployed|Succeeded)$') {
    return [pscustomobject]@{ State = 'Deployed'; Message = $status; Record = $latest }
  }
  if ($status -match '^(?i)(Failed|Canceled|Cancelled)$') {
    $errorText = [string]$latest.errorMessage
    if (-not $errorText) { $errorText = ($latest.error | ConvertTo-Json -Depth 10 -Compress) }
    return [pscustomobject]@{ State = 'Failed'; Message = "$status $errorText".Trim(); Record = $latest }
  }
  return [pscustomobject]@{ State = 'Pending'; Message = $(if ($status) { $status } else { 'Unknown status' }); Record = $latest }
}

function Invoke-GuardedOperation {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][scriptblock]$Work,
    [Parameter(Mandatory)][scriptblock]$Cleanup
  )

  $workError = $null
  $cleanupError = $null
  try {
    & $Work
  }
  catch {
    $workError = $_
  }
  finally {
    try { & $Cleanup } catch { $cleanupError = $_ }
  }

  if ($workError -and $cleanupError) {
    throw "Work failed: $($workError.Exception.Message)`nCleanup also failed: $($cleanupError.Exception.Message)"
  }
  if ($workError) { throw $workError }
  if ($cleanupError) { throw $cleanupError }
}

function Wait-AvnmCondition {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][scriptblock]$Probe,
    [Parameter(Mandatory)][string]$Description,
    [Parameter(Mandatory)][datetime]$Deadline,
    [int]$PollSeconds = 20
  )

  do {
    $result = & $Probe
    if ($result -is [bool] -and $result) { return $true }
    if ($result -and $result.PSObject.Properties.Name -contains 'Done' -and $result.Done) { return $result }
    if ($result -and $result.PSObject.Properties.Name -contains 'TerminalError' -and $result.TerminalError) {
      throw "$Description failed: $($result.Message)"
    }
    if ((Get-Date) -ge $Deadline) {
      $detail = if ($result -and $result.PSObject.Properties.Name -contains 'Message') { $result.Message } else { 'condition remained pending' }
      throw "Timed out waiting for $Description. Last result: $detail"
    }
    Start-Sleep -Seconds $PollSeconds
  } while ($true)
}

function Test-AvnmRecoveryManifest {
  [CmdletBinding()]
  param([Parameter(Mandatory)][System.Collections.IDictionary]$Manifest)

  $required = @(
    'SchemaVersion',
    'RunRoot',
    'WorkDirectory',
    'LogDirectory',
    'EvidenceDirectory',
    'SubscriptionId',
    'ResourceGroupName',
    'NetworkManagerName',
    'RunId'
  )
  $missing = @($required | Where-Object { -not $Manifest.Contains($_) -or [string]::IsNullOrWhiteSpace([string]$Manifest[$_]) })
  if ($missing.Count -gt 0) {
    return [pscustomobject]@{ Valid = $false; Message = "Missing manifest fields: $($missing -join ', ')" }
  }
  if ([int]$Manifest.SchemaVersion -ne 1) {
    return [pscustomobject]@{ Valid = $false; Message = "Unsupported manifest version: $($Manifest.SchemaVersion)" }
  }
  if ([string]$Manifest.SubscriptionId -notmatch '^[0-9a-fA-F-]{36}$') {
    return [pscustomobject]@{ Valid = $false; Message = 'SubscriptionId is not a GUID.' }
  }
  if ([string]$Manifest.RunRoot -notlike '*avnm-live-*') {
    return [pscustomobject]@{ Valid = $false; Message = 'RunRoot is not an AVNM live-run directory.' }
  }
  return [pscustomobject]@{ Valid = $true; Message = 'Manifest is valid.' }
}

Export-ModuleMember -Function @(
  'ConvertTo-IPv4UInt32',
  'Get-CidrRange',
  'Test-CidrContains',
  'Test-CidrOverlap',
  'Get-PlanChangeViolations',
  'Get-DeploymentDisposition',
  'Invoke-GuardedOperation',
  'Wait-AvnmCondition',
  'Test-AvnmRecoveryManifest'
)
