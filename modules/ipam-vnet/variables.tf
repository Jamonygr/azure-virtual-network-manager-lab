variable "name" {
  description = "Virtual network name."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group name."
  type        = string
}

variable "location" {
  description = "Azure region."
  type        = string
}

variable "ipam_pool_id" {
  description = "IPAM pool from which the VNet requests an allocation."
  type        = string
}

variable "vnet_prefix_length" {
  description = "Requested VNet prefix length."
  type        = number
}

variable "subnet_name" {
  description = "Name of the single control-plane demonstration subnet."
  type        = string
}

variable "subnet_prefix_length" {
  description = "Derived subnet prefix length."
  type        = number
}

variable "tags" {
  description = "Tags applied to the VNet."
  type        = map(string)
}
