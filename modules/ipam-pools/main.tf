locals {
  # The AVNM IPAM API returns tag keys in lowercase. Normalize at this module
  # boundary so a refresh does not create perpetual case-only tag drift.
  ipam_tags = { for key, value in var.tags : lower(key) => value }
}

resource "azurerm_network_manager_ipam_pool" "root" {
  name               = "ipam-root-${var.name_suffix}"
  network_manager_id = var.network_manager_id
  location           = var.location
  display_name       = "Lab-root-address-space"
  description        = "Root pool for the disposable AVNM control-plane lab"
  address_prefixes   = [var.root_prefix]
  tags               = local.ipam_tags
}

resource "azurerm_network_manager_ipam_pool" "hub" {
  name               = "ipam-hub-${var.name_suffix}"
  network_manager_id = var.network_manager_id
  location           = var.location
  display_name       = "Hub-allocations"
  description        = "Child pool used by the hub virtual network"
  address_prefixes   = [var.hub_prefix]
  parent_pool_name   = azurerm_network_manager_ipam_pool.root.name
  tags               = local.ipam_tags
}

resource "azurerm_network_manager_ipam_pool" "workload" {
  name               = "ipam-workload-${var.name_suffix}"
  network_manager_id = var.network_manager_id
  location           = var.location
  display_name       = "Workload-allocations"
  description        = "Child pool used by app and data virtual networks"
  address_prefixes   = [var.workload_prefix]
  parent_pool_name   = azurerm_network_manager_ipam_pool.root.name
  tags               = local.ipam_tags

  # Azure updates the parent pool's allocation metadata when a child is
  # created. Serializing siblings avoids intermittent 412 ETag races.
  depends_on = [azurerm_network_manager_ipam_pool.hub]
}

resource "azurerm_network_manager_ipam_pool_static_cidr" "reserved" {
  name             = "reserved-${var.name_suffix}"
  ipam_pool_id     = azurerm_network_manager_ipam_pool.workload.id
  address_prefixes = [var.workload_reserved_prefix]
}
