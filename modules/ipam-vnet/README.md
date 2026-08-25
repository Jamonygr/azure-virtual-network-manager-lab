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
| [azurerm_subnet.this](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/subnet) | resource |
| [azurerm_virtual_network.this](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/virtual_network) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_ipam_pool_id"></a> [ipam\_pool\_id](#input\_ipam\_pool\_id) | IPAM pool from which the VNet requests an allocation. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Virtual network name. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Resource group name. | `string` | n/a | yes |
| <a name="input_subnet_name"></a> [subnet\_name](#input\_subnet\_name) | Name of the single control-plane demonstration subnet. | `string` | n/a | yes |
| <a name="input_subnet_prefix_length"></a> [subnet\_prefix\_length](#input\_subnet\_prefix\_length) | Derived subnet prefix length. | `number` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the VNet. | `map(string)` | n/a | yes |
| <a name="input_vnet_prefix_length"></a> [vnet\_prefix\_length](#input\_vnet\_prefix\_length) | Requested VNet prefix length. | `number` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_allocated_prefix"></a> [allocated\_prefix](#output\_allocated\_prefix) | Azure-allocated VNet prefix. |
| <a name="output_id"></a> [id](#output\_id) | Virtual network ID. |
| <a name="output_name"></a> [name](#output\_name) | Virtual network name. |
| <a name="output_subnet_id"></a> [subnet\_id](#output\_subnet\_id) | Derived subnet ID. |
| <a name="output_subnet_prefix"></a> [subnet\_prefix](#output\_subnet\_prefix) | Derived subnet prefix. |
