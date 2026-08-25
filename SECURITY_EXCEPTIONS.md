# Deliberate security exceptions

This repository is a disposable, control-plane teaching lab. The following choices are intentional and tested as repository contracts:

- No network security group is attached because no NIC or workload exists. Azure Virtual Network Manager security admin rules are the subject under test. The subnet carries the narrowly scoped Checkov `CKV2_AZURE_31` exception; Trivy exceptions `AVD-AZU-0047` and `AVD-AZU-0048` are recorded in `.trivyignore.yaml`.
- No DDoS plan, Firewall, NAT gateway, private endpoint, public IP, diagnostics, or Log Analytics workspace is deployed.
- The managed route for `203.0.113.0/24` uses `NoNextHop`. TEST-NET-3 is reserved for documentation, so the rule cannot redirect production traffic.
- Local Terraform state is required for a create-test-destroy run. State is isolated under a unique temporary directory and removed after verified cleanup.
- `prevent_deletion_if_contains_resources = false` lets Terraform remove the disposable resource group after AVNM goal-state cleanup.

These exceptions do not make the lab a production architecture. Do not copy them into a production landing zone without a threat model and design review.
