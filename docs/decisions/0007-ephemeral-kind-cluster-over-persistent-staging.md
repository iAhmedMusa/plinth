# 0007. Ephemeral kind cluster for staging verification over a persistent staging environment

## Context

The release pipeline needs to prove the manifests and the just-built
images actually come up together — not just that the YAML parses — on
every tagged release.

## Decision

`deploy-staging` creates a single-node kind cluster inside the GitHub
Actions runner, installs ingress-nginx, applies `k8s/overlays/ci` with
images pinned to the release just built, waits for both rollouts, runs
two smoke tests (in-cluster backend health check, ingress reachability
from the runner), then destroys the entire cluster when the job ends.
Nothing here is a persistent environment.

## Alternatives considered

- **A persistent managed staging cluster (EKS).** More realistic — real
  cloud networking, real IAM, real ALB behavior. Rejected for this
  repo's scope: it costs money continuously for a repo with no real
  traffic, and it accumulates configuration drift between releases
  (leftover objects from a previous bad deploy that a fresh-every-time
  cluster can't have). Explicitly noted as the natural upgrade path:
  swapping in a persistent cluster later means replacing the kind-create
  step with a `kubectl` context switch authenticated via OIDC — the
  rest of the job graph is unchanged.
- **No staging deploy at all, tests only.** Rejected — it would leave
  "the manifests apply and the pods come up together" as an untested
  claim rather than a proven one on every release.

## Consequences

Every staging deploy starts from zero, so no configuration drift can
hide between releases — a strong guarantee a persistent cluster can't
offer without extra cleanup tooling. The tradeoff: this proves internal
consistency (images + manifests + Service wiring all work together), not
AWS-specific behavior — no real ALB, no real security groups, no real
IRSA are exercised here. That gap is exactly why `docs/architecture.md`
is explicit about what's real versus mocked in this pipeline.
