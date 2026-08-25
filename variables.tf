variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use ARM_SUBSCRIPTION_ID or the active Azure CLI subscription."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = var.subscription_id == null ? true : (
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", trimspace(var.subscription_id))) &&
      trimspace(var.subscription_id) != "00000000-0000-0000-0000-000000000000"
    )
    error_message = "subscription_id must be a non-zero GUID or null."
  }
}

variable "project" {
  description = "Short project name used in Azure resource names."
  type        = string
  default     = "avnm"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,12}$", var.project))
    error_message = "project must contain 3-12 lowercase letters, numbers, or hyphens."
  }
}

variable "environment" {
  description = "Environment label used in resource names and tags."
  type        = string
  default     = "lab"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,12}$", var.environment))
    error_message = "environment must contain 2-12 lowercase letters, numbers, or hyphens."
  }
}

variable "run_id" {
  description = "Run-specific identifier that isolates dynamic membership and disposable resources."
  type        = string
  default     = "manual"

  validation {
    condition     = can(regex("^[a-z0-9]{4,12}$", var.run_id))
    error_message = "run_id must contain 4-12 lowercase letters or numbers."
  }
}

variable "location" {
  description = "Azure region for the complete lab and all AVNM deployments."
  type        = string
  default     = "westeurope"

  validation {
    condition     = length(trimspace(var.location)) > 0
    error_message = "location cannot be empty."
  }
}

variable "owner" {
  description = "Owner tag applied to lab resources."
  type        = string
  default     = "Lab-User"

  validation {
    condition     = length(trimspace(var.owner)) > 0 && length(var.owner) <= 64
    error_message = "owner must contain 1-64 characters."
  }
}

variable "repository_url" {
  description = "Repository URL written to resource tags."
  type        = string
  default     = "https://github.com/Jamonygr/azure-virtual-network-manager-lab"
}

variable "topology_mode" {
  description = "AVNM connectivity goal state."
  type        = string
  default     = "HubAndSpoke"

  validation {
    condition     = contains(["HubAndSpoke", "Mesh"], var.topology_mode)
    error_message = "topology_mode must be HubAndSpoke or Mesh."
  }
}

variable "ipam_root_prefix" {
  description = "Root IPv4 IPAM pool. Treat this prefix as immutable after deployment."
  type        = string
  default     = "10.240.0.0/12"

  validation {
    condition = (
      can(cidrhost(var.ipam_root_prefix, 0)) &&
      !strcontains(var.ipam_root_prefix, ":") &&
      try(split("/", var.ipam_root_prefix)[0] == cidrhost(var.ipam_root_prefix, 0), false)
    )
    error_message = "ipam_root_prefix must be a canonical IPv4 network CIDR."
  }
}

variable "ipam_hub_pool_prefix" {
  description = "Child IPAM pool used by the hub VNet."
  type        = string
  default     = "10.240.0.0/16"

  validation {
    condition = (
      can(cidrhost(var.ipam_hub_pool_prefix, 0)) &&
      !strcontains(var.ipam_hub_pool_prefix, ":") &&
      try(split("/", var.ipam_hub_pool_prefix)[0] == cidrhost(var.ipam_hub_pool_prefix, 0), false)
    )
    error_message = "ipam_hub_pool_prefix must be a canonical IPv4 network CIDR."
  }
}

variable "ipam_workload_pool_prefix" {
  description = "Child IPAM pool used by workload VNets."
  type        = string
  default     = "10.241.0.0/16"

  validation {
    condition = (
      can(cidrhost(var.ipam_workload_pool_prefix, 0)) &&
      !strcontains(var.ipam_workload_pool_prefix, ":") &&
      try(split("/", var.ipam_workload_pool_prefix)[0] == cidrhost(var.ipam_workload_pool_prefix, 0), false)
    )
    error_message = "ipam_workload_pool_prefix must be a canonical IPv4 network CIDR."
  }
}

variable "ipam_reserved_prefix" {
  description = "Static workload-pool reservation used to demonstrate IPAM exclusions."
  type        = string
  default     = "10.241.240.0/20"

  validation {
    condition = (
      can(cidrhost(var.ipam_reserved_prefix, 0)) &&
      !strcontains(var.ipam_reserved_prefix, ":") &&
      try(split("/", var.ipam_reserved_prefix)[0] == cidrhost(var.ipam_reserved_prefix, 0), false)
    )
    error_message = "ipam_reserved_prefix must be a canonical IPv4 network CIDR."
  }
}

variable "vnet_prefix_length" {
  description = "Prefix length requested from IPAM for each VNet."
  type        = number
  default     = 20

  validation {
    condition     = var.vnet_prefix_length >= 18 && var.vnet_prefix_length <= 24
    error_message = "vnet_prefix_length must be between /18 and /24."
  }
}

variable "subnet_prefix_length" {
  description = "Prefix length derived inside each Azure-allocated VNet prefix."
  type        = number
  default     = 24

  validation {
    condition     = var.subnet_prefix_length >= 24 && var.subnet_prefix_length <= 28
    error_message = "subnet_prefix_length must be between /24 and /28."
  }
}

variable "tags" {
  description = "Additional tags merged with the mandatory lab tags."
  type        = map(string)
  default     = {}
}
