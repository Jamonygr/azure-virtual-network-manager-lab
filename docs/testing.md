# Testing and evidence

## Local static suite

```powershell
.\scripts\invoke-pre-commit-check.ps1
```

The suite runs Terraform formatting, backendless initialization, validation, mocked `terraform test` scenarios, Pester lifecycle/helper tests, Go repository contracts, local Markdown-link checks, TFLint, Trivy, generated-document drift, and actionlint. Use `-SkipOptionalTools` only while bootstrapping tools.

Recommended tool versions match `.github/workflows/static-checks.yml`: Terraform 1.15.8, AzureRM 5.2.0, TFLint 0.63.1, Trivy 0.72.0, Checkov 3.2.x, Gitleaks 8.x, Conftest 0.68.2, terraform-docs 0.24.0, actionlint 1.7.12, Pester 5.7.1, and Go 1.21 or newer.

## Mocked Terraform coverage

`terraform test` uses a mocked AzureRM provider. It verifies address-plan contracts, `/20` requests, `/24` derivation, static and dynamic group semantics, both connectivity shapes, the three security rules, the TEST-NET route, and deployment goal-state hashes without contacting Azure.

## Pester coverage

Pester tests the CIDR helpers, deployment state machine (fresh, stale, terminal failure, and timeout), the exact Azure-required connectivity recreation plan, guaranteed cleanup after work failure, dual failure reporting, and recovery-manifest requirements.

## Policy and repository contracts

Conftest evaluates secure and deliberately insecure Terraform-plan fixtures. Go contracts scan the whole repository to forbid compute, Firewall, public IPs, diagnostics, manually authored peerings/route tables, remote backends, Azure credential material, and live Azure/Terraform mutation in CI.

## Live acceptance

The live command is the only acceptance test. It needs Azure credentials and intentionally runs only from an engineer's local shell. Success means both topologies, both no-drift plans, and teardown evidence passed. Packet delivery is explicitly out of scope.

GitHub Actions is static and credential-free. It has no Azure login action, no cloud secrets, and no `terraform plan`, `apply`, or `destroy` command.
