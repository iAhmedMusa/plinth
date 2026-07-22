# Architecture

System overview: what runs where, how a request flows end to end, and the
tradeoffs made to keep this a reference deployment rather than a live one.

## 1. The workload

Two independent services, deployed as separate containers: a Next.js
frontend and a FastAPI backend, backed by PostgreSQL. The frontend proxies
`/api/*` to the backend internally; the backend is never exposed
directly. This app is deliberately small — see the root
[README.md](../README.md) — the point of this repository is the platform
underneath it, not the app itself.

## 2. Three tiers, one VPC

```
public          — ALB / ingress-nginx only
private-app     — EKS node group (frontend + backend pods)
private-db      — RDS PostgreSQL
```

Each tier is its own subnet group, one per AZ. Only the public tier has a
route to an Internet Gateway; private-app reaches the internet outbound
through a NAT gateway (for image pulls, package installs), and
private-db has no route out at all. See
[`terraform/README.md`](../terraform/README.md) for the module that
provisions this.

## 3. Request path

```
browser -> ALB/ingress-nginx (public)
        -> frontend Service (ClusterIP, private-app)
        -> backend Service (ClusterIP, private-app, internal-only)
        -> RDS PostgreSQL (private-db)
```

The backend is never reachable except through the frontend's proxy, and
the database is never reachable except from backend pods. Full detail —
including what specifically blocks unauthorized traffic at each hop
(NetworkPolicy, security-group-to-security-group rules, ClusterIP-only
Services) — is in [`docs/networking.md`](networking.md).

## 4. What's real vs. mocked

- **Real:** the app, the CI pipeline's test/build/scan/release stages, the
  Docker Hub push, the ephemeral kind cluster staging deploy, and every
  Terraform module (`fmt`, `validate`, and `plan` all pass against real
  provider logic).
- **Mocked, on purpose:** the ECR push and the production deploy job.
  Both are labeled `[MOCK]` in `.github/workflows/deploy.yml` and only
  echo the command sequence a real run would execute — there is no AWS
  account backing this repo, so `terraform apply` has never been run for
  real either. See [`docs/ci-cd.md`](ci-cd.md) for why this line was
  drawn here rather than somewhere else.

## 5. Deliberate tradeoffs

| Decision | What it costs | What it buys |
|---|---|---|
| Single NAT gateway per environment (not one per AZ) | An AZ outage that takes the NAT gateway's AZ down loses egress for the whole private-app tier, not just one AZ's worth | Meaningfully lower cost for a reference deployment nobody is paying real traffic against |
| Single-AZ RDS by default (`multi_az = false`) | No automatic same-region failover | Avoids doubling the instance cost for a database with no real availability requirement |
| Ephemeral kind cluster for staging verification, not a persistent staging cluster | No long-lived environment to manually poke at between releases | Every staging deploy proves the images and manifests work together from a clean slate — no drift can hide in a cluster that no longer exists five minutes later |
| ECR push and production deploy mocked | The pipeline can't be pointed at a real account without someone doing that work first | The full job graph, the approval gate, and the OIDC-federation pattern are provable today, without provisioning a real AWS account for a repo with no production traffic |
| S3-native locking (`use_lockfile`) instead of a DynamoDB lock table | Requires Terraform ≥ 1.10 and recent AWS provider support | One fewer resource to provision and keep in sync with the backend config |

Each of these is written up as a full decision record — context,
alternatives considered, consequences — in
[`docs/decisions/`](decisions/).
