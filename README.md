# Plinth

[![CI/CD](https://github.com/iAhmedMusa/devops-assessment/actions/workflows/deploy.yml/badge.svg)](https://github.com/iAhmedMusa/devops-assessment/actions/workflows/deploy.yml)

User profile manager — Next.js frontend, FastAPI backend, PostgreSQL database, all containerized and deployable to Kubernetes.

```
browser --> frontend:3000 --> backend:8080 --> postgres:5432
```

## Quick start

```bash
cp .env.example .env
docker compose up -d --build

curl http://localhost:8080          # "Application is running"
curl http://localhost:8080/health   # {"status":"ok"}
```

Open http://localhost:3000 to create, edit, and delete profiles.

## What was built (task by task)

### Task 1 — The app

Two independent services in separate Docker containers, started with one command. The frontend serves a profile management UI; the backend exposes `GET /` and `GET /health` plus a full CRUD API for profiles. PostgreSQL stores the data in a named volume. See [`backend/`](backend/) and [`frontend/`](frontend/) for details.

### Task 2 — CI/CD pipeline

A GitHub Actions workflow that runs on every PR (tests only) and on `v*.*.*` tags (full pipeline: test, build multi-arch images, push to Docker Hub, Trivy vulnerability scan, GitHub release, real staging deploy on an ephemeral kind cluster, mock production deploy behind a manual approval gate). Secrets live in GitHub Secrets; production cloud auth uses OIDC federation, not stored keys. See [docs/ci-cd.md](docs/ci-cd.md).

### Task 3 — Kubernetes manifests

Kustomize-based manifests with base + overlays (local, staging, production, CI). Both frontend and backend run 2 replicas with readiness/liveness probes, resource requests/limits, pod disruption budgets, network policies (default-deny ingress), and pod hardening (non-root, read-only rootfs, drop ALL caps). The backend is ClusterIP (internal-only); only the frontend is exposed through an Ingress. Config comes from a ConfigMap; secrets are referenced via a placeholder (real values injected at deploy time). See [k8s/README.md](k8s/README.md).

### Task 4 — Private database connectivity

The backend reaches PostgreSQL without the database ever being reachable from the internet. The setup uses a three-tier VPC (public / private-app / private-db), security-group-to-security-group firewall rules (not CIDR), Kubernetes NetworkPolicy restricting port 5432 to backend pods only, and AWS Secrets Manager for credential storage — the master password never exists in Terraform code. See [docs/networking.md](docs/networking.md).

### Task 5 — Infrastructure as code (Terraform)

Five custom modules (network, EKS, ECR, RDS, monitoring) provisioning a production-grade AWS platform: three-tier VPC, EKS cluster with managed node group and IRSA, ECR repos with lifecycle policies, private RDS PostgreSQL, and CloudWatch monitoring. Separate tfvars and state keys for dev/staging/production. `prevent_destroy` on critical resources. Full upgrade, resize, and drift-recovery procedures documented. See [terraform/README.md](terraform/README.md).

### Task 6 — Troubleshooting

Fifteen real-world failure scenarios — pods crashing, app unreachable, SSL errors, pipeline failures, database timeouts, secrets leaked, Terraform drift — with practical diagnostic commands and root-cause patterns. See [docs/operations/runbook.md](docs/operations/runbook.md).

### Task 7 — Future improvements

Seven production hardening proposals: HPA autoscaling, GitOps with ArgoCD, canary deployments, centralized logging, image signing, OPA Gatekeeper policies, and multi-region disaster recovery. Each with what/why/how/risk-removed. See [docs/roadmap.md](docs/roadmap.md).

## Environment variables

| Service  | Variable          | Example                                              | Notes                              |
|----------|-------------------|-------------------------------------------------------|-------------------------------------|
| db       | POSTGRES_USER     | appuser                                                | from `.env`                         |
| db       | POSTGRES_PASSWORD | change-me                                              | from `.env`                         |
| db       | POSTGRES_DB       | appdb                                                  | from `.env`                         |
| backend  | DATABASE_URL      | postgresql+asyncpg://appuser:change-me@db:5432/appdb   | composed by compose from `.env`     |
| backend  | FRONTEND_ORIGINS  | http://localhost:3000                                  | comma-separated CORS origins        |
| frontend | BACKEND_URL       | http://backend:8080                                    | build-arg — baked into the image    |

## Backend tests

```bash
cd backend
python3.12 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -v
```

No database needed — tests use an in-memory SQLite override.

## Documentation

| Topic | Doc |
|-------|-----|
| CI/CD pipeline | [docs/ci-cd.md](docs/ci-cd.md) |
| Kubernetes manifests | [k8s/README.md](k8s/README.md) |
| Terraform infrastructure | [terraform/README.md](terraform/README.md) |
| Private database connectivity | [docs/networking.md](docs/networking.md) |
| Runbook | [docs/operations/runbook.md](docs/operations/runbook.md) |
| Roadmap | [docs/roadmap.md](docs/roadmap.md) |
| Proof of work | [docs/proof.md](docs/proof.md) |
