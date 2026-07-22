# 0002. OIDC federation over long-lived cloud credentials in CI

## Context

The CI pipeline and, eventually, application pods need to authenticate
against AWS. The easy path — an IAM user's static access key stored as
a GitHub secret — is also the one that leaves a long-lived credential
sitting somewhere it can be leaked from.

## Decision

Use GitHub's OIDC identity provider to obtain short-lived AWS
credentials at run time (`aws-actions/configure-aws-credentials` with
`role-to-assume`), documented in `.github/workflows/deploy.yml`'s mock
ECR step and `docs/ci-cd.md` section 4. Inside the cluster, the same
pattern extends via IRSA: `terraform/modules/eks/iam.tf` provisions an
IAM OIDC provider from the EKS cluster's own issuer, so pods assume
roles through Kubernetes service accounts rather than node-level or
static credentials.

## Alternatives considered

- **Static IAM access keys as GitHub Secrets.** Simpler to wire up —
  no trust-policy configuration required. Rejected because a leaked key
  is valid until someone manually rotates or revokes it, with no
  built-in expiry, and it grants the same access whether the workflow
  run is legitimate or not.
- **A single broad CI IAM role reused everywhere.** Rejected in favor
  of scoping `role-to-assume` per job/purpose — a compromised workflow
  run should not have more reach than that specific job needs.

## Consequences

No cloud credential of any kind is ever stored at rest in this repo —
each run exchanges a token for a few minutes of scoped access via STS,
and that token is useless outside the run that requested it. The cost
is setup complexity: an IAM OIDC provider and a trust policy must exist
in the target AWS account before this works, which is exactly the
chicken-and-egg problem this repo is in today (no real account backs
it, see ADR-0010) — the mock ECR step's comments describe the real
path without executing it. IRSA carries the same tradeoff inside the
cluster: it requires the OIDC provider to exist, which only happens on
a real `terraform apply`, not on `plan`.
