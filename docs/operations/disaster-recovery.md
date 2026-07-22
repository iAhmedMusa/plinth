# Disaster recovery

What this repo's current, single-region setup actually protects against
today, with concrete targets — not the aspirational multi-region plan,
which is tracked separately in [`docs/roadmap.md`](../roadmap.md) (item 7)
as a **Later** item.

## 1. Scope

Single region (`ap-southeast-1`), single AZ for RDS by default
(`multi_az = false` in every env — see
[`terraform/modules/rds/variables.tf`](../../terraform/modules/rds/variables.tf)).
This document covers recovery from data loss or a bad deploy within that
scope: an accidentally dropped table, a corrupted migration, a botched
`terraform apply`, or a single-AZ outage. It does not cover a full
region-wide outage — that requires the cross-region work in the roadmap.

## 2. RTO / RPO targets

| Scenario | RPO (data loss tolerance) | RTO (time to restore) |
|---|---|---|
| Accidental data deletion / bad migration | ≤ 5 minutes (RDS point-in-time recovery granularity) | ~15–30 minutes (restore + DNS/connection cutover) |
| RDS instance failure (single-AZ) | 0 (automated backups, no in-flight transaction loss beyond the failure instant) | ~10–20 minutes (AWS-managed instance recovery from backup) |
| EKS cluster misconfiguration / bad apply | 0 (Git is the source of truth) | ~10 minutes (`terraform apply` / `kubectl apply -k` from last-known-good commit) |
| Full AZ outage | 0 for RDS storage (multi-AZ EBS-backed), pod-level only for compute | Compute: minutes, via EKS rescheduling to a healthy AZ. Database: manual promote-and-restore if the AZ hosting the instance is the one that failed (see limitation below) |

**Known limitation:** because `multi_az` defaults to `false`, an AZ
failure that takes down the RDS instance's own AZ requires a restore from
backup rather than an automatic failover. This is a deliberate cost
tradeoff (see [`docs/architecture.md`](../architecture.md#5-deliberate-tradeoffs))
— setting `multi_az = true` in the relevant `envs/*.tfvars` removes this
limitation at roughly double the instance cost.

## 3. What's already in place

- **Automated RDS backups with point-in-time recovery** —
  `backup_retention_period` (7 days by default,
  `backup_retention_days` in `terraform/modules/rds/variables.tf`) —
  no additional setup required, this is on by default for every
  environment.
- **`deletion_protection = true` and a final snapshot on delete** —
  `terraform/modules/rds/main.tf` sets `skip_final_snapshot = false`, so
  even a deliberate `terraform destroy` leaves a recovery point behind.
- **`prevent_destroy` on the RDS instance and EKS cluster** — the
  lifecycle guard documented in `terraform/README.md` section 8 — stops
  an unreviewed `apply` from silently replacing either.
- **Git as the source of truth for cluster state** — every manifest is
  declarative (`k8s/`) and every infrastructure resource is declarative
  (`terraform/`), so "restore to last known good" is a `git checkout` plus
  an apply, not a manual reconstruction.

## 4. Restore procedure

**Database (point-in-time recovery):**
```bash
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier plinth-<env>-db \
  --target-db-instance-identifier plinth-<env>-db-restored \
  --restore-time <ISO-8601-timestamp>
```
Then update the `DATABASE_URL` secret (Secrets Manager) to point at the
restored instance's endpoint, and cut the backend over to it. The
original instance is left in place until the restore is verified.

**Cluster / manifests:**
```bash
git log --oneline -- k8s/          # find the last known-good commit
git checkout <commit> -- k8s/
kubectl apply -k k8s/overlays/production
```

**Infrastructure (Terraform):**
```bash
git checkout <commit> -- terraform/
terraform plan -var-file=envs/production.tfvars   # review before applying
terraform apply -var-file=envs/production.tfvars
```

## 5. What isn't tested

None of the above has been run against a real AWS account — there is no
live infrastructure behind this repo (see
[`terraform/README.md`](../../terraform/README.md) section 9). The
restore commands are correct against the AWS API and this repo's own
Terraform, but "documented and correct" is not the same claim as
"drilled." A real deployment would run each of these quarterly against a
non-production environment and record the actual time taken, not the
estimated one in section 2.
