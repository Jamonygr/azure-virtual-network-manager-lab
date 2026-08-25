[CmdletBinding(DefaultParameterSetName = 'Run')]
param(
  [Parameter(ParameterSetName = 'Run')]
  [string]$SubscriptionId = '',

  [Parameter(ParameterSetName = 'Run')]
  [string]$Location = 'westeurope',

  [Parameter(ParameterSetName = 'Run')]
  [ValidateRange(5, 120)]
  [int]$TimeoutMinutes = 45,

  [Parameter(ParameterSetName = 'Run')]
  [ValidateRange(5, 120)]
  [int]$PollSeconds = 20,

  [Parameter(ParameterSetName = 'Run')]
  [switch]$KeepResources,

  [Parameter(Mandatory, ParameterSetName = 'Recovery')]
  [string]$CleanupRun
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $PSScriptRoot 'AvnmLab.psm1') -Force

$script:commandCounter = 0
$script:logRoot = $null
$script:workDirectory = $null
$script:subscriptionId = $null
$script:manifest = $null
$script:manifestPath = $null

function Write-Step {
  param([Parameter(Mandatory)][string]$Message)
  Write-Host ''
  Write-Host "==> $Message" -ForegroundColor Cyan
}

function Get-LocationShort {
  param([Parameter(Mandatory)][string]$Name)
  $normalized = ($Name -replace ' ', '').ToLowerInvariant()
  $map = @{
    westeurope         = 'weu'
    northeurope        = 'neu'
    germanywestcentral = 'gwc'
    eastus             = 'eus'
    eastus2            = 'eus2'
    westus2            = 'wus2'
    centralus          = 'cus'
    uksouth            = 'uks'
  }
  if ($map.ContainsKey($normalized)) { return $map[$normalized] }
  return $normalized.Substring(0, [Math]::Min(6, $normalized.Length))
}

function Save-Manifest {
  if (-not $script:manifestPath -or -not $script:manifest) { return }
  $script:manifest.UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
  $script:manifest | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $script:manifestPath -Encoding utf8
}

function Save-Evidence {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)]$Value
  )
  $path = Join-Path $script:manifest.EvidenceDirectory "$Name.json"
  $Value | ConvertTo-Json -Depth 50 | Set-Content -LiteralPath $path -Encoding utf8
}

function Invoke-LoggedNative {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$ArgumentList,
    [string]$WorkingDirectory = $repositoryRoot,
    [int[]]$AllowedExitCodes = @(0),
    [switch]$Quiet
  )

  $script:commandCounter++
  $safeName = $Name -replace '[^A-Za-z0-9_.-]', '_'
  $logPath = Join-Path $script:logRoot ('{0:D3}-{1}.log' -f $script:commandCounter, $safeName)
  $started = Get-Date
  $captured = @()
  $exitCode = -1

  Push-Location $WorkingDirectory
  try {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $captured = & $FilePath @ArgumentList 2>&1
      $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
    }
    finally {
      $ErrorActionPreference = $previousPreference
    }
  }
  finally {
    Pop-Location
  }

  $text = ($captured | ForEach-Object { $_.ToString() }) -join "`n"
  @(
    "command=$FilePath $($ArgumentList -join ' ')"
    "startedUtc=$($started.ToUniversalTime().ToString('o'))"
    "durationSeconds=$([math]::Round(((Get-Date) - $started).TotalSeconds, 3))"
    "exitCode=$exitCode"
    '--- output ---'
    $text
  ) | Set-Content -LiteralPath $logPath -Encoding utf8

  if (-not $Quiet -and $text) { Write-Host $text }
  if ($exitCode -notin $AllowedExitCodes) {
    throw "$Name failed with exit code $exitCode. See $logPath"
  }

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output   = $text
    LogPath  = $logPath
    Duration = ((Get-Date) - $started)
  }
}

function Invoke-AzJson {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string[]]$Arguments,
    [int[]]$AllowedExitCodes = @(0),
    [switch]$AllowEmpty
  )

  $allArguments = @($Arguments) + @('--subscription', $script:subscriptionId, '--only-show-errors', '--output', 'json')
  $result = Invoke-LoggedNative -Name $Name -FilePath 'az' -ArgumentList $allArguments -WorkingDirectory $repositoryRoot -AllowedExitCodes $AllowedExitCodes -Quiet
  if (-not $result.Output) {
    if ($AllowEmpty) { return $null }
    throw "$Name returned no JSON. See $($result.LogPath)"
  }
  try { return $result.Output | ConvertFrom-Json } catch { throw "$Name returned invalid JSON. See $($result.LogPath)" }
}

function Get-TerraformOutputs {
  param([switch]$AllowFailure)
  $allowed = if ($AllowFailure) { @(0, 1) } else { @(0) }
  $result = Invoke-LoggedNative -Name 'terraform-output' -FilePath 'terraform' -ArgumentList @('output', '-json') -WorkingDirectory $script:workDirectory -AllowedExitCodes $allowed -Quiet
  if ($result.ExitCode -ne 0 -or -not $result.Output) { return $null }
  $raw = $result.Output | ConvertFrom-Json -AsHashtable
  $values = @{}
  foreach ($key in $raw.Keys) { $values[$key] = $raw[$key].value }
  return $values
}

function Initialize-RunDirectory {
  $utcStamp = Get-Date -AsUTC -Format 'yyyyMMdd-HHmmss'
  $runId = (Get-Date -AsUTC -Format 'MMddHHmmss') + ([guid]::NewGuid().ToString('N').Substring(0, 2))
  $runRoot = Join-Path ([System.IO.Path]::GetTempPath()) "avnm-live-$utcStamp-$runId"
  $work = Join-Path $runRoot 'work'
  $logs = Join-Path $runRoot 'logs'
  $evidence = Join-Path $runRoot 'evidence'
  New-Item -ItemType Directory -Force -Path $runRoot, $work, $logs, $evidence | Out-Null

  Get-ChildItem -LiteralPath $repositoryRoot -File -Filter '*.tf' | Copy-Item -Destination $work -Force
  Copy-Item -LiteralPath (Join-Path $repositoryRoot '.terraform.lock.hcl') -Destination $work -Force
  Copy-Item -LiteralPath (Join-Path $repositoryRoot 'modules') -Destination $work -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $repositoryRoot 'tests') -Destination $work -Recurse -Force

  $locationShort = Get-LocationShort -Name $Location
  $nameSuffix = "avnm-live-$runId-$locationShort"
  $script:workDirectory = $work
  $script:logRoot = $logs
  $script:manifestPath = Join-Path $runRoot 'run.json'
  $script:manifest = [ordered]@{
    SchemaVersion       = 1
    CreatedUtc          = (Get-Date).ToUniversalTime().ToString('o')
    UpdatedUtc          = $null
    RepositoryRoot      = $repositoryRoot
    RunRoot             = $runRoot
    WorkDirectory       = $work
    LogDirectory        = $logs
    EvidenceDirectory   = $evidence
    RunId               = $runId
    Location            = $Location
    LocationShort       = $locationShort
    Environment         = 'live'
    NameSuffix          = $nameSuffix
    ResourceGroupName   = "rg-$nameSuffix"
    NetworkManagerName  = "vnm-$nameSuffix"
    PolicyDefinitionName = "avnm-workloads-$nameSuffix"
    PolicyAssignmentName = "avnm-workloads-$runId"
    SubscriptionId      = $null
    HubTfVars           = Join-Path $runRoot 'hub-spoke.auto.tfvars'
    MeshTfVars          = Join-Path $runRoot 'mesh.auto.tfvars'
    LastTfVars          = $null
    LastTopology        = $null
    CleanupRequired     = $false
    CleanupVerified     = $false
    RouteTableIds       = @()
    Applied             = $false
    CompletedStages     = @()
  }
  Save-Manifest
  return $script:manifest
}

