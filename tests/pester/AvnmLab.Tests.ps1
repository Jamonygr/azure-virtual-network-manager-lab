BeforeAll {
  Import-Module (Join-Path $PSScriptRoot '..\..\scripts\AvnmLab.psm1') -Force
}

Describe 'CIDR contracts' {
  It 'recognizes pool containment and reservation overlap' {
    Test-CidrContains -Parent '10.240.0.0/12' -Child '10.241.0.0/16' | Should -BeTrue
    Test-CidrOverlap -Left '10.241.0.0/20' -Right '10.241.240.0/20' | Should -BeFalse
    (Get-CidrRange -Cidr '10.241.0.0/20').Size | Should -Be 4096
  }
}

Describe 'Mesh transition plan guardrail' {
  It 'allows only the connectivity configuration and deployment' {
    $plan = [pscustomobject]@{
      resource_changes = @(
        [pscustomobject]@{ address = 'module.avnm.azurerm_network_manager_connectivity_configuration.active'; change = [pscustomobject]@{ actions = @('update') } },
        [pscustomobject]@{ address = 'module.avnm.azurerm_network_manager_deployment.connectivity'; change = [pscustomobject]@{ actions = @('update') } },
        [pscustomobject]@{ address = 'module.vnet["app"].azurerm_virtual_network.this'; change = [pscustomobject]@{ actions = @('no-op') } }
      )
    }
    $violations = @(Get-PlanChangeViolations -Plan $plan -AllowedAddresses @(
      'module.avnm.azurerm_network_manager_connectivity_configuration.active',
      'module.avnm.azurerm_network_manager_deployment.connectivity'
    ))
    $violations | Should -BeNullOrEmpty
  }

  It 'rejects any IPAM or VNet replacement' {
    $plan = [pscustomobject]@{
      resource_changes = @(
        [pscustomobject]@{ address = 'module.vnet["app"].azurerm_virtual_network.this'; change = [pscustomobject]@{ actions = @('delete', 'create') } }
      )
    }
    $violations = @(Get-PlanChangeViolations -Plan $plan -AllowedAddresses @(
      'module.avnm.azurerm_network_manager_connectivity_configuration.active',
      'module.avnm.azurerm_network_manager_deployment.connectivity'
    ))
    $violations.Count | Should -Be 1
  }

  It 'rejects replacement of an allowlisted connectivity resource' {
    $plan = [pscustomobject]@{
      resource_changes = @(
        [pscustomobject]@{ address = 'module.avnm.azurerm_network_manager_connectivity_configuration.active'; change = [pscustomobject]@{ actions = @('delete', 'create') } }
      )
    }
    $violations = @(Get-PlanChangeViolations -Plan $plan -AllowedAddresses @(
      'module.avnm.azurerm_network_manager_connectivity_configuration.active'
    ))
    $violations.Count | Should -Be 1
    $violations[0] | Should -Match 'only an in-place update'
  }

  It 'allows only the explicit Azure-required connectivity recreation shape' {
    $plan = [pscustomobject]@{
      resource_changes = @(
        [pscustomobject]@{ address = 'module.avnm.azurerm_network_manager_connectivity_configuration.active'; change = [pscustomobject]@{ actions = @('delete', 'create') } },
        [pscustomobject]@{ address = 'module.avnm.azurerm_network_manager_deployment.connectivity'; change = [pscustomobject]@{ actions = @('create') } }
      )
    }
    $violations = @(Get-PlanChangeViolations -Plan $plan -AllowedAddresses @(
      'module.avnm.azurerm_network_manager_connectivity_configuration.active',
      'module.avnm.azurerm_network_manager_deployment.connectivity'
    ) -AllowedActionsByAddress @{
      'module.avnm.azurerm_network_manager_connectivity_configuration.active' = @('delete', 'create')
      'module.avnm.azurerm_network_manager_deployment.connectivity'           = @('create')
    })
    $violations | Should -BeNullOrEmpty
  }
}

