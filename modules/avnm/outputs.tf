output "network_group_ids" {
  description = "Network group IDs keyed by teaching purpose."
  value = {
    spokes_static           = azurerm_network_manager_network_group.spokes_static.id
    all_vnets_static        = azurerm_network_manager_network_group.all_vnets_static.id
    workloads_dynamic       = azurerm_network_manager_network_group.workloads_dynamic.id
    workload_subnets_static = azurerm_network_manager_network_group.workload_subnets_static.id
  }
}

output "policy_ids" {
  description = "Dynamic membership policy IDs."
  value = {
    definition = azurerm_policy_definition.workload_membership.id
    assignment = azurerm_resource_group_policy_assignment.workload_membership.id
  }
}

output "configuration_ids" {
  description = "AVNM configuration IDs."
  value = {
    connectivity = azurerm_network_manager_connectivity_configuration.active.id
    security     = azurerm_network_manager_security_admin_configuration.baseline.id
    routing      = azurerm_network_manager_routing_configuration.safe.id
  }
}

output "security_rule_ids" {
  description = "Security admin rule IDs."
  value = {
    always_allow_hub_ssh    = azurerm_network_manager_admin_rule.always_allow_hub_ssh.id
    deny_inbound_management = azurerm_network_manager_admin_rule.deny_inbound_management.id
    deny_outbound_smb       = azurerm_network_manager_admin_rule.deny_outbound_smb.id
  }
}

output "routing_rule_id" {
  description = "Safe TEST-NET-3 blackhole rule ID."
  value       = azurerm_network_manager_routing_rule.test_net_blackhole.id
}
