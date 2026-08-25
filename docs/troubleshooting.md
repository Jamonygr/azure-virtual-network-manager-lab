# Troubleshooting

## Provider or region preflight fails

Confirm the active subscription, register `Microsoft.Network`, `Microsoft.PolicyInsights`, and `Microsoft.Authorization`, and use a region that exposes `Microsoft.Network/networkManagers`. West Europe is the default. The runner refuses to continue if an existing AVNM overlaps the same subscription and enabled access types.

## Dynamic group membership times out

Azure Policy membership is eventually consistent. Confirm app/data VNet tags contain the exact run ID and `avnm-role = workload`, the assignment is scoped to the lab resource group, and the policy mode is `Microsoft.Network.Data`. Inspect the logged Resource Graph responses in the run directory.

## A deployment is stale or failed

Open the matching `deployment-status-*` command log and evidence JSON. The runner requires the expected configuration ID, `Deployed`, and a commit time after the topology apply. A previous successful commit cannot satisfy the next stage. Azure Policy denial messages commonly explain terminal failures.

## Mesh has no peering objects

That is expected. Mesh with `DirectlyConnected` uses an AVNM connected group. The positive signal is each VNet's effective connectivity configuration; stale hub-spoke peering rows must disappear.

## Routing is slow to materialize or remove

Managed routing is eventually consistent. Keep the run directory intact. The runner captures exact route-table IDs and will not blindly delete the shared `AVNM_Managed_ResourceGroup_*`.

## IPAM pool tags appear with different casing

AVNM's IPAM API canonicalizes pool tag keys to lowercase. The IPAM module deliberately normalizes only its pool tag map so refreshes remain no-drift; other lab resources keep the shared tag casing.

## Cleanup failed or the shell was interrupted

Use the exact recovery command printed by the runner:

```powershell
.\scripts\invoke-live-validation.ps1 -CleanupRun '<run-directory>'
```

If the original terminal was killed, find `%TEMP%\avnm-live-*\run.json`, select the intended run, and pass its parent directory. Recovery reads only that manifest and local state. Do not manually delete state, the resource group, policies, or shared AVNM managed group before recovery completes.

## Static scanning reports an expected no-NSG/DDoS finding

Read [SECURITY_EXCEPTIONS.md](../SECURITY_EXCEPTIONS.md). Only the narrowly documented exceptions are accepted; new high/critical findings must be fixed or explicitly reviewed.
