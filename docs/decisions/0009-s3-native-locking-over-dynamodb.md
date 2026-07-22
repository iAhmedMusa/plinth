# 0009. S3-native locking over DynamoDB for state locking

## Context

Remote Terraform state needs both storage and locking so two people (or
two CI runs) never apply against the same state file concurrently. The
long-standing pattern for the S3 backend pairs it with a DynamoDB table
purely to hold the lock.

## Decision

`terraform/backend.tf` documents an S3 backend using `use_lockfile`
(S3-native locking, available with Terraform ≥ 1.10 and recent AWS
provider versions) — no DynamoDB table is provisioned or referenced
anywhere in this repo.

## Alternatives considered

- **S3 + DynamoDB lock table (the traditional pattern).** Works on any
  Terraform version, is the long-established standard, and is what
  most existing documentation and tutorials describe. Rejected as the
  default here because it's a second AWS resource that exists purely
  for locking — it has to be provisioned, tagged, and kept in sync with
  the backend config (both the bucket and the table must be correctly
  referenced), for a purely mechanical purpose a newer Terraform
  version handles natively. The DynamoDB alternative remains documented
  in `terraform/README.md` section 2 for teams pinned to an older
  Terraform.

## Consequences

Fewer moving parts: one less resource to bootstrap out-of-band and keep
consistent with the backend configuration. The cost is a version floor
— this only works on Terraform ≥ 1.10 with AWS provider backend
support for `use_lockfile`; a team constrained to an older Terraform
would need the DynamoDB pattern instead, and migrating between the two
later is a real (if mechanical) state-backend change, not a
no-op. Since `backend.tf` here is entirely commented out — no real S3
bucket has ever been provisioned for this repo — this decision
describes the intended real setup rather than something exercised
today; the bucket itself would still need to be bootstrapped out-of-band
before any of this applies (see `terraform/README.md` section 2's
chicken-and-egg note).
