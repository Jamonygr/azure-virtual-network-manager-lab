mock_provider "azurerm" {}

run "ipam_pool_hierarchy_and_reservation" {
  command = plan

  module {
    source = "./modules/ipam-pools"
  }

  variables {
    network_manager_id       = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/networkManagers/vnm-test"
    location                 = "westeurope"
    name_suffix              = "avnm-test-run1-weu"
    root_prefix              = "10.240.0.0/12"
    hub_prefix               = "10.240.0.0/16"
    workload_prefix          = "10.241.0.0/16"
    workload_reserved_prefix = "10.241.240.0/20"
    tags                     = { ManagedBy = "Terraform" }
  }

  assert {
    condition     = one(azurerm_network_manager_ipam_pool.root.address_prefixes) == "10.240.0.0/12"
    error_message = "The root pool must own the documented /12."
  }

  assert {
    condition     = azurerm_network_manager_ipam_pool.hub.parent_pool_name == azurerm_network_manager_ipam_pool.root.name
    error_message = "The hub pool must be a child of the root pool."
  }

  assert {
    condition     = azurerm_network_manager_ipam_pool.workload.parent_pool_name == azurerm_network_manager_ipam_pool.root.name
    error_message = "The workload pool must be a child of the root pool."
  }

  assert {
    condition     = one(azurerm_network_manager_ipam_pool_static_cidr.reserved.address_prefixes) == "10.241.240.0/20"
    error_message = "The workload pool must reserve TEST lab capacity before VNet allocation."
  }
}

run "vnet_requests_a_20_and_derives_a_24" {
  command = plan

  module {
    source = "./modules/ipam-vnet"
  }

  variables {
    name                 = "vnet-app-test"
    resource_group_name  = "rg-test"
    location             = "westeurope"
    ipam_pool_id         = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/networkManagers/vnm-test/ipamPools/workload"
    vnet_prefix_length   = 20
    subnet_name          = "snet-workload"
    subnet_prefix_length = 24
    tags                 = { "avnm-role" = "workload" }
  }

  override_resource {
    target          = azurerm_virtual_network.this
    override_during = plan
    values = {
      name = "vnet-app-test"
      ip_address_pool = {
        id                            = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-test/providers/Microsoft.Network/networkManagers/vnm-test/ipamPools/workload"
        number_of_ip_addresses        = "4096"
        allocated_ip_address_prefixes = ["10.241.0.0/20"]
      }
    }
  }

  assert {
    condition     = azurerm_virtual_network.this.ip_address_pool[0].number_of_ip_addresses == "4096"
    error_message = "A /20 request must ask IPAM for 4,096 addresses."
  }

  assert {
    condition     = azurerm_virtual_network.this.address_space == null
    error_message = "An IPAM-backed VNet must not declare a static address space."
  }

  assert {
    condition     = one(azurerm_subnet.this.address_prefixes) == "10.241.0.0/24"
    error_message = "The workload subnet must be the first /24 derived from the Azure-allocated /20."
  }

  assert {
    condition     = azurerm_subnet.this.default_outbound_access_enabled == false
    error_message = "Default outbound access must stay disabled."
  }
}
