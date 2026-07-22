# Architecture decisions

Short decision records for choices in this repo that have a real
alternative someone might reasonably ask "why not X instead?" about.
Format: Context / Decision / Alternatives considered / Consequences.

| ADR | Decision |
|---|---|
| [0001](0001-kustomize-over-helm.md) | Kustomize over Helm for environment overlays |
| [0002](0002-oidc-federation-over-long-lived-credentials.md) | OIDC federation over long-lived cloud credentials in CI |
| [0003](0003-security-group-to-security-group-over-cidr.md) | Security-group-to-security-group rules over CIDR blocks |
| [0004](0004-secrets-manager-over-terraform-managed-secrets.md) | Secrets Manager over Terraform-managed secrets |
| [0005](0005-default-deny-networkpolicy-posture.md) | Default-deny NetworkPolicy posture |
| [0006](0006-multi-arch-images-and-trivy-gate.md) | Multi-arch images + Trivy gate in the release path |
| [0007](0007-ephemeral-kind-cluster-over-persistent-staging.md) | Ephemeral kind cluster for staging verification over a persistent staging environment |
| [0008](0008-custom-terraform-modules-over-registry-modules.md) | Custom Terraform modules over community registry modules |
| [0009](0009-s3-native-locking-over-dynamodb.md) | S3-native locking over DynamoDB for state locking |
| [0010](0010-mocked-ecr-and-production-push.md) | Mocked ECR push and production deploy over a real cloud account |