function New-LiveTfVars {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][ValidateSet('HubAndSpoke', 'Mesh')][string]$Topology
  )
  @"
environment   = "live"
run_id        = "$($script:manifest.RunId)"
location      = "$($script:manifest.Location)"
owner         = "Live-Validation"
topology_mode = "$Topology"
"@ | Set-Content -LiteralPath $Path -Encoding utf8
}

function Assert-ToolsAndAzureContext {
  Write-Step 'preflight tools, Azure context, providers, and AVNM scope'

  foreach ($command in @('terraform', 'az', 'pwsh', 'go')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "$command is required." }
  }

  $terraformVersion = Invoke-LoggedNative -Name 'terraform-version' -FilePath 'terraform' -ArgumentList @('version', '-json') -AllowedExitCodes @(0) -Quiet
  $terraformJson = $terraformVersion.Output | ConvertFrom-Json
  if ($terraformJson.terraform_version -ne '1.15.8') {
    throw "Terraform 1.15.8 is required; found $($terraformJson.terraform_version)."
  }

  $accountArgs = @('account', 'show')
  if ($SubscriptionId) { $accountArgs += @('--subscription', $SubscriptionId) }
  $accountResult = Invoke-LoggedNative -Name 'azure-account' -FilePath 'az' -ArgumentList ($accountArgs + @('--only-show-errors', '--output', 'json')) -AllowedExitCodes @(0) -Quiet
  $account = $accountResult.Output | ConvertFrom-Json
  if ($account.state -ne 'Enabled') { throw "Azure subscription $($account.name) is not enabled." }
  $script:subscriptionId = $account.id
  $script:manifest.SubscriptionId = $account.id
  Save-Manifest

  $env:ARM_SUBSCRIPTION_ID = $account.id
  $env:TF_VAR_subscription_id = $account.id

  foreach ($namespace in @('Microsoft.Network', 'Microsoft.PolicyInsights', 'Microsoft.Authorization')) {
    $provider = Invoke-AzJson -Name "provider-$namespace" -Arguments @('provider', 'show', '--namespace', $namespace)
    if ($provider.registrationState -ne 'Registered') {
      throw "$namespace must be registered before the live run. Current state: $($provider.registrationState)"
    }
  }

  foreach ($extension in @('virtual-network-manager', 'resource-graph')) {
    $extensionResult = Invoke-LoggedNative -Name "extension-$extension" -FilePath 'az' -ArgumentList @('extension', 'show', '--name', $extension, '--only-show-errors', '--output', 'json') -AllowedExitCodes @(0) -Quiet
    if (-not $extensionResult.Output) { throw "Azure CLI extension $extension is required." }
  }

  $networkProvider = Invoke-AzJson -Name 'network-provider-locations' -Arguments @('provider', 'show', '--namespace', 'Microsoft.Network')
  $managerType = @($networkProvider.resourceTypes | Where-Object { $_.resourceType -eq 'networkManagers' }) | Select-Object -First 1
  $normalizedRequested = ($Location -replace ' ', '').ToLowerInvariant()
  $supported = @($managerType.locations | Where-Object { ($_ -replace ' ', '').ToLowerInvariant() -eq $normalizedRequested })
  if ($supported.Count -eq 0) { throw "Azure Virtual Network Manager is not available in $Location for this subscription." }

  $managers = Invoke-AzJson -Name 'existing-network-managers' -Arguments @('network', 'manager', 'list')
  foreach ($manager in @($managers)) {
    $json = $manager | ConvertTo-Json -Depth 30 -Compress
    if ($json -match [regex]::Escape($account.id) -and $json -match '(?i)(Connectivity|SecurityAdmin|Routing)') {
      throw "An existing AVNM instance overlaps this subscription and enabled feature scope: $($manager.name). Use a disposable subscription or remove the conflict."
    }
  }

  Write-Host "Using subscription '$($account.name)' in $Location."
}

function Invoke-StaticPreflight {
  Write-Step 'static Terraform and script tests'
  Invoke-LoggedNative -Name 'terraform-fmt-check' -FilePath 'terraform' -ArgumentList @('fmt', '-check', '-recursive', '-diff') -WorkingDirectory $repositoryRoot | Out-Null
  Invoke-LoggedNative -Name 'terraform-init' -FilePath 'terraform' -ArgumentList @('init', '-input=false', '-lockfile=readonly') -WorkingDirectory $script:workDirectory | Out-Null
  Invoke-LoggedNative -Name 'terraform-validate' -FilePath 'terraform' -ArgumentList @('validate', '-no-color') -WorkingDirectory $script:workDirectory | Out-Null
  Invoke-LoggedNative -Name 'terraform-test' -FilePath 'terraform' -ArgumentList @('test', '-no-color') -WorkingDirectory $script:workDirectory | Out-Null
  $pesterResult = Join-Path $script:manifest.EvidenceDirectory 'pester.xml'
  Invoke-LoggedNative -Name 'pester-test' -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-File', (Join-Path $repositoryRoot 'scripts/invoke-pester-tests.ps1'), '-OutputFile', $pesterResult) -WorkingDirectory $repositoryRoot | Out-Null
  if (Test-Path -LiteralPath (Join-Path $repositoryRoot 'tests/go.mod')) {
    Invoke-LoggedNative -Name 'go-contract-tests' -FilePath 'go' -ArgumentList @('test', './...') -WorkingDirectory (Join-Path $repositoryRoot 'tests') | Out-Null
  }
}

function Invoke-TerraformPlan {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$TfVars,
    [Parameter(Mandatory)][string]$PlanPath,
    [string[]]$ExtraArguments = @()
  )
  $arguments = @('plan', '-input=false', '-no-color', "-out=$PlanPath", "-var-file=$TfVars") + @($ExtraArguments)
  Invoke-LoggedNative -Name $Name -FilePath 'terraform' -ArgumentList $arguments -WorkingDirectory $script:workDirectory | Out-Null
}

function Invoke-TerraformApply {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$PlanPath
  )
  Invoke-LoggedNative -Name $Name -FilePath 'terraform' -ArgumentList @('apply', '-input=false', '-no-color', '-auto-approve', $PlanPath) -WorkingDirectory $script:workDirectory | Out-Null
}

function Assert-NoTerraformDrift {
  param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$TfVars
  )
  $result = Invoke-LoggedNative -Name $Name -FilePath 'terraform' -ArgumentList @('plan', '-input=false', '-no-color', '-detailed-exitcode', "-var-file=$TfVars") -WorkingDirectory $script:workDirectory -AllowedExitCodes @(0, 2) -Quiet
  if ($result.ExitCode -eq 2) { throw "$Name detected Terraform drift. See $($result.LogPath)" }
}

function Assert-MeshPlanIsScoped {
  param([Parameter(Mandatory)][string]$PlanPath)
  $shown = Invoke-LoggedNative -Name 'mesh-plan-json' -FilePath 'terraform' -ArgumentList @('show', '-json', $PlanPath) -WorkingDirectory $script:workDirectory -Quiet
  $plan = $shown.Output | ConvertFrom-Json
  Save-Evidence -Name 'mesh-plan' -Value $plan
  $violations = @(Get-PlanChangeViolations -Plan $plan -AllowedAddresses @(
    'module.avnm.azurerm_network_manager_connectivity_configuration.active',
    'module.avnm.azurerm_network_manager_deployment.connectivity'
  ) -AllowedActionsByAddress @{
    'module.avnm.azurerm_network_manager_connectivity_configuration.active' = @('delete', 'create')
    'module.avnm.azurerm_network_manager_deployment.connectivity'           = @('create')
  })
  if ($violations.Count -gt 0) {
    throw "Mesh transition changes resources outside AVNM connectivity: $($violations -join '; ')"
  }
}