Describe 'Deployment polling state machine' {
  It 'captures the bounded polling result before returning its record' {
    $runner = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\scripts\invoke-live-validation.ps1') -Raw
    $runner | Should -Match '\$result\s*=\s*Wait-AvnmCondition\s+-Description\s+"\$Type deployment"'
    $runner | Should -Match 'return\s+\$result\.Record'
  }

  It 'detects a successful current deployment' {
    $records = @([pscustomobject]@{
        deploymentStatus = 'Deployed'
        commitTime       = (Get-Date).ToUniversalTime().ToString('o')
        configurationIds = @('/config/expected')
      })
    (Get-DeploymentDisposition -Records $records -ConfigurationId '/config/expected').State | Should -Be 'Deployed'
  }

  It 'rejects a stale deployment record' {
    $records = @([pscustomobject]@{
        deploymentStatus = 'Deployed'
        commitTime       = (Get-Date).AddMinutes(-10).ToUniversalTime().ToString('o')
        configurationIds = @('/config/expected')
      })
    (Get-DeploymentDisposition -Records $records -ConfigurationId '/config/expected' -NotBefore (Get-Date).AddMinutes(-1)).State | Should -Be 'Stale'
  }

  It 'treats an Azure failure as terminal' {
    $records = @([pscustomobject]@{
        deploymentStatus = 'Failed'
        commitTime       = (Get-Date).ToUniversalTime().ToString('o')
        configurationIds = @('/config/expected')
        errorMessage     = 'policy blocked the deployment'
      })
    $result = Get-DeploymentDisposition -Records $records -ConfigurationId '/config/expected'
    $result.State | Should -Be 'Failed'
    $result.Message | Should -Match 'policy blocked'
  }

  It 'times out with the last observed condition' {
    {
      Wait-AvnmCondition -Description 'dynamic membership' -Deadline (Get-Date).AddMilliseconds(-1) -PollSeconds 0 -Probe {
        [pscustomobject]@{ Done = $false; TerminalError = $false; Message = 'app still missing' }
      }
    } | Should -Throw '*app still missing*'
  }
}

Describe 'Effective security contracts' {
  It 'correlates normalized effective rules by their resource IDs' {
    $runner = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\scripts\invoke-live-validation.ps1') -Raw
    $runner | Should -Match '\-like\s+"\*/rules/\$Name"'
    $runner | Should -Match 'Assert-SecurityRuleResources\s+-Outputs\s+\$Outputs'
    $runner | Should -Not -Match "Tokens\s*=\s*@\([^\r\n]*'100'"
  }
}

Describe 'Guaranteed cleanup' {
  It 'runs cleanup after work fails' {
    $script:cleanupCalled = $false
    { Invoke-GuardedOperation -Work { throw 'apply failed' } -Cleanup { $script:cleanupCalled = $true } } | Should -Throw '*apply failed*'
    $script:cleanupCalled | Should -BeTrue
  }

  It 'reports both work and cleanup failures' {
    { Invoke-GuardedOperation -Work { throw 'validation failed' } -Cleanup { throw 'destroy failed' } } | Should -Throw '*Cleanup also failed*'
  }
}

Describe 'Recovery manifests' {
  It 'accepts a complete version-one live-run manifest' {
    $manifest = @{
      SchemaVersion = 1
      RunRoot = 'C:\Temp\avnm-live-20260825-run1'
      WorkDirectory = 'C:\Temp\avnm-live-20260825-run1\work'
      LogDirectory = 'C:\Temp\avnm-live-20260825-run1\logs'
      EvidenceDirectory = 'C:\Temp\avnm-live-20260825-run1\evidence'
      SubscriptionId = '11111111-1111-4111-8111-111111111111'
      ResourceGroupName = 'rg-avnm-live-run1-weu'
      NetworkManagerName = 'vnm-avnm-live-run1-weu'
      RunId = 'run1'
    }
    (Test-AvnmRecoveryManifest -Manifest $manifest).Valid | Should -BeTrue
  }

  It 'rejects an incomplete recovery manifest' {
    $result = Test-AvnmRecoveryManifest -Manifest @{ SchemaVersion = 1; RunRoot = 'C:\Temp\avnm-live-run1' }
    $result.Valid | Should -BeFalse
    $result.Message | Should -Match 'Missing manifest fields'
  }
}
