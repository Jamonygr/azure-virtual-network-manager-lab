# Static and dynamic network groups deliberately coexist so the lab can compare
# deterministic membership with policy-driven membership.
resource "azurerm_network_manager_network_group" "spokes_static" {
  name               = "ng-spokes-static-${var.name_suffix}"
  network_manager_id = var.network_manager_id
  description        = "Static app and data VNet members used by hub-spoke connectivity"
  member_type        = "VirtualNetwork"
}

resource "azurerm_network_manager_network_group" "all_vnets_static" {
  name               = "ng-all-vnets-static-${var.name_suffix}"
  network_manager_id = var.network_manager_id
  description        = "Static hub, app, and data VNet members used by mesh connectivity"
  member_type        = "VirtualNetwork"
}

resource "azurerm_network_manager_network_group" "workloads_dynamic" {
  name               = "ng-workloads-dynamic-${var.name_suffix}"
  network_manager_id = var.network_manager_id
  description        = "Policy-selected app and data VNets used by security admin rules"
  member_type        = "VirtualNetwork"
}

resource "azurerm_network_manager_network_group" "workload_subnets_static" {
  name               = "ng-workload-subnets-${var.name_suffix}"
  network_manager_id = var.network_manager_id
  description        = "Static app and data subnet members used by managed routing"
  member_type        = "Subnet"
}

resource "azurerm_network_manager_static_member" "spokes" {
  for_each = var.workload_vnet_ids

  name                      = "sm-spoke-${each.key}-${var.name_suffix}"
  network_group_id          = azurerm_network_manager_network_group.spokes_static.id
  target_virtual_network_id = each.value
}

resource "azurerm_network_manager_static_member" "all_vnets" {
  for_each = var.all_vnet_ids

  name                      = "sm-all-${each.key}-${var.name_suffix}"
  network_group_id          = azurerm_network_manager_network_group.all_vnets_static.id
  target_virtual_network_id = each.value
}

resource "azurerm_network_manager_static_member" "workload_subnets" {
  for_each = var.workload_subnet_ids

  name                      = "sm-subnet-${each.key}-${var.name_suffix}"
  network_group_id          = azurerm_network_manager_network_group.workload_subnets_static.id
  target_virtual_network_id = each.value
}

resource "azurerm_policy_definition" "workload_membership" {
  name         = "avnm-workloads-${var.name_suffix}"
  policy_type  = "Custom"
  mode         = "Microsoft.Network.Data"
  display_name = "AVNM dynamic workload membership (${var.run_id})"
  description  = "Adds only run-tagged workload VNets to the dynamic AVNM security group."

  metadata = jsonencode({
    category = "Azure Virtual Network Manager"
    version  = "1.0.0"
  })

  policy_rule = jsonencode({
    "if" = {
      allOf = [
        {
          field  = "type"
          equals = "Microsoft.Network/virtualNetworks"
        },
        {
          field  = "tags['avnm-run-id']"
          equals = var.run_id
        },
        {
          field  = "tags['avnm-role']"
          equals = "workload"
        }
      ]
    }
    "then" = {
      effect = "addToNetworkGroup"
      details = {
        networkGroupId = azurerm_network_manager_network_group.workloads_dynamic.id
      }
    }
  })
}

resource "azurerm_resource_group_policy_assignment" "workload_membership" {
  name                 = "avnm-workloads-${var.run_id}"
  display_name         = "AVNM dynamic workloads (${var.run_id})"
  description          = "Limits dynamic membership to tagged VNets in this disposable lab resource group."
  resource_group_id    = var.resource_group_id
  policy_definition_id = azurerm_policy_definition.workload_membership.id
  enforce              = true
}