function Wait-ConnectivityRemovedForTransition {
  param([Parameter(Mandatory)]$Outputs)

  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  Wait-AvnmCondition -Description 'temporary Connectivity None goal state before Mesh' -Deadline $deadline -PollSeconds $PollSeconds -Probe {
    $remaining = [System.Collections.Generic.List[string]]::new()
    $snapshots = [ordered]@{ deployment = $null; effective = @{}; peerings = @{} }
    try {
      $records = Get-DeploymentRecords -Type Connectivity
      $snapshots.deployment = $records
      if (@($records | Where-Object { @($_.configurationIds).Count -gt 0 }).Count -gt 0) { $remaining.Add('Connectivity deployment goal state') }
    }
    catch { $remaining.Add('Connectivity deployment query') }

    foreach ($role in @('hub', 'app', 'data')) {
      try {
        $effective = Get-EffectiveConnectivity -VnetName $Outputs.virtual_network_names[$role]
        $snapshots.effective[$role] = $effective
        if (($effective | ConvertTo-Json -Depth 40 -Compress) -match [regex]::Escape($Outputs.configuration_ids.connectivity)) { $remaining.Add("$role effective connectivity") }
      }
      catch { $remaining.Add("$role effective connectivity query") }
      try {
        $peerings = @(Get-VnetPeerings -VnetName $Outputs.virtual_network_names[$role])
        $snapshots.peerings[$role] = $peerings
        if ($peerings.Count -ne 0) { $remaining.Add("$role peering rows") }
      }
      catch { $remaining.Add("$role peering query") }
    }

    if ($remaining.Count -eq 0) {
      Save-Evidence -Name 'connectivity-none-before-mesh' -Value $snapshots
      return [pscustomobject]@{ Done = $true; TerminalError = $false; Message = 'Connectivity is fully undeployed.' }
    }
    return [pscustomobject]@{ Done = $false; TerminalError = $false; Message = ($remaining -join ', ') }
  } | Out-Null
}

function Invoke-ConnectivityUndeployForMesh {
  param([Parameter(Mandatory)]$Outputs)

  Write-Step 'undeploy the immutable hub-spoke connectivity shape before mesh'
  Invoke-LoggedNative -Name 'terraform-undeploy-connectivity-for-mesh' -FilePath 'terraform' -ArgumentList @(
    'destroy', '-input=false', '-no-color', '-auto-approve',
    '-target=module.avnm.azurerm_network_manager_deployment.connectivity',
    "-var-file=$($script:manifest.HubTfVars)"
  ) -WorkingDirectory $script:workDirectory | Out-Null
  Wait-ConnectivityRemovedForTransition -Outputs $Outputs
  $script:manifest.CompletedStages += 'connectivity-none-before-mesh'
  Save-Manifest
}

function Get-DeploymentRecords {
  param([Parameter(Mandatory)][ValidateSet('Connectivity', 'SecurityAdmin', 'Routing')][string]$Type)
  # The virtual-network-manager CLI extension currently rejects Routing in
  # list-deploy-status even though the ARM API and post-commit support it.
  # Use the common ARM endpoint for all three types so polling has one schema.
  $bodyPath = Join-Path $script:manifest.RunRoot "deployment-$Type.json"
  @{ regions = @($script:manifest.Location); deploymentTypes = @($Type) } |
    ConvertTo-Json -Compress |
    Set-Content -LiteralPath $bodyPath -Encoding ascii -NoNewline
  $uri = "https://management.azure.com$($script:manifest.NetworkManagerId)/listDeploymentStatus?api-version=2025-01-01"
  $result = Invoke-AzJson -Name "deployment-status-$Type" -Arguments @(
    'rest', '--method', 'post', '--uri', $uri,
    '--body', "@$bodyPath", '--headers', 'Content-Type=application/json'
  )
  return @($result.value)
}

function Wait-Deployment {
  param(
    [Parameter(Mandatory)][ValidateSet('Connectivity', 'SecurityAdmin', 'Routing')][string]$Type,
    [Parameter(Mandatory)][string]$ConfigurationId,
    [datetime]$NotBefore = [datetime]::MinValue
  )
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  $result = Wait-AvnmCondition -Description "$Type deployment" -Deadline $deadline -PollSeconds $PollSeconds -Probe {
    $records = Get-DeploymentRecords -Type $Type
    $disposition = Get-DeploymentDisposition -Records $records -ConfigurationId $ConfigurationId -NotBefore $NotBefore
    if ($disposition.State -eq 'Failed') {
      return [pscustomobject]@{ Done = $false; TerminalError = $true; Message = $disposition.Message }
    }
    if ($disposition.State -eq 'Deployed') {
      $configurationIds = @($disposition.Record.configurationIds)
      if ($configurationIds.Count -ne 1 -or $configurationIds[0] -ne $ConfigurationId) {
        return [pscustomobject]@{ Done = $false; TerminalError = $true; Message = "Unexpected $Type goal-state IDs: $($configurationIds -join ', ')" }
      }
      $stage = ([string]$script:manifest.LastTopology).ToLowerInvariant()
      Save-Evidence -Name "deployment-$($Type.ToLowerInvariant())-$stage" -Value $records
      return [pscustomobject]@{ Done = $true; TerminalError = $false; Message = 'Deployed'; Record = $disposition.Record }
    }
    return [pscustomobject]@{ Done = $false; TerminalError = $false; Message = $disposition.Message }
  }
  return $result.Record
}

function Find-RuleJsonObjects {
  param(
    [Parameter(Mandatory)]$InputObject,
    [Parameter(Mandatory)][string]$Name
  )

  $found = [System.Collections.Generic.List[object]]::new()
  function Visit-Value {
    param($Value)
    if ($null -eq $Value -or $Value -is [string] -or $Value.GetType().IsPrimitive) { return }

    if ($Value -is [System.Collections.IDictionary]) {
      $nameKey = @($Value.Keys | Where-Object { [string]$_ -ieq 'name' }) | Select-Object -First 1
      $idKey = @($Value.Keys | Where-Object { [string]$_ -ieq 'id' }) | Select-Object -First 1
      if (($nameKey -and [string]$Value[$nameKey] -eq $Name) -or
        ($idKey -and [string]$Value[$idKey] -like "*/rules/$Name")) { $found.Add($Value) }
      foreach ($item in $Value.Values) { Visit-Value -Value $item }
      return
    }
    if ($Value -is [System.Collections.IEnumerable]) {
      foreach ($item in $Value) { Visit-Value -Value $item }
      return
    }

    $properties = @($Value.PSObject.Properties)
    $nameProperty = $properties | Where-Object { $_.Name -ieq 'name' } | Select-Object -First 1
    $idProperty = $properties | Where-Object { $_.Name -ieq 'id' } | Select-Object -First 1
    if (($nameProperty -and [string]$nameProperty.Value -eq $Name) -or
      ($idProperty -and [string]$idProperty.Value -like "*/rules/$Name")) { $found.Add($Value) }
    foreach ($property in $properties) { Visit-Value -Value $property.Value }
  }
  Visit-Value -Value $InputObject
  return @($found)
}

function Test-EffectiveRuleSemantics {
  param(
    [Parameter(Mandatory)]$Snapshot,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string[]]$RequiredTokens
  )

  foreach ($candidate in @(Find-RuleJsonObjects -InputObject $Snapshot -Name $Name)) {
    $json = $candidate | ConvertTo-Json -Depth 30 -Compress
    $missing = @($RequiredTokens | Where-Object { $json -notmatch [regex]::Escape($_) })
    if ($missing.Count -eq 0) { return $true }
  }
  return $false
}

