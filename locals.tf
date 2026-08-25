locals {
  normalized_location = lower(replace(var.location, " ", ""))
  location_short = lookup({
    westeurope         = "weu"
    northeurope        = "neu"
    germanywestcentral = "gwc"
    eastus             = "eus"
    eastus2            = "eus2"
    westus2            = "wus2"
    centralus          = "cus"
    uksouth            = "uks"
  }, local.normalized_location, substr(local.normalized_location, 0, min(6, length(local.normalized_location))))

  name_suffix = "${var.project}-${var.environment}-${var.run_id}-${local.location_short}"

  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.owner
    Project     = var.project
    Repository  = var.repository_url
    RunId       = var.run_id
  })

  ipam_cidr_parts = {
    for name, cidr in {
      root        = var.ipam_root_prefix
      hub         = var.ipam_hub_pool_prefix
      workload    = var.ipam_workload_pool_prefix
      reservation = var.ipam_reserved_prefix
      } : name => {
      octets        = try([for octet in split(".", split("/", cidr)[0]) : tonumber(octet)], [0, 0, 0, 0])
      prefix_length = try(tonumber(split("/", cidr)[1]), 32)
    }
  }

  ipam_networks = {
    for name, parts in local.ipam_cidr_parts : name => {
      first = sum([for index, octet in parts.octets : octet * pow(256, 3 - index)])
      last  = sum([for index, octet in parts.octets : octet * pow(256, 3 - index)]) + pow(2, 32 - parts.prefix_length) - 1
    }
  }

  networks = {
    hub = {
      role        = "hub"
      subnet_name = "snet-management"
    }
    app = {
      role        = "workload"
      subnet_name = "snet-workload"
    }
    data = {
      role        = "workload"
      subnet_name = "snet-workload"
    }
  }
}
