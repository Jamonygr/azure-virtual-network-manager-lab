package main

import rego.v1

forbidden_types := {
  "azurerm_linux_virtual_machine",
  "azurerm_windows_virtual_machine",
  "azurerm_network_interface",
  "azurerm_public_ip",
  "azurerm_firewall",
  "azurerm_virtual_network_gateway",
  "azurerm_nat_gateway",
  "azurerm_log_analytics_workspace",
  "azurerm_monitor_diagnostic_setting",
  "azurerm_virtual_network_peering",
  "azurerm_route_table",
}

deny contains message if {
  some change in input.resource_changes
  change.type in forbidden_types
  message := sprintf("%s uses forbidden resource type %s", [change.address, change.type])
}

deny contains message if {
  some change in input.resource_changes
  startswith(change.type, "azapi_")
  message := sprintf("%s uses AzAPI; this lab requires native AzureRM resources", [change.address])
}

deny contains message if {
  some change in input.resource_changes
  change.type == "azurerm_network_manager_routing_rule"
  after := change.change.after
  after.destination[0].address != "203.0.113.0/24"
  message := sprintf("%s routes a prefix other than TEST-NET-3", [change.address])
}

deny contains message if {
  some change in input.resource_changes
  change.type == "azurerm_network_manager_routing_rule"
  after := change.change.after
  after.next_hop[0].type != "NoNextHop"
  message := sprintf("%s must use NoNextHop", [change.address])
}

