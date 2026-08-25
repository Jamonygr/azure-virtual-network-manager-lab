variable "network_manager_id" {
  description = "Parent Azure Virtual Network Manager ID."
  type        = string
}

variable "location" {
  description = "Azure region for the IPAM pools."
  type        = string
}

variable "name_suffix" {
  description = "Unique suffix for pool names."
  type        = string
}

variable "root_prefix" {
  description = "Root IPAM prefix."
  type        = string
}

variable "hub_prefix" {
  description = "Hub child-pool prefix."
  type        = string
}

variable "workload_prefix" {
  description = "Workload child-pool prefix."
  type        = string
}

variable "workload_reserved_prefix" {
  description = "Static CIDR reserved inside the workload child pool."
  type        = string
}

variable "tags" {
  description = "Tags applied to IPAM pools."
  type        = map(string)
}