function Get-ResponseValueCount {
  param([Parameter(Mandatory)]$Snapshot)

  if ($Snapshot -is [System.Collections.IDictionary]) {
    $valueKey = @($Snapshot.Keys | Where-Object { [string]$_ -ieq 'value' }) | Select-Object -First 1
    if ($valueKey) { return @($Snapshot[$valueKey]).Count }
  }
  $valueProperty = @($Snapshot.PSObject.Properties | Where-Object { $_.Name -ieq 'value' }) | Select-Object -First 1
  if ($valueProperty) { return @($valueProperty.Value).Count }
  return @($Snapshot).Count
}

function Assert-ExactStringSet {
  param(
    [Parameter(Mandatory)][string]$Label,
    [AllowEmptyCollection()][string[]]$Actual = @(),
    [AllowEmptyCollection()][string[]]$Expected = @()
  )

  $actualText = (@($Actual) | Sort-Object) -join ','
  $expectedText = (@($Expected) | Sort-Object) -join ','
  if ($actualText -cne $expectedText) {
    throw "$Label was '$actualText'; expected '$expectedText'."
  }
}

function Assert-SecurityRuleResources {
  param([Parameter(Mandatory)]$Outputs)

  $expectations = [ordered]@{
    always_allow_hub_ssh = @{
      Name = 'always-allow-hub-ssh'; Access = 'AlwaysAllow'; Direction = 'Inbound'; Priority = 100; Protocol = 'Tcp'
      Ports = @('22'); Sources = @([string]$Outputs.subnet_prefixes.hub); Destinations = @('10.241.0.0/16')
    }
    deny_inbound_management = @{
      Name = 'deny-inbound-internet-management'; Access = 'Deny'; Direction = 'Inbound'; Priority = 200; Protocol = 'Tcp'
      Ports = @('22', '3389'); Sources = @('Internet'); Destinations = @('10.241.0.0/16')
    }
    deny_outbound_smb = @{
      Name = 'deny-outbound-smb'; Access = 'Deny'; Direction = 'Outbound'; Priority = 300; Protocol = 'Tcp'
      Ports = @('445'); Sources = @('10.241.0.0/16'); Destinations = @('Internet')
    }
  }
  $snapshots = [ordered]@{}
  foreach ($key in $expectations.Keys) {
    $expected = $expectations[$key]
    $rule = Invoke-AzJson -Name "security-rule-resource-$key" -Arguments @(
      'resource', 'show', '--ids', [string]$Outputs.security_rule_ids[$key], '--api-version', '2024-05-01'
    )
    $snapshots[$key] = $rule
    $properties = $rule.properties
    foreach ($propertyName in @('access', 'direction', 'protocol', 'provisioningState')) {
      $expectedValue = if ($propertyName -eq 'provisioningState') { 'Succeeded' } else { $expected[$propertyName.Substring(0, 1).ToUpperInvariant() + $propertyName.Substring(1)] }
      if ([string]$properties.$propertyName -cne [string]$expectedValue) {
        throw "$($expected.Name) $propertyName was '$($properties.$propertyName)'; expected '$expectedValue'."
      }
    }
    if ([int]$properties.priority -ne [int]$expected.Priority) {
      throw "$($expected.Name) priority was '$($properties.priority)'; expected '$($expected.Priority)'."
    }
    if ([string]$rule.name -cne [string]$expected.Name) {
      throw "Security rule resource name was '$($rule.name)'; expected '$($expected.Name)'."
    }
    Assert-ExactStringSet -Label "$($expected.Name) destination ports" -Actual @($properties.destinationPortRanges) -Expected $expected.Ports
    Assert-ExactStringSet -Label "$($expected.Name) sources" -Actual @($properties.sources | ForEach-Object { $_.addressPrefix }) -Expected $expected.Sources
    Assert-ExactStringSet -Label "$($expected.Name) destinations" -Actual @($properties.destinations | ForEach-Object { $_.addressPrefix }) -Expected $expected.Destinations
  }
  Save-Evidence -Name 'security-rule-resources' -Value $snapshots
}

function Get-MembershipData {
  $query = "networkresources | where type =~ 'microsoft.network/networkgroupmemberships' | project id, properties"
  $result = Invoke-AzJson -Name 'network-group-memberships' -Arguments @('graph', 'query', '--graph-query', $query, '--first', '1000')
  return @($result.data)
}

function Test-MembershipRecord {
  param(
    [Parameter(Mandatory)]$Records,
    [Parameter(Mandatory)][string]$TargetId,
    [Parameter(Mandatory)][string]$GroupId
  )
  foreach ($record in @($Records)) {
    $json = $record | ConvertTo-Json -Depth 30 -Compress
    if ([string]$record.id -like "$TargetId*" -and $json -match [regex]::Escape($GroupId)) { return $true }
  }
  return $false
}

function Wait-NetworkGroupMembership {
  param([Parameter(Mandatory)]$Outputs)
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  Wait-AvnmCondition -Description 'static and dynamic network-group membership' -Deadline $deadline -PollSeconds $PollSeconds -Probe {
    $records = Get-MembershipData
    $groups = $Outputs.network_group_ids
    $vnets = $Outputs.virtual_network_ids
    $subnets = $Outputs.subnet_ids
    $missing = [System.Collections.Generic.List[string]]::new()

    foreach ($role in @('hub', 'app', 'data')) {
      if (-not (Test-MembershipRecord -Records $records -TargetId $vnets[$role] -GroupId $groups.all_vnets_static)) { $missing.Add("$role -> all-vnets-static") }
    }
    foreach ($role in @('app', 'data')) {
      if (-not (Test-MembershipRecord -Records $records -TargetId $vnets[$role] -GroupId $groups.spokes_static)) { $missing.Add("$role -> spokes-static") }
      if (-not (Test-MembershipRecord -Records $records -TargetId $vnets[$role] -GroupId $groups.workloads_dynamic)) { $missing.Add("$role -> workloads-dynamic") }
      if (-not (Test-MembershipRecord -Records $records -TargetId $subnets[$role] -GroupId $groups.workload_subnets_static)) { $missing.Add("$role subnet -> workload-subnets-static") }
    }
    if (Test-MembershipRecord -Records $records -TargetId $vnets.hub -GroupId $groups.workloads_dynamic) {
      return [pscustomobject]@{ Done = $false; TerminalError = $true; Message = 'The hub incorrectly joined the dynamic workload group.' }
    }

    if ($missing.Count -eq 0) {
      Save-Evidence -Name 'network-group-memberships' -Value $records
      return [pscustomobject]@{ Done = $true; TerminalError = $false; Message = 'All expected memberships are present.' }
    }
    return [pscustomobject]@{ Done = $false; TerminalError = $false; Message = ($missing -join ', ') }
  } | Out-Null
}

