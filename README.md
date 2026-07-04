# DevOps Assessment

[![CI/CD](https://github.com/iAhmedMusa/devops-assessment/actions/workflows/deploy.yml/badge.svg)](https://github.com/iAhmedMusa/devops-assessment/actions/workflows/deploy.yml)

User profile manager: Next.js frontend, FastAPI backend, PostgreSQL database, all containerized.

## Architecture

    browser --> frontend:3000 --[Next.js rewrite /api/*]--> backend:8080 --> postgres:5432

The browser only ever talks to the frontend container. The frontend forwards
`/api/*` requests server-side to the backend using a Next.js rewrite rule.

## Prerequisites

- Docker and Docker Compose

## Run

    cp .env.example .env
    docker compose up -d --build

## Verify

    curl http://localhost:8080          # "Application is running"
    curl http://localhost:8080/health   # {"status":"ok"}

Open http://localhost:3000 and create/edit/delete a profile. Data persists
across `docker compose restart backend` because Postgres uses a named volume.

## Backend tests

    cd backend
    python3.12 -m venv .venv && source .venv/bin/activate
    pip install -r requirements-dev.txt
    pytest -v

No database needs to be running — tests use an in-memory SQLite override.

## Environment variables

| Service  | Variable          | Example                                              | Notes                              |
|----------|-------------------|-------------------------------------------------------|-------------------------------------|
| db       | POSTGRES_USER     | appuser                                                | from `.env`                         |
| db       | POSTGRES_PASSWORD | change-me                                              | from `.env`                         |
| db       | POSTGRES_DB       | appdb                                                  | from `.env`                         |
| backend  | DATABASE_URL      | postgresql+asyncpg://appuser:change-me@db:5432/appdb   | composed by compose from `.env`     |
| backend  | FRONTEND_ORIGINS  | http://localhost:3000                                  | comma-separated CORS origins        |
| frontend | BACKEND_URL       | http://backend:8080                                    | build-arg only — baked into the image at `docker build` time, see below |

## CI/CD

Pull requests run the backend and frontend test suites only. Pushing a
`v*.*.*` tag runs the full pipeline: tests, build and push to Docker Hub
with a Trivy vulnerability scan, a clearly-labeled mock ECR push, a GitHub
release, and a clearly-labeled mock Kubernetes deploy. Releases promote the
same immutable images through staging to production behind a manual
approval gate; see [docs/ci-cd.md](docs/ci-cd.md) for the trigger model,
image tagging policy, registry strategy, secrets management, and
branching/promotion strategy.

## Documentation

| Topic | Doc |
|-------|-----|
| CI/CD pipeline (triggers, tagging, promotion) | [docs/ci-cd.md](docs/ci-cd.md) |
| Kubernetes manifests & local deploy | [k8s/README.md](k8s/README.md) |
| Terraform provisioning (EKS, ECR, RDS, monitoring) | [terraform/README.md](terraform/README.md) |
| Private database connectivity (task 4) | [docs/database-connectivity.md](docs/database-connectivity.md) |
| Troubleshooting (15 real-world scenarios) | [docs/troubleshooting.md](docs/troubleshooting.md) |
| Future improvements (production hardening) | [docs/future-improvements.md](docs/future-improvements.md) |

## Design decisions

### Frontend-to-backend routing (build-time rewrite)

The browser only ever calls relative `/api/*` paths on the frontend. Next.js
forwards those requests server-side to the backend via a `rewrites()` rule,
so the backend never needs to be reachable from the browser directly and can
run as an internal-only (ClusterIP) service once this stack moves to
Kubernetes.

With `output: "standalone"`, `next.config.ts` is serialized at **build**
time. The rewrite destination is fixed into the built image the moment
`next build` runs — setting `BACKEND_URL` at container runtime has no effect
on it.

Convention: the backend is reachable as `http://backend:8080` in every
environment — that's the docker-compose service name today, and the
Kubernetes Service will also be named `backend` when that phase lands (a
constraint to carry forward, not just a default).

Trade-off, stated plainly: if the backend's address ever changes, this image
must be rebuilt — there is no runtime knob. The alternative we considered
was a per-request route-handler proxy (an `app/api/[...path]/route.ts` that
reads `BACKEND_URL` at request time instead of at build time), which would
support a true runtime override. We chose the simpler build-time convention
instead because the backend's address is stable across every environment
this project targets, so the extra proxy layer isn't earning its keep.
