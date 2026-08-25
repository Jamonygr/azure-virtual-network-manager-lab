## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.15.0, < 2.0.0 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | = 5.2.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | = 5.2.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_network_manager_ipam_pool.hub](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_ipam_pool) | resource |
| [azurerm_network_manager_ipam_pool.root](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_ipam_pool) | resource |
| [azurerm_network_manager_ipam_pool.workload](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_ipam_pool) | resource |
| [azurerm_network_manager_ipam_pool_static_cidr.reserved](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_ipam_pool_static_cidr) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_hub_prefix"></a> [hub\_prefix](#input\_hub\_prefix) | Hub child-pool prefix. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region for the IPAM pools. | `string` | n/a | yes |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Unique suffix for pool names. | `string` | n/a | yes |
| <a name="input_network_manager_id"></a> [network\_manager\_id](#input\_network\_manager\_id) | Parent Azure Virtual Network Manager ID. | `string` | n/a | yes |
| <a name="input_root_prefix"></a> [root\_prefix](#input\_root\_prefix) | Root IPAM prefix. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to IPAM pools. | `map(string)` | n/a | yes |
| <a name="input_workload_prefix"></a> [workload\_prefix](#input\_workload\_prefix) | Workload child-pool prefix. | `string` | n/a | yes |
| <a name="input_workload_reserved_prefix"></a> [workload\_reserved\_prefix](#input\_workload\_reserved\_prefix) | Static CIDR reserved inside the workload child pool. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_hub_pool_id"></a> [hub\_pool\_id](#output\_hub\_pool\_id) | Hub child-pool ID. |
| <a name="output_ids"></a> [ids](#output\_ids) | All IPAM resource IDs. |
| <a name="output_root_pool_id"></a> [root\_pool\_id](#output\_root\_pool\_id) | Root IPAM pool ID. |
| <a name="output_workload_pool_id"></a> [workload\_pool\_id](#output\_workload\_pool\_id) | Workload child-pool ID. |
