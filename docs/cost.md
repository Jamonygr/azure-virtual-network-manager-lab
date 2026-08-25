# Cost notes

Azure Virtual Network Manager can charge for each managed VNet while a deployed configuration is active. The exact amount depends on region, feature, and current Azure pricing. The lab keeps only three small VNets and tears them down after validation, but a slow or interrupted run can continue to incur charges.

IPAM active-IP charges should remain zero because no NICs or IP configurations are created. The lab also avoids compute, Firewall, NAT, gateways, public IPs, Log Analytics ingestion, and reachability-analysis runs.

Before running, review the current [Azure Virtual Network Manager pricing FAQ](https://learn.microsoft.com/azure/virtual-network-manager/faq). Use `-KeepResources` only for debugging and immediately run the printed recovery command afterward.

