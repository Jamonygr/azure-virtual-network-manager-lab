output "id" {
  description = "Virtual network ID."
  value       = azurerm_virtual_network.this.id
}

output "name" {
  description = "Virtual network name."
  value       = azurerm_virtual_network.this.name
}

output "allocated_prefix" {
  description = "Azure-allocated VNet prefix."
  value       = local.allocated_prefix
}

output "subnet_id" {
  description = "Derived subnet ID."
  value       = azurerm_subnet.this.id
}

output "subnet_prefix" {
  description = "Derived subnet prefix."
  value       = one(azurerm_subnet.this.address_prefixes)
}