function Assert-IpamAndSubnets {
  param([Parameter(Mandatory)]$Outputs)
  $prefixes = $Outputs.allocated_vnet_prefixes
  $subnets = $Outputs.subnet_prefixes
  $roles = @('hub', 'app', 'data')
  $unique = @($roles | ForEach-Object { $prefixes[$_] } | Sort-Object -Unique)
  if ($unique.Count -ne 3) { throw "IPAM did not return three unique VNet prefixes: $($unique -join ', ')" }

  foreach ($role in $roles) {
    $range = Get-CidrRange -Cidr $prefixes[$role]
    if ($range.PrefixLength -ne 20) { throw "$role received $($prefixes[$role]); expected a /20." }
    $parent = if ($role -eq 'hub') { '10.240.0.0/16' } else { '10.241.0.0/16' }
    if (-not (Test-CidrContains -Parent $parent -Child $prefixes[$role])) { throw "$role prefix $($prefixes[$role]) is outside $parent." }
    if ((Get-CidrRange -Cidr $subnets[$role]).PrefixLength -ne 24 -or -not (Test-CidrContains -Parent $prefixes[$role] -Child $subnets[$role])) {
      throw "$role subnet $($subnets[$role]) is not a /24 inside $($prefixes[$role])."
    }
  }

  foreach ($pair in @(@('hub', 'app'), @('hub', 'data'), @('app', 'data'))) {
    if (Test-CidrOverlap -Left $prefixes[$pair[0]] -Right $prefixes[$pair[1]]) { throw "IPAM allocations overlap: $($pair -join ' and ')" }
  }
  foreach ($role in @('app', 'data')) {
    if (Test-CidrOverlap -Left $prefixes[$role] -Right '10.241.240.0/20') { throw "$role allocation overlaps the static reservation." }
  }
  Save-Evidence -Name 'ipam-prefixes' -Value @{ vnets = $prefixes; subnets = $subnets; reservation = '10.241.240.0/20' }
}

function Get-EffectiveConnectivity {
  param([Parameter(Mandatory)][string]$VnetName)
  return Invoke-AzJson -Name "effective-connectivity-$VnetName" -Arguments @('network', 'manager', 'list-effective-connectivity-config', '--resource-group', $script:manifest.ResourceGroupName, '--virtual-network-name', $VnetName)
}

function Get-EffectiveSecurity {
  param([Parameter(Mandatory)][string]$VnetName)
  return Invoke-AzJson -Name "effective-security-$VnetName" -Arguments @('network', 'manager', 'list-effective-security-admin-rule', '--resource-group', $script:manifest.ResourceGroupName, '--virtual-network-name', $VnetName)
}

function Wait-EffectiveConnectivity {
  param(
    [Parameter(Mandatory)]$Outputs,
    [Parameter(Mandatory)][ValidateSet('HubAndSpoke', 'Mesh')][string]$Topology
  )
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  $configId = $Outputs.configuration_ids.connectivity
  Wait-AvnmCondition -Description "$Topology effective connectivity" -Deadline $deadline -PollSeconds $PollSeconds -Probe {
    $snapshots = @{}
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($role in @('hub', 'app', 'data')) {
      $snapshot = Get-EffectiveConnectivity -VnetName $Outputs.virtual_network_names[$role]
      $snapshots[$role] = $snapshot
      $json = $snapshot | ConvertTo-Json -Depth 40 -Compress
      if ($json -notmatch [regex]::Escape($configId) -or $json -notmatch [regex]::Escape($Topology)) { $missing.Add($role) }
    }
    if ($missing.Count -eq 0) {
      Save-Evidence -Name "effective-connectivity-$($Topology.ToLowerInvariant())" -Value $snapshots
      return [pscustomobject]@{ Done = $true; TerminalError = $false; Message = 'Effective on all VNets.' }
    }
    return [pscustomobject]@{ Done = $false; TerminalError = $false; Message = "Missing on: $($missing -join ', ')" }
  } | Out-Null
}

function Wait-EffectiveSecurity {
  param([Parameter(Mandatory)]$Outputs)
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  $configId = $Outputs.configuration_ids.security
  Wait-AvnmCondition -Description 'effective workload security admin rules' -Deadline $deadline -PollSeconds $PollSeconds -Probe {
    $snapshots = @{}
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($role in @('app', 'data')) {
      $snapshot = Get-EffectiveSecurity -VnetName $Outputs.virtual_network_names[$role]
      $snapshots[$role] = $snapshot
      $json = $snapshot | ConvertTo-Json -Depth 50 -Compress
      if ($json -notmatch [regex]::Escape($configId)) { $missing.Add("$role config") }
      $expectedRules = @(
        @{ Name = 'always-allow-hub-ssh'; Tokens = @('AlwaysAllow', 'Inbound', 'Tcp', '22', [string]$Outputs.subnet_prefixes.hub, '10.241.0.0/16', 'Succeeded') },
        @{ Name = 'deny-inbound-internet-management'; Tokens = @('Deny', 'Inbound', 'Tcp', '22', '3389', 'Internet', '10.241.0.0/16', 'Succeeded') },
        @{ Name = 'deny-outbound-smb'; Tokens = @('Deny', 'Outbound', 'Tcp', '445', 'Internet', '10.241.0.0/16', 'Succeeded') }
      )
      foreach ($rule in $expectedRules) {
        if (-not (Test-EffectiveRuleSemantics -Snapshot $snapshot -Name $rule.Name -RequiredTokens $rule.Tokens)) { $missing.Add("$role $($rule.Name) semantics") }
      }
      if ((Get-ResponseValueCount -Snapshot $snapshot) -ne 3) { $missing.Add("$role exact rule count") }
    }
    $hub = Get-EffectiveSecurity -VnetName $Outputs.virtual_network_names.hub
    $hubJson = $hub | ConvertTo-Json -Depth 30 -Compress
    if ($hubJson -match [regex]::Escape($configId)) {
      return [pscustomobject]@{ Done = $false; TerminalError = $true; Message = 'The workload security configuration incorrectly applies to the hub.' }
    }
    if ((Get-ResponseValueCount -Snapshot $hub) -ne 0) {
      return [pscustomobject]@{ Done = $false; TerminalError = $true; Message = 'The hub unexpectedly has effective security admin rules.' }
    }
    $snapshots.hub = $hub
    if ($missing.Count -eq 0) {
      Save-Evidence -Name 'effective-security' -Value $snapshots
      return [pscustomobject]@{ Done = $true; TerminalError = $false; Message = 'All rules are effective on workloads only.' }
    }
    return [pscustomobject]@{ Done = $false; TerminalError = $false; Message = ($missing -join ', ') }
  } | Out-Null
  Assert-SecurityRuleResources -Outputs $Outputs
}

function Get-VnetPeerings {
  param([Parameter(Mandatory)][string]$VnetName)
  return @(Invoke-AzJson -Name "peerings-$VnetName" -Arguments @('network', 'vnet', 'peering', 'list', '--resource-group', $script:manifest.ResourceGroupName, '--vnet-name', $VnetName))
}

function Wait-HubSpokePeerings {
  param([Parameter(Mandatory)]$Outputs)
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  Wait-AvnmCondition -Description 'hub-spoke peering graph' -Deadline $deadline -PollSeconds $PollSeconds -Probe {
    $graph = @{}
    foreach ($role in @('hub', 'app', 'data')) { $graph[$role] = @(Get-VnetPeerings -VnetName $Outputs.virtual_network_names[$role]) }
    $hub = @($graph.hub)
    $app = @($graph.app)
    $data = @($graph.data)
    $all = @($hub + $app + $data)
    $connected = @($all | Where-Object { $_.peeringState -eq 'Connected' -and $_.provisioningState -eq 'Succeeded' })
    $hubTargets = @($hub | ForEach-Object { $_.remoteVirtualNetwork.id })
    $appTargets = @($app | ForEach-Object { $_.remoteVirtualNetwork.id })
    $dataTargets = @($data | ForEach-Object { $_.remoteVirtualNetwork.id })
    $correct = (
      $hub.Count -eq 2 -and $app.Count -eq 1 -and $data.Count -eq 1 -and $connected.Count -eq 4 -and
      $Outputs.virtual_network_ids.app -in $hubTargets -and $Outputs.virtual_network_ids.data -in $hubTargets -and
      $Outputs.virtual_network_ids.hub -in $appTargets -and $Outputs.virtual_network_ids.hub -in $dataTargets -and
      $Outputs.virtual_network_ids.data -notin $appTargets -and $Outputs.virtual_network_ids.app -notin $dataTargets
    )
    if ($correct) {
      Save-Evidence -Name 'hub-spoke-peerings' -Value $graph
      return [pscustomobject]@{ Done = $true; TerminalError = $false; Message = 'Exact four-direction graph is connected.' }
    }
    return [pscustomobject]@{ Done = $false; TerminalError = $false; Message = "Counts hub=$($hub.Count), app=$($app.Count), data=$($data.Count), connected=$($connected.Count)" }
  } | Out-Null
}

