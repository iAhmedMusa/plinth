# 0010. Mocked ECR push and production deploy over a real cloud account

## Context

No AWS account backs this repo — nothing here has ever been applied
for real (see `terraform/README.md` section 9). The pipeline should
still demonstrate the *shape* of a real release: build → scan →
registry push → release → staging deploy → production approval gate.

## Decision

`mock-ecr-push` and `deploy-production` are real jobs in the workflow's
job graph, gated exactly like a real deploy would be — tag-triggered,
`needs:` dependencies enforced, `deploy-production` declaring
`environment: production` with a required-reviewer rule configured in
repo settings. Each job is explicitly labeled `[MOCK]` in its name and
only echoes the exact command sequence a real run would execute; neither
calls the AWS API.

## Alternatives considered

- **Omit these jobs and describe the intended production path in
  prose only.** Rejected — a described pipeline and a provable one
  read very differently to a reviewer. The mock jobs still prove the
  job graph, the gating conditions, and the approval-rule wiring are
  real, even though the AWS calls inside them aren't.
- **Provision a real (free-tier) AWS account and actually push to
  ECR / deploy to a real cluster.** Considered and rejected on scope,
  cost, and security-surface grounds for a portfolio repository with no
  production traffic to protect — this is precisely the gap the
  roadmap's "why not built yet" reasoning is honest about, not an
  oversight.

## Consequences

The required-reviewer gate on the `production` GitHub environment is
real and currently guards a job that does nothing — an explicitly
disclosed limitation (both here and in the job's own comments) rather
than a hidden one. The upside: swapping in a real AWS account later
requires no job-graph changes at all, only replacing the mock steps'
bodies with the real AWS CLI/OIDC calls already described in
`mock-ecr-push`'s comments (see ADR-0002) — the gating logic,
dependencies, and approval rule stay exactly as they are today.
