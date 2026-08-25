output "root_pool_id" {
  description = "Root IPAM pool ID."
  value       = azurerm_network_manager_ipam_pool.root.id
}

output "hub_pool_id" {
  description = "Hub child-pool ID."
  value       = azurerm_network_manager_ipam_pool.hub.id
}

output "workload_pool_id" {
  description = "Workload child-pool ID."
  value       = azurerm_network_manager_ipam_pool.workload.id
}

output "ids" {
  description = "All IPAM resource IDs."
  value = {
    root               = azurerm_network_manager_ipam_pool.root.id
    hub                = azurerm_network_manager_ipam_pool.hub.id
    workload           = azurerm_network_manager_ipam_pool.workload.id
    static_reservation = azurerm_network_manager_ipam_pool_static_cidr.reserved.id
  }
}