function Wait-NoPeerings {
  param([Parameter(Mandatory)]$Outputs)
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  Wait-AvnmCondition -Description 'removal of obsolete AVNM peerings' -Deadline $deadline -PollSeconds $PollSeconds -Probe {
    $graph = @{}
    $count = 0
    foreach ($role in @('hub', 'app', 'data')) {
      $graph[$role] = @(Get-VnetPeerings -VnetName $Outputs.virtual_network_names[$role])
      $count += @($graph[$role]).Count
    }
    if ($count -eq 0) {
      Save-Evidence -Name 'mesh-peerings-empty' -Value $graph
      return [pscustomobject]@{ Done = $true; TerminalError = $false; Message = 'No VNet peering rows remain.' }
    }
    return [pscustomobject]@{ Done = $false; TerminalError = $false; Message = "$count peering rows remain." }
  } | Out-Null
}

function Get-SubnetResource {
  param(
    [Parameter(Mandatory)]$Outputs,
    [Parameter(Mandatory)][string]$Role
  )
  return Invoke-AzJson -Name "subnet-$Role" -Arguments @('network', 'vnet', 'subnet', 'show', '--resource-group', $script:manifest.ResourceGroupName, '--vnet-name', $Outputs.virtual_network_names[$Role], '--name', 'snet-workload')
}

function Wait-ManagedRoutes {
  param([Parameter(Mandatory)]$Outputs)
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  Wait-AvnmCondition -Description 'managed TEST-NET route materialization' -Deadline $deadline -PollSeconds $PollSeconds -Probe {
    $snapshot = @{}
    $routeIds = [System.Collections.Generic.List[string]]::new()
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($role in @('app', 'data')) {
      $subnet = Get-SubnetResource -Outputs $Outputs -Role $role
      $routeTableId = [string]$subnet.routeTable.id
      if (-not $routeTableId) { $missing.Add("$role route-table association"); continue }
      $segments = $routeTableId -split '/'
      $routeTableName = $segments[-1]
      $routeTableRg = $segments[[Array]::IndexOf($segments, 'resourceGroups') + 1]
      $routes = Invoke-AzJson -Name "managed-routes-$role" -Arguments @('network', 'route-table', 'route', 'list', '--resource-group', $routeTableRg, '--route-table-name', $routeTableName)
      $matching = @($routes | Where-Object { $_.addressPrefix -eq '203.0.113.0/24' -and $_.nextHopType -eq 'None' -and -not $_.nextHopIpAddress })
      if ($matching.Count -ne 1 -or @($routes).Count -ne 1) { $missing.Add("$role exact TEST-NET-3 -> None route") }
      $snapshot[$role] = @{ subnet = $subnet.id; routeTable = $routeTableId; routes = $routes }
      $routeIds.Add($routeTableId)
    }
    if ($missing.Count -eq 0) {
      $script:manifest.RouteTableIds = @($routeIds | Sort-Object -Unique)
      Save-Manifest
      Save-Evidence -Name 'managed-routes' -Value $snapshot
      return [pscustomobject]@{ Done = $true; TerminalError = $false; Message = 'Safe route is materialized on both workload subnets.' }
    }
    return [pscustomobject]@{ Done = $false; TerminalError = $false; Message = ($missing -join ', ') }
  } | Out-Null
}

function Assert-StableInfrastructure {
  param(
    [Parameter(Mandatory)]$Before,
    [Parameter(Mandatory)]$After
  )
  foreach ($key in @('virtual_network_ids', 'allocated_vnet_prefixes', 'subnet_ids')) {
    $left = $Before[$key] | ConvertTo-Json -Depth 20 -Compress
    $right = $After[$key] | ConvertTo-Json -Depth 20 -Compress
    if ($left -ne $right) { throw "$key changed during the in-place topology transition." }
  }
  foreach ($key in @('connectivity', 'security', 'routing')) {
    if ($Before.configuration_ids[$key] -ne $After.configuration_ids[$key]) { throw "$key configuration ID changed during the topology transition." }
  }
}

function Invoke-TopologyValidation {
  param(
    [Parameter(Mandatory)]$Outputs,
    [Parameter(Mandatory)][ValidateSet('HubAndSpoke', 'Mesh')][string]$Topology,
    [datetime]$ConnectivityNotBefore = [datetime]::MinValue
  )
  Write-Step "wait for $Topology control-plane convergence"
  $connectivityRecord = Wait-Deployment -Type Connectivity -ConfigurationId $Outputs.configuration_ids.connectivity -NotBefore $ConnectivityNotBefore
  $null = Wait-Deployment -Type SecurityAdmin -ConfigurationId $Outputs.configuration_ids.security
  $null = Wait-Deployment -Type Routing -ConfigurationId $Outputs.configuration_ids.routing
  Wait-NetworkGroupMembership -Outputs $Outputs
  Wait-EffectiveConnectivity -Outputs $Outputs -Topology $Topology
  Wait-EffectiveSecurity -Outputs $Outputs
  Wait-ManagedRoutes -Outputs $Outputs
  if ($Topology -eq 'HubAndSpoke') { Wait-HubSpokePeerings -Outputs $Outputs } else { Wait-NoPeerings -Outputs $Outputs }
  return $connectivityRecord
}

function Invoke-EmptyGoalStateFallback {
  param([Parameter(Mandatory)]$Outputs)
  Write-Host 'Terraform undeploy failed; posting an explicit empty AVNM goal state as fallback.' -ForegroundColor Yellow
  foreach ($type in @('Connectivity', 'SecurityAdmin', 'Routing')) {
    Invoke-AzJson -Name "empty-goal-$type" -Arguments @(
      'network', 'manager', 'post-commit',
      '--resource-group', $script:manifest.ResourceGroupName,
      '--name', $script:manifest.NetworkManagerName,
      '--commit-type', $type,
      '--target-locations', $script:manifest.Location,
      '--configuration-ids', '[]'
    ) -AllowEmpty | Out-Null
  }
}

function Wait-GoalStateRemoved {
  param([Parameter(Mandatory)]$Outputs)
  $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
  Wait-AvnmCondition -Description 'None goal state on all lab VNets and subnets' -Deadline $deadline -PollSeconds $PollSeconds -Probe {
    $remaining = [System.Collections.Generic.List[string]]::new()
    foreach ($type in @('Connectivity', 'SecurityAdmin', 'Routing')) {
      try {
        $records = Get-DeploymentRecords -Type $type
        $activeRecords = @($records | Where-Object { @($_.configurationIds).Count -gt 0 })
        if ($activeRecords.Count -gt 0) { $remaining.Add("$type deployment goal state") }
      }
      catch { $remaining.Add("$type deployment query") }
    }
    foreach ($role in @('hub', 'app', 'data')) {
      try {
        $connectivity = Get-EffectiveConnectivity -VnetName $Outputs.virtual_network_names[$role]
        if (($connectivity | ConvertTo-Json -Depth 40 -Compress) -match [regex]::Escape($Outputs.configuration_ids.connectivity)) { $remaining.Add("$role connectivity") }
      }
      catch { $remaining.Add("$role connectivity query") }
      if ($role -ne 'hub') {
        try {
          $security = Get-EffectiveSecurity -VnetName $Outputs.virtual_network_names[$role]
          if (($security | ConvertTo-Json -Depth 40 -Compress) -match [regex]::Escape($Outputs.configuration_ids.security)) { $remaining.Add("$role security") }
        }
        catch { $remaining.Add("$role security query") }
        try {
          $subnet = Get-SubnetResource -Outputs $Outputs -Role $role
          $routeTableProperty = $subnet.PSObject.Properties['routeTable']
          if ($routeTableProperty -and $routeTableProperty.Value -and $routeTableProperty.Value.id) { $remaining.Add("$role route table") }
        }
        catch { $remaining.Add("$role subnet query") }
      }
    }
    if ($remaining.Count -eq 0) { return [pscustomobject]@{ Done = $true; TerminalError = $false; Message = 'All effective configurations are absent.' } }
    return [pscustomobject]@{ Done = $false; TerminalError = $false; Message = ($remaining -join ', ') }
  } | Out-Null
}

