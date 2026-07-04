# network module

## Purpose

Three-tier VPC: public (ALB/NAT), private-app (EKS nodes), private-db (RDS).
Each tier spans 3 AZs.

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix` | Resource name prefix | (required) |
| `region` | AWS region, drives the AZ list | (required) |
| `vpc_cidr` | VPC CIDR block | `10.0.0.0/16` |
| `single_nat_gateway` | One NAT for all AZs vs. one per AZ | `true` |
| `tags` | Common tags | `{}` |

## Outputs

| Name | Description |
|---|---|
| `vpc_id` | VPC ID |
| `public_subnet_ids` | Public subnet IDs |
| `private_app_subnet_ids` | Private app (EKS node) subnet IDs |
| `private_db_subnet_ids` | Private db (RDS) subnet IDs |
| `azs` | AZ names used |

## Design notes

- **Three tiers, not two.** Public carries only ALB/NAT — no workload ever
  gets a public IP. Private-app carries EKS nodes, egress-only via NAT.
  Private-db carries RDS with **no route out at all** (not even NAT) —
  isolation enforced at the routing layer, not just security groups.
- **AZs from the region string, not a data source.** `data
  "aws_availability_zones"` needs live AWS credentials to resolve at plan
  time, which breaks the credential-free `terraform plan` this assessment
  requires. `${region}a/b/c` is correct for every commercial AWS region.
- **Single NAT gateway by default.** A real HA production setup wants one
  NAT per AZ so an AZ outage doesn't take down every other AZ's egress —
  set `single_nat_gateway = false` for that. Single here is a deliberate
  cost trade-off for this assessment (NAT gateways bill hourly + per-GB).
- **EKS subnet tags.** `kubernetes.io/role/elb` on public and
  `kubernetes.io/role/internal-elb` on private-app are how the AWS Load
  Balancer Controller auto-discovers which subnets to place ALBs/NLBs into
  — without them you'd have to hardcode subnet IDs into every Ingress
  annotation.
