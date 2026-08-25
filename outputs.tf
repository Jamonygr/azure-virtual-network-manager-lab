output "subscription_id" {
  description = "Azure subscription used by the lab."
  value       = data.azurerm_subscription.current.subscription_id
}

output "location" {
  description = "Region receiving the AVNM goal state."
  value       = azurerm_resource_group.lab.location
}

output "run_id" {
  description = "Run identifier used for resource isolation."
  value       = var.run_id
}

output "topology_mode" {
  description = "Current AVNM connectivity goal state."
  value       = var.topology_mode
}

output "resource_group" {
  description = "Lab resource group name and ID."
  value = {
    name = azurerm_resource_group.lab.name
    id   = azurerm_resource_group.lab.id
  }
}

output "network_manager" {
  description = "AVNM resource name and ID."
  value = {
    name = azurerm_network_manager.lab.name
    id   = azurerm_network_manager.lab.id
  }
}

output "ipam_pool_ids" {
  description = "IPAM pool and static-reservation IDs."
  value       = module.ipam_pools.ids
}

output "allocated_vnet_prefixes" {
  description = "Azure-allocated VNet prefixes keyed by role."
  value       = { for name, network in module.vnet : name => network.allocated_prefix }
}

output "virtual_network_ids" {
  description = "Virtual network IDs keyed by role."
  value       = { for name, network in module.vnet : name => network.id }
}

output "virtual_network_names" {
  description = "Virtual network names keyed by role."
  value       = { for name, network in module.vnet : name => network.name }
}

output "subnet_ids" {
  description = "Subnet IDs keyed by VNet role."
  value       = { for name, network in module.vnet : name => network.subnet_id }
}

output "subnet_prefixes" {
  description = "Derived subnet prefixes keyed by VNet role."
  value       = { for name, network in module.vnet : name => network.subnet_prefix }
}

output "network_group_ids" {
  description = "AVNM network group IDs keyed by teaching purpose."
  value       = module.avnm.network_group_ids
}

output "policy_ids" {
  description = "Dynamic-membership policy definition and assignment IDs."
  value       = module.avnm.policy_ids
}

output "configuration_ids" {
  description = "Connectivity, security, and routing configuration IDs."
  value       = module.avnm.configuration_ids
}

output "security_rule_ids" {
  description = "Security admin rule IDs keyed by rule name."
  value       = module.avnm.security_rule_ids
}

output "routing_rule_id" {
  description = "Safe TEST-NET blackhole routing-rule ID."
  value       = module.avnm.routing_rule_id
}