function Invoke-LabCleanup {
  Write-Step 'undeploy AVNM goal state and destroy the disposable lab'
  $outputs = Get-TerraformOutputs -AllowFailure
  if ($outputs -and $outputs.network_manager -and $outputs.network_manager.id) {
    $script:manifest.NetworkManagerId = $outputs.network_manager.id
    Save-Manifest
  }
  $tfvars = [string]$script:manifest.LastTfVars
  if (-not $tfvars -or -not (Test-Path -LiteralPath $tfvars)) { $tfvars = [string]$script:manifest.MeshTfVars }

  $stateResult = Invoke-LoggedNative -Name 'state-before-cleanup' -FilePath 'terraform' -ArgumentList @('state', 'list') -WorkingDirectory $script:workDirectory -AllowedExitCodes @(0, 1) -Quiet
  if ($stateResult.ExitCode -eq 0 -and $stateResult.Output) {
    $deploymentAddresses = @(
      'module.avnm.azurerm_network_manager_deployment.connectivity',
      'module.avnm.azurerm_network_manager_deployment.security',
      'module.avnm.azurerm_network_manager_deployment.routing'
    )
    $stateAddresses = @($stateResult.Output -split "`r?`n" | Where-Object { $_ })
    $hasDeploymentState = @($deploymentAddresses | Where-Object { $_ -in $stateAddresses }).Count -gt 0

    if ($hasDeploymentState) {
      $undeployFailed = $false
      try {
        Invoke-LoggedNative -Name 'terraform-undeploy-goal-state' -FilePath 'terraform' -ArgumentList @(
          'destroy', '-input=false', '-no-color', '-auto-approve',
          '-target=module.avnm.azurerm_network_manager_deployment.connectivity',
          '-target=module.avnm.azurerm_network_manager_deployment.security',
          '-target=module.avnm.azurerm_network_manager_deployment.routing',
          "-var-file=$tfvars"
        ) -WorkingDirectory $script:workDirectory | Out-Null
      }
      catch {
        $undeployFailed = $true
        Write-Warning $_.Exception.Message
      }

      if ($undeployFailed -and $outputs) { Invoke-EmptyGoalStateFallback -Outputs $outputs }
      if ($outputs) { Wait-GoalStateRemoved -Outputs $outputs }
    }

    Invoke-LoggedNative -Name 'terraform-destroy' -FilePath 'terraform' -ArgumentList @('destroy', '-input=false', '-no-color', '-auto-approve', "-var-file=$tfvars") -WorkingDirectory $script:workDirectory | Out-Null
  }

  $stateAfter = Invoke-LoggedNative -Name 'state-after-destroy' -FilePath 'terraform' -ArgumentList @('state', 'list') -WorkingDirectory $script:workDirectory -AllowedExitCodes @(0, 1) -Quiet
  if ($stateAfter.ExitCode -eq 0 -and $stateAfter.Output) { throw "Terraform state is not empty after destroy: $($stateAfter.Output)" }

  $deleteDeadline = (Get-Date).AddMinutes([Math]::Min($TimeoutMinutes, 15))
  Wait-AvnmCondition -Description 'lab resource-group deletion' -Deadline $deleteDeadline -PollSeconds $PollSeconds -Probe {
    $existsResult = Invoke-LoggedNative -Name 'resource-group-exists' -FilePath 'az' -ArgumentList @('group', 'exists', '--name', $script:manifest.ResourceGroupName, '--subscription', $script:subscriptionId, '--only-show-errors') -AllowedExitCodes @(0) -Quiet
    return $existsResult.Output.Trim() -eq 'false'
  } | Out-Null

  foreach ($routeTableId in @($script:manifest.RouteTableIds)) {
    $routeResult = Invoke-LoggedNative -Name 'route-table-deleted' -FilePath 'az' -ArgumentList @('resource', 'show', '--ids', $routeTableId, '--subscription', $script:subscriptionId, '--only-show-errors', '--output', 'none') -AllowedExitCodes @(0, 1, 3) -Quiet
    if ($routeResult.ExitCode -eq 0) { throw "AVNM-managed route table still exists after destroy: $routeTableId" }
  }

  $definition = Invoke-LoggedNative -Name 'policy-definition-deleted' -FilePath 'az' -ArgumentList @('policy', 'definition', 'show', '--name', $script:manifest.PolicyDefinitionName, '--subscription', $script:subscriptionId, '--only-show-errors', '--output', 'none') -AllowedExitCodes @(0, 1, 3) -Quiet
  if ($definition.ExitCode -eq 0) { throw "Subscription policy definition still exists: $($script:manifest.PolicyDefinitionName)" }

  $assignmentScope = "/subscriptions/$($script:subscriptionId)/resourceGroups/$($script:manifest.ResourceGroupName)"
  $assignment = Invoke-LoggedNative -Name 'policy-assignment-deleted' -FilePath 'az' -ArgumentList @('policy', 'assignment', 'show', '--name', $script:manifest.PolicyAssignmentName, '--scope', $assignmentScope, '--subscription', $script:subscriptionId, '--only-show-errors', '--output', 'none') -AllowedExitCodes @(0, 1, 3) -Quiet
  if ($assignment.ExitCode -eq 0) { throw "Resource-group policy assignment still exists: $($script:manifest.PolicyAssignmentName)" }

  $query = "resources | where tostring(tags.RunId) =~ '$($script:manifest.RunId)' or tostring(tags.runId) =~ '$($script:manifest.RunId)' | project id"
  Wait-AvnmCondition -Description 'run-tag residue removal' -Deadline $deleteDeadline -PollSeconds $PollSeconds -Probe {
    $tagged = Invoke-AzJson -Name 'run-tag-cleanup-query' -Arguments @('graph', 'query', '--graph-query', $query, '--first', '1000')
    if (@($tagged.data).Count -eq 0) { return $true }
    return [pscustomobject]@{ Done = $false; TerminalError = $false; Message = "$(@($tagged.data).Count) tagged resources remain" }
  } | Out-Null

  $script:manifest.CleanupRequired = $false
  $script:manifest.CleanupVerified = $true
  $script:manifest.CompletedStages += 'destroy-verified'
  Save-Manifest

  foreach ($pattern in @('*.tfplan', '*.tfstate', '*.tfstate.backup', '*.auto.tfvars')) {
    Get-ChildItem -LiteralPath $script:manifest.RunRoot -Filter $pattern -File -ErrorAction SilentlyContinue | Remove-Item -Force
    Get-ChildItem -LiteralPath $script:workDirectory -Filter $pattern -File -ErrorAction SilentlyContinue | Remove-Item -Force
  }
  $resolvedWork = (Resolve-Path -LiteralPath $script:workDirectory).Path
  $resolvedRun = (Resolve-Path -LiteralPath $script:manifest.RunRoot).Path
  if ([IO.Path]::GetDirectoryName($resolvedWork) -ne $resolvedRun -or [IO.Path]::GetFileName($resolvedWork) -ne 'work') {
    throw "Refusing to remove unexpected successful-run work directory: $resolvedWork"
  }
  Remove-Item -LiteralPath $resolvedWork -Recurse -Force
  Write-Host "Cleanup verified. Evidence and logs remain at $($script:manifest.RunRoot)"
}

