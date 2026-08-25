# Managed routing Preview

The routing configuration uses `ManagedOnly` mode and targets the static workload-subnet group. It contains one safe teaching route:

```text
203.0.113.0/24 -> NoNextHop (Azure reports next hop None)
```

`203.0.113.0/24` is TEST-NET-3, reserved for documentation. The route therefore demonstrates managed blackholing without a virtual appliance, gateway, or meaningful application path. BGP route propagation is disabled on the collection.

Managed routing remains a Preview surface in parts of Azure CLI. Terraform uses the native AzureRM 5.2.0 routing resources; no AzAPI resource is present. The live runner waits for a managed route-table association on both workload subnets, captures the exact route-table resource IDs, and verifies each route. During teardown it waits for those associations to disappear before destroying the network and later proves the captured route resources are absent.

Azure may place routing artifacts in a subscription-wide `AVNM_Managed_ResourceGroup_*`. That resource group can be shared with unrelated AVNM configurations. The lab never deletes it and never requires it to disappear.

