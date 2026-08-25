## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.15.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | = 5.2.0 |
| <a name="requirement_time"></a> [time](#requirement\_time) | ~> 0.13 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | 5.2.0 |
| <a name="provider_time"></a> [time](#provider\_time) | 0.14.1 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_network_manager.lab](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager) | resource |
| [azurerm_resource_group.lab](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/resource_group) | resource |
| [time_sleep.ipam_pool_settle](https://registry.terraform.io/providers/hashicorp/time/latest/docs/resources/sleep) | resource |
| [azurerm_subscription.current](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/data-sources/subscription) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment label used in resource names and tags. | `string` | `"lab"` | no |
| <a name="input_ipam_hub_pool_prefix"></a> [ipam\_hub\_pool\_prefix](#input\_ipam\_hub\_pool\_prefix) | Child IPAM pool used by the hub VNet. | `string` | `"10.240.0.0/16"` | no |
| <a name="input_ipam_reserved_prefix"></a> [ipam\_reserved\_prefix](#input\_ipam\_reserved\_prefix) | Static workload-pool reservation used to demonstrate IPAM exclusions. | `string` | `"10.241.240.0/20"` | no |
| <a name="input_ipam_root_prefix"></a> [ipam\_root\_prefix](#input\_ipam\_root\_prefix) | Root IPv4 IPAM pool. Treat this prefix as immutable after deployment. | `string` | `"10.240.0.0/12"` | no |
| <a name="input_ipam_workload_pool_prefix"></a> [ipam\_workload\_pool\_prefix](#input\_ipam\_workload\_pool\_prefix) | Child IPAM pool used by workload VNets. | `string` | `"10.241.0.0/16"` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the complete lab and all AVNM deployments. | `string` | `"westeurope"` | no |
| <a name="input_owner"></a> [owner](#input\_owner) | Owner tag applied to lab resources. | `string` | `"Lab-User"` | no |
| <a name="input_project"></a> [project](#input\_project) | Short project name used in Azure resource names. | `string` | `"avnm"` | no |
| <a name="input_repository_url"></a> [repository\_url](#input\_repository\_url) | Repository URL written to resource tags. | `string` | `"https://github.com/Jamonygr/azure-virtual-network-manager-lab"` | no |
| <a name="input_run_id"></a> [run\_id](#input\_run\_id) | Run-specific identifier that isolates dynamic membership and disposable resources. | `string` | `"manual"` | no |
| <a name="input_subnet_prefix_length"></a> [subnet\_prefix\_length](#input\_subnet\_prefix\_length) | Prefix length derived inside each Azure-allocated VNet prefix. | `number` | `24` | no |
| <a name="input_subscription_id"></a> [subscription\_id](#input\_subscription\_id) | Azure subscription ID. Leave null to use ARM\_SUBSCRIPTION\_ID or the active Azure CLI subscription. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged with the mandatory lab tags. | `map(string)` | `{}` | no |
| <a name="input_topology_mode"></a> [topology\_mode](#input\_topology\_mode) | AVNM connectivity goal state. | `string` | `"HubAndSpoke"` | no |
| <a name="input_vnet_prefix_length"></a> [vnet\_prefix\_length](#input\_vnet\_prefix\_length) | Prefix length requested from IPAM for each VNet. | `number` | `20` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_allocated_vnet_prefixes"></a> [allocated\_vnet\_prefixes](#output\_allocated\_vnet\_prefixes) | Azure-allocated VNet prefixes keyed by role. |
| <a name="output_configuration_ids"></a> [configuration\_ids](#output\_configuration\_ids) | Connectivity, security, and routing configuration IDs. |
| <a name="output_ipam_pool_ids"></a> [ipam\_pool\_ids](#output\_ipam\_pool\_ids) | IPAM pool and static-reservation IDs. |
| <a name="output_location"></a> [location](#output\_location) | Region receiving the AVNM goal state. |
| <a name="output_network_group_ids"></a> [network\_group\_ids](#output\_network\_group\_ids) | AVNM network group IDs keyed by teaching purpose. |
| <a name="output_network_manager"></a> [network\_manager](#output\_network\_manager) | AVNM resource name and ID. |
| <a name="output_policy_ids"></a> [policy\_ids](#output\_policy\_ids) | Dynamic-membership policy definition and assignment IDs. |
| <a name="output_resource_group"></a> [resource\_group](#output\_resource\_group) | Lab resource group name and ID. |
| <a name="output_routing_rule_id"></a> [routing\_rule\_id](#output\_routing\_rule\_id) | Safe TEST-NET blackhole routing-rule ID. |
| <a name="output_run_id"></a> [run\_id](#output\_run\_id) | Run identifier used for resource isolation. |
| <a name="output_security_rule_ids"></a> [security\_rule\_ids](#output\_security\_rule\_ids) | Security admin rule IDs keyed by rule name. |
| <a name="output_subnet_ids"></a> [subnet\_ids](#output\_subnet\_ids) | Subnet IDs keyed by VNet role. |
| <a name="output_subnet_prefixes"></a> [subnet\_prefixes](#output\_subnet\_prefixes) | Derived subnet prefixes keyed by VNet role. |
| <a name="output_subscription_id"></a> [subscription\_id](#output\_subscription\_id) | Azure subscription used by the lab. |
| <a name="output_topology_mode"></a> [topology\_mode](#output\_topology\_mode) | Current AVNM connectivity goal state. |
| <a name="output_virtual_network_ids"></a> [virtual\_network\_ids](#output\_virtual\_network\_ids) | Virtual network IDs keyed by role. |
| <a name="output_virtual_network_names"></a> [virtual\_network\_names](#output\_virtual\_network\_names) | Virtual network names keyed by role. |