# Azure locks ConnectivityTopology after creation. The runner briefly undeploys
# Connectivity and replaces this resource with the same Azure name for Mesh.
resource "azurerm_network_manager_connectivity_configuration" "active" {
  name                  = "cc-active-${var.name_suffix}"
  network_manager_id    = var.network_manager_id
  connectivity_topology = var.topology_mode
  description           = "Stable connectivity goal state switched between hub-spoke and mesh"

  connected_group_address_overlap_enabled = false
  connected_group_private_endpoints_scale = "Standard"
  delete_existing_peering_enabled         = false
  global_mesh_enabled                     = false
  peering_enforcement_enabled             = false

  applies_to_group {
    group_connectivity  = var.topology_mode == "Mesh" ? "DirectlyConnected" : "None"
    network_group_id    = var.topology_mode == "Mesh" ? azurerm_network_manager_network_group.all_vnets_static.id : azurerm_network_manager_network_group.spokes_static.id
    global_mesh_enabled = false
    use_hub_gateway     = false
  }

  dynamic "hub" {
    for_each = var.topology_mode == "HubAndSpoke" ? [1] : []

    content {
      resource_id   = var.hub_vnet_id
      resource_type = "Microsoft.Network/virtualNetworks"
    }
  }
}

resource "azurerm_network_manager_security_admin_configuration" "baseline" {
  name               = "sac-baseline-${var.name_suffix}"
  network_manager_id = var.network_manager_id
  description        = "Central workload security baseline for the control-plane lab"
}

resource "azurerm_network_manager_admin_rule_collection" "workloads" {
  name                            = "arc-workloads-${var.name_suffix}"
  security_admin_configuration_id = azurerm_network_manager_security_admin_configuration.baseline.id
  network_group_ids               = [azurerm_network_manager_network_group.workloads_dynamic.id]
  description                     = "Rules applied to policy-selected workload VNets"
}

resource "azurerm_network_manager_admin_rule" "always_allow_hub_ssh" {
  name                     = "always-allow-hub-ssh"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.workloads.id
  action                   = "AlwaysAllow"
  direction                = "Inbound"
  priority                 = 100
  protocol                 = "Tcp"
  destination_port_ranges  = ["22"]
  description              = "Guarantee the narrow hub management SSH path before NSG evaluation"

  source {
    address_prefix_type = "IPPrefix"
    address_prefix      = var.hub_subnet_prefix
  }

  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = var.workload_address_space
  }
}

resource "azurerm_network_manager_admin_rule" "deny_inbound_management" {
  name                     = "deny-inbound-internet-management"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.workloads.id
  action                   = "Deny"
  direction                = "Inbound"
  priority                 = 200
  protocol                 = "Tcp"
  destination_port_ranges  = ["22", "3389"]
  description              = "Block Internet-originated SSH and RDP across workload VNets"

  source {
    address_prefix_type = "ServiceTag"
    address_prefix      = "Internet"
  }

  destination {
    address_prefix_type = "IPPrefix"
    address_prefix      = var.workload_address_space
  }
}

resource "azurerm_network_manager_admin_rule" "deny_outbound_smb" {
  name                     = "deny-outbound-smb"
  admin_rule_collection_id = azurerm_network_manager_admin_rule_collection.workloads.id
  action                   = "Deny"
  direction                = "Outbound"
  priority                 = 300
  protocol                 = "Tcp"
  destination_port_ranges  = ["445"]
  description              = "Block Internet-bound SMB from workload VNets"

  source {
    address_prefix_type = "IPPrefix"
    address_prefix      = var.workload_address_space
  }

  destination {
    address_prefix_type = "ServiceTag"
    address_prefix      = "Internet"
  }
}

resource "azurerm_network_manager_routing_configuration" "safe" {
  name                   = "rc-safe-${var.name_suffix}"
  network_manager_id     = var.network_manager_id
  description            = "ManagedOnly routing demonstration without an appliance"
  route_table_usage_mode = "ManagedOnly"
}

resource "azurerm_network_manager_routing_rule_collection" "workloads" {
  name                          = "rrc-workloads-${var.name_suffix}"
  routing_configuration_id      = azurerm_network_manager_routing_configuration.safe.id
  network_group_ids             = [azurerm_network_manager_network_group.workload_subnets_static.id]
  bgp_route_propagation_enabled = false
  description                   = "Safe route applied only to app and data subnets"
}

