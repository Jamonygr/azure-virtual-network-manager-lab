# Azure Virtual Network Manager create-test-destroy lab

Build a disposable Azure Virtual Network Manager (AVNM) environment, prove its control-plane behavior, change the same environment from hub-spoke to mesh, prove the transition, and remove everything again.

The lab uses Terraform **1.15.8** and exactly **AzureRM 5.2.0**. It demonstrates native AVNM connectivity, security admin, IP address management (IPAM), and managed routing resources. There are no VMs, NICs, public IPs, firewalls, gateways, NAT, diagnostics, or Log Analytics resources.

![Lab architecture](docs/diagrams/architecture.svg)

## Run the complete lab

Prerequisites are PowerShell 7, Terraform 1.15.8, Azure CLI, Go 1.21 or newer, Pester 5, and an Azure subscription where the signed-in identity can create resource-group and subscription-scoped AVNM/policy resources. The `Microsoft.Network`, `Microsoft.PolicyInsights`, and `Microsoft.Authorization` providers must be registered. Install the Azure CLI `virtual-network-manager` and `resource-graph` extensions.

```powershell
az login
.\scripts\invoke-live-validation.ps1
```

The command creates a unique temporary work directory, applies hub-spoke, validates it, briefly undeploys Connectivity, recreates the same configuration name as mesh, validates it, commits an empty goal state, and destroys the lab. The checkout never contains live state or credentials.

Useful options:

```powershell
# Select a subscription or tune convergence polling.
.\scripts\invoke-live-validation.ps1 `
  -SubscriptionId '<subscription-guid>' `
  -Location westeurope `
  -TimeoutMinutes 45 `
  -PollSeconds 20

# Debug only: leave resources and state intact. This keeps incurring AVNM charges.
.\scripts\invoke-live-validation.ps1 -KeepResources

# Recover a failed or interrupted cleanup using the exact path printed by the runner.
.\scripts\invoke-live-validation.ps1 -CleanupRun '<temp\avnm-live-...>'
```

Do not use `-KeepResources` for normal runs. The safe recovery path needs the preserved local state; never delete the resource group or the shared `AVNM_Managed_ResourceGroup_*` as a shortcut.

## What the smoke test proves

- Azure IPAM allocates three unique, non-overlapping `/20` prefixes from the intended child pools and outside the reserved `/20`; every VNet gets a derived `/24` subnet.
- Static VNet/subnet membership and tag-policy-driven workload membership converge exactly.
- Connectivity, SecurityAdmin, and Routing deployments reach a fresh `Deployed` state.
- Hub-spoke produces four directional AVNM peering objects and no spoke-to-spoke edge.
- Mesh becomes effective on all three VNets, removes the obsolete peerings, and keeps the VNet IDs and IPAM prefixes unchanged.
- Workload VNets receive three exact security admin rules, while the hub does not.
- Workload subnets receive a managed `203.0.113.0/24 -> None` route.
- Both steady states produce a no-drift Terraform plan.
- Cleanup proves the None goal state, empty Terraform state, deleted lab resource group and policy objects, deleted captured route resources, and no remaining run-tagged resources.

These are management-plane and effective-configuration tests. They do **not** claim packet delivery, NSG interaction, NIC effective routes, or application reachability because the lab deliberately creates no workload.

## Architecture at a glance

| Area | Teaching resource | Scope |
| --- | --- | --- |
| IPAM | Root `/12`, hub `/16`, workload `/16`, reserved `/20` | AVNM |
| Networks | Hub, app, data VNets with allocated `/20`s and one `/24` each | Resource group |
| Groups | Static spokes, static all VNets, dynamic workloads, static workload subnets | AVNM |
| Connectivity | One stable name: `HubAndSpoke`, then Azure-required recreation as `Mesh` | West Europe goal state |
| Security | AlwaysAllow hub SSH; deny Internet SSH/RDP; deny outbound SMB | Dynamic workloads |
| Routing | `ManagedOnly`, TEST-NET-3 to `NoNextHop` | Workload subnets |

## Learn and extend

- [Architecture and boundaries](docs/architecture.md)
- [IPAM address plan](docs/ipam.md)
- [Network groups and dynamic membership](docs/network-groups.md)
- [Connectivity and hub-to-mesh exercise](docs/connectivity.md)
- [Security admin rules](docs/security-admin.md)
- [Managed routing Preview](docs/managed-routing.md)
- [Testing and evidence](docs/testing.md)
- [Lifecycle and safe teardown](docs/lifecycle.md)
- [Cost notes](docs/cost.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Generated Terraform reference](docs/generated/terraform.md)

## Static development checks

```powershell
.\scripts\invoke-pre-commit-check.ps1
```

GitHub Actions runs only credential-free static checks. It never logs into Azure and never runs live `terraform plan`, `apply`, or `destroy`. See [testing](docs/testing.md) and [security exceptions](SECURITY_EXCEPTIONS.md).

## License

MIT. See [LICENSE](LICENSE).
