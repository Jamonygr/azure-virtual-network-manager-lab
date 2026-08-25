data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "lab" {
  name     = "rg-${local.name_suffix}"
  location = var.location
  tags     = local.common_tags
}

resource "azurerm_network_manager" "lab" {
  name                = "vnm-${local.name_suffix}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  description         = "Disposable AVNM control-plane lab: IPAM, groups, connectivity, security, and routing"

  scope {
    subscription_ids = [data.azurerm_subscription.current.id]
  }

  scope_accesses = ["Connectivity", "SecurityAdmin", "Routing"]
  tags           = local.common_tags

  # The Network Manager resource provider normalizes tag keys, which otherwise
  # produces a perpetual plan diff after a successful apply.
  lifecycle {
    ignore_changes = [tags]
  }
}

module "ipam_pools" {
  source = "./modules/ipam-pools"

  network_manager_id       = azurerm_network_manager.lab.id
  location                 = azurerm_resource_group.lab.location
  name_suffix              = local.name_suffix
  root_prefix              = var.ipam_root_prefix
  hub_prefix               = var.ipam_hub_pool_prefix
  workload_prefix          = var.ipam_workload_pool_prefix
  workload_reserved_prefix = var.ipam_reserved_prefix
  tags                     = local.common_tags
}

module "vnet" {
  for_each = local.networks
  source   = "./modules/ipam-vnet"

  name                 = "vnet-${each.key}-${local.name_suffix}"
  resource_group_name  = azurerm_resource_group.lab.name
  location             = azurerm_resource_group.lab.location
  ipam_pool_id         = each.key == "hub" ? module.ipam_pools.hub_pool_id : module.ipam_pools.workload_pool_id
  vnet_prefix_length   = var.vnet_prefix_length
  subnet_name          = each.value.subnet_name
  subnet_prefix_length = var.subnet_prefix_length
  tags = merge(local.common_tags, {
    "avnm-role"   = each.value.role
    "avnm-run-id" = var.run_id
  })

  # The reservation must exist before app/data ask Azure for an allocation.
  depends_on = [module.ipam_pools]
}

module "avnm" {
  source = "./modules/avnm"

  network_manager_id     = azurerm_network_manager.lab.id
  resource_group_id      = azurerm_resource_group.lab.id
  location               = azurerm_resource_group.lab.location
  name_suffix            = local.name_suffix
  run_id                 = var.run_id
  topology_mode          = var.topology_mode
  hub_vnet_id            = module.vnet["hub"].id
  hub_subnet_prefix      = module.vnet["hub"].subnet_prefix
  all_vnet_ids           = { for name, network in module.vnet : name => network.id }
  workload_vnet_ids      = { for name, network in module.vnet : name => network.id if local.networks[name].role == "workload" }
  workload_subnet_ids    = { for name, network in module.vnet : name => network.subnet_id if local.networks[name].role == "workload" }
  workload_address_space = var.ipam_workload_pool_prefix
}

check "ipam_children_are_inside_root" {
  assert {
    condition = (
      local.ipam_networks.hub.first >= local.ipam_networks.root.first &&
      local.ipam_networks.hub.last <= local.ipam_networks.root.last &&
      local.ipam_networks.workload.first >= local.ipam_networks.root.first &&
      local.ipam_networks.workload.last <= local.ipam_networks.root.last
    )
    error_message = "Hub and workload IPAM pools must be contained by ipam_root_prefix."
  }
}

check "ipam_child_pools_do_not_overlap" {
  assert {
    condition = (
      local.ipam_networks.hub.last < local.ipam_networks.workload.first ||
      local.ipam_networks.workload.last < local.ipam_networks.hub.first
    )
    error_message = "Hub and workload IPAM child pools must not overlap."
  }
}

check "reservation_is_inside_workload_pool" {
  assert {
    condition = (
      local.ipam_networks.reservation.first >= local.ipam_networks.workload.first &&
      local.ipam_networks.reservation.last <= local.ipam_networks.workload.last
    )
    error_message = "ipam_reserved_prefix must be fully contained by ipam_workload_pool_prefix."
  }
}

check "allocation_sizes_fit_pools" {
  assert {
    condition = (
      var.vnet_prefix_length >= tonumber(split("/", var.ipam_hub_pool_prefix)[1]) &&
      var.vnet_prefix_length >= tonumber(split("/", var.ipam_workload_pool_prefix)[1]) &&
      var.subnet_prefix_length >= var.vnet_prefix_length
    )
    error_message = "VNet allocations must fit child pools and subnet prefixes must fit the VNet allocation."
  }
}