resource "azurerm_network_manager_routing_rule" "test_net_blackhole" {
  name               = "drop-test-net-3"
  rule_collection_id = azurerm_network_manager_routing_rule_collection.workloads.id
  description        = "Blackhole RFC 5737 TEST-NET-3 without changing real traffic paths"

  destination {
    type    = "AddressPrefix"
    address = "203.0.113.0/24"
  }

  next_hop {
    type = "NoNextHop"
  }
}

locals {
  connectivity_goal_state = {
    topology                 = var.topology_mode
    selected_group           = var.topology_mode == "Mesh" ? azurerm_network_manager_network_group.all_vnets_static.id : azurerm_network_manager_network_group.spokes_static.id
    hub                      = var.topology_mode == "HubAndSpoke" ? var.hub_vnet_id : null
    group_connectivity       = var.topology_mode == "Mesh" ? "DirectlyConnected" : "None"
    global_mesh              = false
    address_overlap          = false
    delete_existing_peerings = false
    peering_enforcement      = false
    use_hub_gateway          = false
  }

  security_goal_state = {
    group = azurerm_network_manager_network_group.workloads_dynamic.id
    rules = [
      {
        name        = "always-allow-hub-ssh"
        action      = "AlwaysAllow"
        direction   = "Inbound"
        priority    = 100
        protocol    = "Tcp"
        source      = var.hub_subnet_prefix
        destination = var.workload_address_space
        ports       = ["22"]
      },
      {
        name        = "deny-inbound-internet-management"
        action      = "Deny"
        direction   = "Inbound"
        priority    = 200
        protocol    = "Tcp"
        source      = "Internet"
        destination = var.workload_address_space
        ports       = ["22", "3389"]
      },
      {
        name        = "deny-outbound-smb"
        action      = "Deny"
        direction   = "Outbound"
        priority    = 300
        protocol    = "Tcp"
        source      = var.workload_address_space
        destination = "Internet"
        ports       = ["445"]
      }
    ]
  }

  routing_goal_state = {
    group            = azurerm_network_manager_network_group.workload_subnets_static.id
    usage_mode       = "ManagedOnly"
    bgp_propagation  = false
    destination_type = "AddressPrefix"
    destination      = "203.0.113.0/24"
    next_hop         = "NoNextHop"
  }
}

resource "azurerm_network_manager_deployment" "connectivity" {
  network_manager_id = var.network_manager_id
  location           = var.location
  scope_access       = "Connectivity"
  configuration_ids  = [azurerm_network_manager_connectivity_configuration.active.id]

  triggers = {
    goal_state = sha256(jsonencode(local.connectivity_goal_state))
  }

  depends_on = [
    azurerm_network_manager_static_member.spokes,
    azurerm_network_manager_static_member.all_vnets
  ]
}

resource "azurerm_network_manager_deployment" "security" {
  network_manager_id = var.network_manager_id
  location           = var.location
  scope_access       = "SecurityAdmin"
  configuration_ids  = [azurerm_network_manager_security_admin_configuration.baseline.id]

  triggers = {
    goal_state = sha256(jsonencode(local.security_goal_state))
  }

  depends_on = [
    azurerm_resource_group_policy_assignment.workload_membership,
    azurerm_network_manager_admin_rule.always_allow_hub_ssh,
    azurerm_network_manager_admin_rule.deny_inbound_management,
    azurerm_network_manager_admin_rule.deny_outbound_smb
  ]
}

resource "azurerm_network_manager_deployment" "routing" {
  network_manager_id = var.network_manager_id
  location           = var.location
  scope_access       = "Routing"
  configuration_ids  = [azurerm_network_manager_routing_configuration.safe.id]

  triggers = {
    goal_state = sha256(jsonencode(local.routing_goal_state))
  }

  depends_on = [
    azurerm_network_manager_static_member.workload_subnets,
    azurerm_network_manager_routing_rule.test_net_blackhole
  ]
}
