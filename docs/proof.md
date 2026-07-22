# Proof of work

Evidence for each task, grouped by requirement. All screenshots are from
real runs — no mocked or synthetic output.

---

## Task 1 — Build the actual app

### Local cluster running all three services

Two backend replicas, two frontend replicas, one postgres — all running
in the `plinth-local` namespace:

![kubectl get all — local namespace](proof/Screenshot%202026-07-04%20at%2011.07.11.png)

### Production namespace (multi-replica)

Three backend replicas, two frontend replicas, one postgres — all
`Running`, all `1/1 Ready`:

![kubectl get all — production namespace](proof/Screenshot%202026-07-04%20at%2011.05.50.png)

---

## Task 2 — CI/CD pipeline

### Full pipeline success (v0.1.2)

All 7 jobs passed: test backend, test frontend, build and push images,
mock ECR push, GitHub release, mock staging deploy, mock production
deploy. Total: 14m 19s.

![Pipeline v0.1.2 — all jobs green](proof/Screenshot%202026-07-04%20at%2011.28.47.png)

### Docker build records and Trivy scan artifacts

Three artifacts produced: frontend build record (112 KB), backend build
record (95.8 KB), and Trivy scan results (8.15 KB).

![Artifacts — build records + Trivy scan](proof/Screenshot%202026-07-04%20at%2011.28.59.png)

### Build details — frontend and backend

Frontend build: 8m 21s. Backend build: 2m 21s. Both completed with 0%
cache (clean builds).

![Build summary — frontend and backend](proof/Screenshot%202026-07-04%20at%2011.29.09.png)

### Staging deploy in progress (v0.2.0)

Pipeline triggered by merge to `ci/kind-staging-deploy`. "Deploy to
staging (kind)" job running — proves the real kind cluster deploy step
works, not just the mock.

![Staging deploy running](proof/Screenshot%202026-07-04%20at%2011.57.54.png)

### Production approval gate (v0.2.1)

Pipeline paused at "Deploy to production" — GitHub environment protection
rule requested a review before proceeding:

![Waiting for production review](proof/Screenshot%202026-07-04%20at%2012.17.34.png)

### Approval dialog

The "Review pending deployments" modal — reviewer must check the
`production` environment and click "Approve and deploy":

![Approval dialog](proof/Screenshot%202026-07-04%20at%2012.17.43.png)

### Pipeline success after approval (v0.2.1)

All 7 jobs green after manual approval. Total: 16m 30s. The full chain
(test → build → release → staging → approval → production) completed
end-to-end.

![Pipeline success after approval](proof/Screenshot%202026-07-04%20at%2012.17.54.png)

### Latest pipeline run (v0.3.0)

Triggered by merge of `feat/terraform-eks`. All jobs passed. Total:
14m 57s.

![Pipeline v0.3.0 — all jobs green](proof/Screenshot%202026-07-04%20at%2013.11.00.png)

---

## Task 3 — Kubernetes manifests

The `kubectl get all` screenshots above (Task 1) prove the manifests
work: both deployments run 2+ replicas, all pods pass readiness probes,
services are ClusterIP (no external IPs), and the ingress routes only to
the frontend.

The CI/CD pipeline's staging deploy step applies `k8s/overlays/ci` to a
real kind cluster and runs smoke tests — see Task 2 evidence above.

---

## Task 4 — Private database connectivity

See `docs/database-connectivity.md` for the full architecture. The
screenshots above confirm the database runs inside the cluster as a
ClusterIP service (`postgres  5432/TCP  <none>`), not exposed externally.

---

## Task 5 — Infrastructure as code (Terraform)

### Terraform plan — dev environment

Full plan saved at `proof/tfplan-dev.txt`. Key highlights:

| Module | Resources | What it creates |
|--------|-----------|-----------------|
| `network` | 19 | VPC, 3 public subnets, 3 private-app subnets, 3 private-db subnets, IGW, NAT, route tables, associations |
| `eks` | 14 | EKS cluster (v1.30), managed node group (t3.medium, 2 nodes), OIDC provider, IAM roles, security groups |
| `ecr` | 4 | Two ECR repos (backend + frontend) with lifecycle policies, immutable tags, scan-on-push |
| `rds` | 3 | PostgreSQL 16 instance, subnet group, security group (SG-to-SG ingress from nodes) |
| `monitoring` | 5 | CloudWatch log groups, Container Insights addon, CPU alarm, storage alarm, SNS topic |

**Total: 59 resources to create, 0 to change, 0 to destroy.**

```bash
# Commands run to produce the plan:
cd terraform
terraform init -backend=false
terraform validate                              # passes
terraform fmt -check -recursive                  # passes
terraform plan -var-file=envs/dev.tfvars \
  -out=tfplan-dev 2>&1 | tee proof/tfplan-dev.txt
```

Notable from the plan:

- **Three-tier VPC**: public subnets (IGW route), private-app subnets
  (NAT route), private-db subnets (no default route — no path out)
- **EKS cluster**: Kubernetes 1.30, API/audit/authenticator logging,
  public endpoint restricted to `0.0.0.0/0` (dev), `prevent_destroy`
  set
- **Node group**: `t3.medium`, desired 2 / min 1 / max 2,
  `create_before_destroy`, `ignore_changes` on desired_size
- **ECR repos**: `IMMUTABLE` tag mutability, AES256 encryption,
  scan-on-push enabled, lifecycle keeps last 20 tagged images, expires
  untagged after 7 days
- **RDS**: PostgreSQL 16, `publicly_accessible = false`,
  `manage_master_user_password = true` (password in Secrets Manager,
  never in Terraform), `deletion_protection = true`,
  `prevent_destroy = true`, Multi-AZ configurable, gp3 storage with
  autoscaling to 100 GB
- **Monitoring**: CloudWatch log groups with 30-day retention, Container
  Insights addon, node CPU alarm (>80% for 10 min), RDS storage alarm
  (<2 GB free)

---

## Task 6 — Troubleshooting

See `docs/troubleshooting.md` — 15 real-world scenarios with diagnostic
commands and root-cause patterns.

---

## Task 7 — Future improvements

See `docs/future-improvements.md` — 7 production hardening proposals
(HPA, GitOps, canary, logging, image signing, OPA Gatekeeper,
multi-region DR) with what/why/how/risk-removed for each.
