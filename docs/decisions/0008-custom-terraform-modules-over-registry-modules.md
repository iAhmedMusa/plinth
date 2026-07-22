# 0008. Custom Terraform modules over community registry modules

## Context

The platform needs network, EKS, ECR, RDS, and monitoring
infrastructure. Well-known community modules exist for most of these
(`terraform-aws-modules/eks/aws`, `.../vpc/aws`, `.../rds/aws`) and are
widely used in production.

## Decision

Five hand-written modules under `terraform/modules/` — `network`,
`eks`, `ecr`, `rds`, `monitoring` — with zero
`source = "terraform-aws-modules/..."` or any other registry/third-party
module. Only the official `hashicorp/aws` and `hashicorp/tls` providers
are used directly.

## Alternatives considered

- **`terraform-aws-modules/*` community modules.** Far less code to
  write, battle-tested across many real deployments, actively
  maintained. Rejected for this repo specifically: these modules carry
  a large surface of optional features (Fargate profiles, multiple
  node group types, add-on management, cross-account patterns) most of
  which go unused here, adding a fourth-party dependency — the module
  maintainer, not just the AWS provider — to a repository whose purpose
  is demonstrating what its author can build. Reading "what does this
  actually provision" would mean reading someone else's abstraction
  layer instead of this repo's own code.

## Consequences

More code to write and maintain by hand, and no free ride on community
module upgrades, bugfixes, or newly-supported AWS features — a real
ongoing cost relative to depending on a maintained module. In exchange,
every resource this platform provisions is legible from this repo
alone: the module dependency graph in `terraform/README.md` is a
complete picture of what exists, not a curated subset of a much larger
module's surface area. For a reference/portfolio deployment meant to be
read end to end, that legibility is worth more than the maintenance
savings a registry module would provide.
