variable "network_manager_id" {
  description = "Azure Virtual Network Manager ID."
  type        = string
}

variable "resource_group_id" {
  description = "Lab resource group ID used as the dynamic policy-assignment scope."
  type        = string
}

variable "location" {
  description = "Region receiving configuration deployments."
  type        = string
}

variable "name_suffix" {
  description = "Unique suffix used in AVNM component names."
  type        = string
}

variable "run_id" {
  description = "Run tag selected by the dynamic group policy."
  type        = string
}

variable "topology_mode" {
  description = "Connectivity goal state."
  type        = string
}

variable "hub_vnet_id" {
  description = "Hub VNet ID."
  type        = string
}

variable "hub_subnet_prefix" {
  description = "Actual Azure-allocated hub management subnet prefix."
  type        = string
}

variable "all_vnet_ids" {
  description = "All lab VNet IDs keyed by role."
  type        = map(string)
}

variable "workload_vnet_ids" {
  description = "App and data VNet IDs keyed by role."
  type        = map(string)
}

variable "workload_subnet_ids" {
  description = "App and data subnet IDs keyed by role."
  type        = map(string)
}

variable "workload_address_space" {
  description = "Workload IPAM child-pool prefix used by security rules."
  type        = string
}
