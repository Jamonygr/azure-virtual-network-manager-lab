# Contributing

Keep changes focused on the control-plane learning goals. New compute, NIC, public endpoint, Firewall, gateway, NAT, diagnostic, remote-backend, or CI deployment resources are intentionally outside scope.

Before opening a change:

1. Run `.\scripts\invoke-pre-commit-check.ps1`.
2. Regenerate [Terraform reference](docs/generated/terraform.md) when the module interface changes.
3. Add mocked tests and repository contracts for changed behavior.
4. Run live validation only in a disposable subscription or with an approved subscription-scoped AVNM design.
5. Confirm cleanup and retain only sanitized evidence; never commit state, plans, IDs, access tokens, or generated live tfvars.

