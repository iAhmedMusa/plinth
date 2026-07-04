# rds module

## Purpose

Private PostgreSQL 16 instance in the db-tier subnets, reachable only from
EKS worker nodes, password never touched by Terraform.

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix` | Resource name prefix | (required) |
| `vpc_id` | VPC ID | (required) |
| `private_db_subnet_ids` | Db-tier subnet IDs | (required) |
| `node_security_group_id` | EKS node SG -- the only allowed source | (required) |
| `db_instance_class` | Instance class | `db.t4g.micro` |
| `db_name` | Initial database name | (required) |
| `db_username` | Master username | (required) |
| `multi_az` | Multi-AZ standby | `false` |
| `backup_retention_days` | Backup retention window | `7` |
| `tags` | Common tags | `{}` |

## Outputs

| Name | Description |
|---|---|
| `endpoint` | Connection endpoint (sensitive) |
| `port` | Port |
| `security_group_id` | DB security group ID |
| `master_user_secret_arn` | Secrets Manager ARN holding the master password |

## Design notes

- **No `db_password` variable, anywhere.** `manage_master_user_password =
  true` tells RDS to generate the master password itself and store it in
  AWS Secrets Manager — Terraform never sees it, so it can never end up in
  a `.tfvars` file, a plan diff, or state (even encrypted state is a wider
  blast radius than "not present at all"). The application reads the
  actual connection secret at runtime via External Secrets Operator or the
  Secrets Store CSI driver, using IRSA — never a value baked into a
  ConfigMap, an image, or a Kubernetes Secret checked into git. An
  alternative some teams prefer is `random_password` + writing to SSM
  Parameter Store from Terraform; that keeps the password's lifecycle
  fully in Terraform's hands but means the value transits Terraform state
  as plaintext (state is normally encrypted at rest via the S3 backend's
  SSE, but it's still one more place the value exists) — `manage_master_user_password`
  avoids that entirely, which is why it's the default here.
- **`publicly_accessible = false` is not the only guard.** The db-tier
  subnets (network module) have no route to an internet gateway or NAT
  gateway at all, so there is no path from the internet to this instance
  even if this flag were somehow misconfigured. Defense in depth: routing
  isolation first, this flag second, the security group third.
- **Security group is SG-to-SG, not CIDR.** Ingress on 5432 references the
  EKS node security group directly. As nodes scale up/down or get
  replaced by a new node group, this rule needs no update — anything not a
  member of that security group cannot reach the database, regardless of
  what subnet or IP it has.
- **`prevent_destroy = true` and `deletion_protection = true`.** Two
  independent guards against an accidental destroy: Terraform refuses to
  even plan a destroy of this resource, and AWS itself refuses a delete
  API call unless deletion protection is explicitly turned off first.
  `skip_final_snapshot = false` means even a deliberate, reviewed destroy
  still leaves a final snapshot behind.
- **Single-AZ by default (`multi_az = false`).** Cost trade-off for this
  assessment — a Multi-AZ standby roughly doubles the instance cost. Real
  production should set `multi_az = true` for automatic failover.