function Invoke-RecoveryCleanup {
  $resolved = (Resolve-Path -LiteralPath $CleanupRun).Path
  $manifestPath = if ((Get-Item -LiteralPath $resolved).PSIsContainer) { Join-Path $resolved 'run.json' } else { $resolved }
  if (-not (Test-Path -LiteralPath $manifestPath)) { throw "Recovery manifest not found: $manifestPath" }
  $loaded = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -AsHashtable
  $manifestCheck = Test-AvnmRecoveryManifest -Manifest $loaded
  if (-not $manifestCheck.Valid) { throw "Invalid recovery manifest: $($manifestCheck.Message)" }
  $script:manifest = $loaded
  $script:manifestPath = $manifestPath
  $script:workDirectory = $loaded.WorkDirectory
  $script:logRoot = $loaded.LogDirectory
  $script:subscriptionId = $loaded.SubscriptionId
  $existingLogNumbers = @(Get-ChildItem -LiteralPath $script:logRoot -File -ErrorAction SilentlyContinue | ForEach-Object {
      if ($_.BaseName -match '^(\d+)-') { [int]$Matches[1] }
    })
  if ($existingLogNumbers.Count -gt 0) { $script:commandCounter = [int](($existingLogNumbers | Measure-Object -Maximum).Maximum) }
  if (-not (Test-Path -LiteralPath $script:workDirectory)) { throw "Recovery work directory is missing: $($script:workDirectory)" }
  $env:ARM_SUBSCRIPTION_ID = $script:subscriptionId
  $env:TF_VAR_subscription_id = $script:subscriptionId
  Invoke-LabCleanup
}

if ($PSCmdlet.ParameterSetName -eq 'Recovery') {
  Invoke-RecoveryCleanup
  return
}

$workFailure = $null
$cleanupFailure = $null
Initialize-RunDirectory | Out-Null

try {
  Assert-ToolsAndAzureContext
  Invoke-StaticPreflight

  New-LiveTfVars -Path $script:manifest.HubTfVars -Topology HubAndSpoke
  New-LiveTfVars -Path $script:manifest.MeshTfVars -Topology Mesh
  Save-Manifest

  $hubPlan = Join-Path $script:manifest.RunRoot 'hub-spoke.tfplan'
  Write-Step 'plan and apply hub-spoke goal state'
  Invoke-TerraformPlan -Name 'plan-hub-spoke' -TfVars $script:manifest.HubTfVars -PlanPath $hubPlan
  $script:manifest.CleanupRequired = $true
  $script:manifest.LastTfVars = $script:manifest.HubTfVars
  $script:manifest.LastTopology = 'HubAndSpoke'
  Save-Manifest
  $hubCommitStart = (Get-Date).ToUniversalTime().AddSeconds(-5)
  Invoke-TerraformApply -Name 'apply-hub-spoke' -PlanPath $hubPlan
  $script:manifest.Applied = $true
  $script:manifest.CompletedStages += 'hub-spoke-applied'
  Save-Manifest

  $hubOutputs = Get-TerraformOutputs
  $script:manifest.NetworkManagerId = $hubOutputs.network_manager.id
  Save-Manifest
  Save-Evidence -Name 'outputs-hub-spoke' -Value $hubOutputs
  Assert-IpamAndSubnets -Outputs $hubOutputs
  $hubConnectivityRecord = Invoke-TopologyValidation -Outputs $hubOutputs -Topology HubAndSpoke -ConnectivityNotBefore $hubCommitStart
  Assert-NoTerraformDrift -Name 'no-drift-hub-spoke' -TfVars $script:manifest.HubTfVars
  $script:manifest.CompletedStages += 'hub-spoke-validated'
  Save-Manifest

  $meshPlan = Join-Path $script:manifest.RunRoot 'mesh.tfplan'
  Invoke-ConnectivityUndeployForMesh -Outputs $hubOutputs
  Write-Step 'recreate the stable connectivity name with the mesh shape'
  Invoke-TerraformPlan -Name 'plan-mesh-transition' -TfVars $script:manifest.MeshTfVars -PlanPath $meshPlan -ExtraArguments @(
    '-replace=module.avnm.azurerm_network_manager_connectivity_configuration.active'
  )
  Assert-MeshPlanIsScoped -PlanPath $meshPlan
  $script:manifest.LastTfVars = $script:manifest.MeshTfVars
  $script:manifest.LastTopology = 'Mesh'
  Save-Manifest
  $hubCommitText = $hubConnectivityRecord.commitTime
  if (-not $hubCommitText) { $hubCommitText = $hubConnectivityRecord.deploymentTime }
  if (-not $hubCommitText) { throw 'The hub-spoke deployment record has no commit timestamp.' }
  $meshCommitStart = ([datetime]$hubCommitText).ToUniversalTime().AddTicks(1)
  Invoke-TerraformApply -Name 'apply-mesh-transition' -PlanPath $meshPlan
  $script:manifest.CompletedStages += 'mesh-applied'
  Save-Manifest

  $meshOutputs = Get-TerraformOutputs
  Save-Evidence -Name 'outputs-mesh' -Value $meshOutputs
  Assert-StableInfrastructure -Before $hubOutputs -After $meshOutputs
  $null = Invoke-TopologyValidation -Outputs $meshOutputs -Topology Mesh -ConnectivityNotBefore $meshCommitStart
  Assert-NoTerraformDrift -Name 'no-drift-mesh' -TfVars $script:manifest.MeshTfVars
  $script:manifest.CompletedStages += 'mesh-validated'
  Save-Manifest

  Write-Host ''
  Write-Host 'Hub-spoke and mesh control-plane smoke tests passed.' -ForegroundColor Green
}
catch {
  $workFailure = $_
  Write-Error -ErrorRecord $_ -ErrorAction Continue
}
finally {
  if ($script:manifest.CleanupRequired) {
    if ($KeepResources) {
      Write-Warning "-KeepResources was specified. Azure resources and billable AVNM configurations remain active."
      Write-Warning "Recover with: .\scripts\invoke-live-validation.ps1 -CleanupRun '$($script:manifest.RunRoot)'"
      Save-Manifest
    }
    else {
      try { Invoke-LabCleanup } catch { $cleanupFailure = $_; Write-Error -ErrorRecord $_ -ErrorAction Continue }
    }
  }
}

if ($workFailure -and $cleanupFailure) {
  throw "Live validation failed: $($workFailure.Exception.Message)`nCleanup also failed: $($cleanupFailure.Exception.Message)`nRecover with: .\scripts\invoke-live-validation.ps1 -CleanupRun '$($script:manifest.RunRoot)'"
}
if ($workFailure) { throw $workFailure }
if ($cleanupFailure) {
  throw "Live validation passed, but cleanup could not be proven: $($cleanupFailure.Exception.Message)`nRecover with: .\scripts\invoke-live-validation.ps1 -CleanupRun '$($script:manifest.RunRoot)'"
}

if (-not $KeepResources) {
  Write-Host 'Create -> hub-spoke test -> mesh test -> destroy completed successfully.' -ForegroundColor Green
}
