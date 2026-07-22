# 0003. Security-group-to-security-group rules over CIDR blocks

## Context

The RDS security group needs an ingress rule for port 5432. The source
of that rule can be expressed either as an IP range (CIDR) or as a
reference to another security group.

## Decision

`terraform/modules/rds/main.tf`'s `db_ingress_from_nodes` rule sources
from the EKS node security group by reference, not a CIDR block. Only
members of that security group — EKS worker nodes — can reach 5432 at
the network layer at all.

## Alternatives considered

- **CIDR block covering the private-app subnets.** Easier to read at a
  glance in the console. Rejected because it authorizes by *location*,
  not *identity*: anything later placed in those subnets — a bastion
  host, a misconfigured Lambda with VPC access, a future service that
  has nothing to do with this database — inherits the same access with
  no code change and no review trigger. A CIDR rule also doesn't shrink
  or grow as node groups are replaced (see the EKS upgrade path in
  `docs/operations/upgrades.md`); it has to be manually kept in sync
  with the subnet layout instead.

## Consequences

The rule tracks node group membership automatically — a node group
replaced during an upgrade (ADR-implicit in `docs/operations/upgrades.md`)
is covered with zero Terraform changes, because the *security group*,
not the specific instances, is what's referenced. The cost is a cross-
module dependency: `modules/rds` now takes `node_security_group_id` as
an input from `modules/eks` (visible as an edge in the module graph in
`terraform/README.md`), so the two modules can't be applied fully
independently of each other on a from-scratch account. Auditing the
rule from the AWS console also takes one more click than a CIDR would —
you have to resolve the security group to its members to know exactly
what's authorized — which is a reasonable price for a rule that can't
silently widen over time.
