mock_provider "azurerm" {}

variables {
  network_manager_id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/networkManagers/vnm-test"
  resource_group_id  = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test"
  location           = "westeurope"
  name_suffix        = "avnm-test-run1-weu"
  run_id             = "run1"
  hub_vnet_id        = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-hub"
  hub_subnet_prefix  = "10.240.0.0/24"
  all_vnet_ids = {
    hub  = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-hub"
    app  = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-app"
    data = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-data"
  }
  workload_vnet_ids = {
    app  = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-app"
    data = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-data"
  }
  workload_subnet_ids = {
    app  = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-app/subnets/snet-workload"
    data = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-data/subnets/snet-workload"
  }
  workload_address_space = "10.241.0.0/16"
}

run "hub_spoke_goal_state" {
  command = plan

  module {
    source = "./modules/avnm"
  }

  variables {
    topology_mode = "HubAndSpoke"
  }

  override_resource {
    target          = azurerm_network_manager_network_group.spokes_static
    override_during = plan
    values = {
      id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/networkManagers/vnm-test/networkGroups/spokes"
    }
  }

  override_resource {
    target          = azurerm_network_manager_network_group.all_vnets_static
    override_during = plan
    values = {
      id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/networkManagers/vnm-test/networkGroups/all"
    }
  }

  override_resource {
    target          = azurerm_network_manager_network_group.workloads_dynamic
    override_during = plan
    values = {
      id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/networkManagers/vnm-test/networkGroups/workloads"
    }
  }

  override_resource {
    target          = azurerm_network_manager_network_group.workload_subnets_static
    override_during = plan
    values = {
      id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/networkManagers/vnm-test/networkGroups/subnets"
    }
  }

  assert {
    condition     = azurerm_network_manager_connectivity_configuration.active.connectivity_topology == "HubAndSpoke"
    error_message = "Hub-spoke mode must use the HubAndSpoke topology."
  }

  assert {
    condition     = length(azurerm_network_manager_connectivity_configuration.active.hub) == 1
    error_message = "Hub-spoke mode must contain exactly one hub."
  }

  assert {
    condition     = one(azurerm_network_manager_connectivity_configuration.active.applies_to_group).group_connectivity == "None"
    error_message = "Hub-spoke mode must not directly connect spokes."
  }

  assert {
    condition     = one(azurerm_network_manager_connectivity_configuration.active.applies_to_group).network_group_id == azurerm_network_manager_network_group.spokes_static.id
    error_message = "Hub-spoke mode must target the static spoke group."
  }

  assert {
    condition     = jsondecode(azurerm_policy_definition.workload_membership.policy_rule).then.effect == "addToNetworkGroup"
    error_message = "Dynamic membership must use addToNetworkGroup."
  }

  assert {
    condition     = jsondecode(azurerm_policy_definition.workload_membership.policy_rule)["if"].allOf[1].field == "tags['avnm-run-id']"
    error_message = "Dynamic membership must isolate each live run by tag."
  }

  assert {
    condition = (
      azurerm_network_manager_admin_rule.always_allow_hub_ssh.action == "AlwaysAllow" &&
      azurerm_network_manager_admin_rule.always_allow_hub_ssh.priority == 100 &&
      azurerm_network_manager_admin_rule.deny_inbound_management.priority == 200 &&
      azurerm_network_manager_admin_rule.deny_outbound_smb.priority == 300
    )
    error_message = "Security rule actions and priorities must retain the documented baseline."
  }

  assert {
    condition = (
      azurerm_network_manager_routing_configuration.safe.route_table_usage_mode == "ManagedOnly" &&
      azurerm_network_manager_routing_rule_collection.workloads.bgp_route_propagation_enabled == false
    )
    error_message = "Routing must be ManagedOnly with BGP propagation disabled."
  }

  assert {
    condition = (
      azurerm_network_manager_routing_rule.test_net_blackhole.destination[0].address == "203.0.113.0/24" &&
      azurerm_network_manager_routing_rule.test_net_blackhole.next_hop[0].type == "NoNextHop" &&
      azurerm_network_manager_routing_rule.test_net_blackhole.next_hop[0].address == null
    )
    error_message = "The only route must safely blackhole TEST-NET-3 without a next-hop address."
  }

  assert {
    condition = azurerm_network_manager_deployment.connectivity.triggers.goal_state == sha256(jsonencode({
      topology                 = "HubAndSpoke"
      selected_group           = azurerm_network_manager_network_group.spokes_static.id
      hub                      = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-hub"
      group_connectivity       = "None"
      global_mesh              = false
      address_overlap          = false
      delete_existing_peerings = false
      peering_enforcement      = false
      use_hub_gateway          = false
    }))
    error_message = "The connectivity deployment must hash the complete hub-spoke goal state."
  }
}

run "mesh_goal_state" {
  command = plan

  module {
    source = "./modules/avnm"
  }

  variables {
    topology_mode = "Mesh"
  }

  override_resource {
    target          = azurerm_network_manager_network_group.spokes_static
    override_during = plan
    values = {
      id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/networkManagers/vnm-test/networkGroups/spokes"
    }
  }

  override_resource {
    target          = azurerm_network_manager_network_group.all_vnets_static
    override_during = plan
    values = {
      id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/networkManagers/vnm-test/networkGroups/all"
    }
  }

  override_resource {
    target          = azurerm_network_manager_network_group.workloads_dynamic
    override_during = plan
    values = {
      id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/networkManagers/vnm-test/networkGroups/workloads"
    }
  }

  override_resource {
    target          = azurerm_network_manager_network_group.workload_subnets_static
    override_during = plan
    values = {
      id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/networkManagers/vnm-test/networkGroups/subnets"
    }
  }

  assert {
    condition     = azurerm_network_manager_connectivity_configuration.active.connectivity_topology == "Mesh"
    error_message = "Mesh mode must use the Mesh topology."
  }

  assert {
    condition     = length(azurerm_network_manager_connectivity_configuration.active.hub) == 0
    error_message = "Mesh mode must remove the hub block."
  }

  assert {
    condition     = one(azurerm_network_manager_connectivity_configuration.active.applies_to_group).group_connectivity == "DirectlyConnected"
    error_message = "Mesh mode must enable connected-group routing."
  }

  assert {
    condition     = one(azurerm_network_manager_connectivity_configuration.active.applies_to_group).network_group_id == azurerm_network_manager_network_group.all_vnets_static.id
    error_message = "Mesh mode must target the static all-VNet group."
  }

  assert {
    condition = azurerm_network_manager_deployment.connectivity.triggers.goal_state == sha256(jsonencode({
      topology                 = "Mesh"
      selected_group           = azurerm_network_manager_network_group.all_vnets_static.id
      hub                      = null
      group_connectivity       = "DirectlyConnected"
      global_mesh              = false
      address_overlap          = false
      delete_existing_peerings = false
      peering_enforcement      = false
      use_hub_gateway          = false
    }))
    error_message = "The connectivity deployment must hash the complete mesh goal state."
  }
}
