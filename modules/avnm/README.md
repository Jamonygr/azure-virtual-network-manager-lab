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
| [azurerm_network_manager_admin_rule.always_allow_hub_ssh](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_admin_rule) | resource |
| [azurerm_network_manager_admin_rule.deny_inbound_management](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_admin_rule) | resource |
| [azurerm_network_manager_admin_rule.deny_outbound_smb](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_admin_rule) | resource |
| [azurerm_network_manager_admin_rule_collection.workloads](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_admin_rule_collection) | resource |
| [azurerm_network_manager_connectivity_configuration.active](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_connectivity_configuration) | resource |
| [azurerm_network_manager_deployment.connectivity](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_deployment) | resource |
| [azurerm_network_manager_deployment.routing](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_deployment) | resource |
| [azurerm_network_manager_deployment.security](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_deployment) | resource |
| [azurerm_network_manager_network_group.all_vnets_static](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_network_group) | resource |
| [azurerm_network_manager_network_group.spokes_static](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_network_group) | resource |
| [azurerm_network_manager_network_group.workload_subnets_static](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_network_group) | resource |
| [azurerm_network_manager_network_group.workloads_dynamic](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_network_group) | resource |
| [azurerm_network_manager_routing_configuration.safe](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_routing_configuration) | resource |
| [azurerm_network_manager_routing_rule.test_net_blackhole](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_routing_rule) | resource |
| [azurerm_network_manager_routing_rule_collection.workloads](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_routing_rule_collection) | resource |
| [azurerm_network_manager_security_admin_configuration.baseline](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_security_admin_configuration) | resource |
| [azurerm_network_manager_static_member.all_vnets](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_static_member) | resource |
| [azurerm_network_manager_static_member.spokes](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_static_member) | resource |
| [azurerm_network_manager_static_member.workload_subnets](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/network_manager_static_member) | resource |
| [azurerm_policy_definition.workload_membership](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/policy_definition) | resource |
| [azurerm_resource_group_policy_assignment.workload_membership](https://registry.terraform.io/providers/hashicorp/azurerm/5.2.0/docs/resources/resource_group_policy_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_all_vnet_ids"></a> [all\_vnet\_ids](#input\_all\_vnet\_ids) | All lab VNet IDs keyed by role. | `map(string)` | n/a | yes |
| <a name="input_hub_subnet_prefix"></a> [hub\_subnet\_prefix](#input\_hub\_subnet\_prefix) | Actual Azure-allocated hub management subnet prefix. | `string` | n/a | yes |
| <a name="input_hub_vnet_id"></a> [hub\_vnet\_id](#input\_hub\_vnet\_id) | Hub VNet ID. | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Region receiving configuration deployments. | `string` | n/a | yes |
| <a name="input_name_suffix"></a> [name\_suffix](#input\_name\_suffix) | Unique suffix used in AVNM component names. | `string` | n/a | yes |
| <a name="input_network_manager_id"></a> [network\_manager\_id](#input\_network\_manager\_id) | Azure Virtual Network Manager ID. | `string` | n/a | yes |
| <a name="input_resource_group_id"></a> [resource\_group\_id](#input\_resource\_group\_id) | Lab resource group ID used as the dynamic policy-assignment scope. | `string` | n/a | yes |
| <a name="input_run_id"></a> [run\_id](#input\_run\_id) | Run tag selected by the dynamic group policy. | `string` | n/a | yes |
| <a name="input_topology_mode"></a> [topology\_mode](#input\_topology\_mode) | Connectivity goal state. | `string` | n/a | yes |
| <a name="input_workload_address_space"></a> [workload\_address\_space](#input\_workload\_address\_space) | Workload IPAM child-pool prefix used by security rules. | `string` | n/a | yes |
| <a name="input_workload_subnet_ids"></a> [workload\_subnet\_ids](#input\_workload\_subnet\_ids) | App and data subnet IDs keyed by role. | `map(string)` | n/a | yes |
| <a name="input_workload_vnet_ids"></a> [workload\_vnet\_ids](#input\_workload\_vnet\_ids) | App and data VNet IDs keyed by role. | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_configuration_ids"></a> [configuration\_ids](#output\_configuration\_ids) | AVNM configuration IDs. |
| <a name="output_network_group_ids"></a> [network\_group\_ids](#output\_network\_group\_ids) | Network group IDs keyed by teaching purpose. |
| <a name="output_policy_ids"></a> [policy\_ids](#output\_policy\_ids) | Dynamic membership policy IDs. |
| <a name="output_routing_rule_id"></a> [routing\_rule\_id](#output\_routing\_rule\_id) | Safe TEST-NET-3 blackhole rule ID. |
| <a name="output_security_rule_ids"></a> [security\_rule\_ids](#output\_security\_rule\_ids) | Security admin rule IDs. |
