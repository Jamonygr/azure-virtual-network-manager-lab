resource "azurerm_virtual_network" "this" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location

  ip_address_pool {
    id                     = var.ipam_pool_id
    number_of_ip_addresses = tostring(pow(2, 32 - var.vnet_prefix_length))
  }

  tags = var.tags
}

locals {
  allocated_prefix = one(azurerm_virtual_network.this.ip_address_pool[0].allocated_ip_address_prefixes)
  subnet_newbits   = var.subnet_prefix_length - var.vnet_prefix_length
}

resource "azurerm_subnet" "this" {
  name                                          = var.subnet_name
  resource_group_name                           = var.resource_group_name
  virtual_network_name                          = azurerm_virtual_network.this.name
  address_prefixes                              = [cidrsubnet(local.allocated_prefix, local.subnet_newbits, 0)]
  default_outbound_access_enabled               = false
  private_endpoint_network_policies             = "Enabled"
  private_link_service_network_policies_enabled = true
}
