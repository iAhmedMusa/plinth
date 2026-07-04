# Terraform — AWS platform (EKS, ECR, RDS, monitoring)

Provisions the production platform this repo's k8s manifests
(`../k8s/`) run on top of: a three-tier VPC, an EKS cluster with a managed
node group and IRSA, two ECR repositories, a private RDS PostgreSQL
instance, and CloudWatch monitoring.

**Every module here is custom** — no `terraform-aws-modules/*` or any
other registry/third-party module. Only the official `hashicorp/aws` and
`hashicorp/tls` providers are used.

```
terraform/
  provider.tf, backend.tf, main.tf, variables.tf, outputs.tf
  terraform.tfvars.example
  envs/{dev,staging,production}.tfvars
  modules/{network,eks,ecr,rds,monitoring}/
```

## 1. How to use

```
cd terraform
terraform init                              # after uncommenting backend.tf, see section 2
terraform plan  -var-file=envs/dev.tfvars
terraform apply -var-file=envs/dev.tfvars
```

**tfvars-per-environment, not workspaces.** Each environment gets its own
`envs/<env>.tfvars` and its own state file (a distinct backend `key`, see
section 2) rather than `terraform workspace new staging`. Workspaces share
one backend configuration and the same state *file family*, which means a
single `terraform destroy` in the wrong workspace, or a provider/version
bump applied "everywhere at once," can reach across environments. Separate
tfvars + separate state keys give production a completely separate blast
radius from dev — a mistake in dev's state can't touch production's, full
stop, because they're not even the same file.

## 2. Remote backend & state locking

`backend.tf` is deliberately commented out — there is no real S3 bucket
for this assessment to point at, and Terraform can't create the bucket
that stores its own state (chicken-and-egg), so the bucket is provisioned
out-of-band, by hand or a one-time bootstrap script, before `backend.tf`
is ever uncommented:

```
bucket: versioning enabled, SSE enabled (SSE-S3 or SSE-KMS), public
access blocked, and a bucket policy denying non-TLS requests.
```

Locking uses **S3-native locking** (`use_lockfile = true`, Terraform ≥
1.10 with a compatible AWS provider) — a conditional-write lock file
alongside the state object in the same bucket, no second resource to
create, tag, or keep in sync with the backend block. The **legacy
alternative** is a separate DynamoDB table with a `LockID` hash key,
referenced via the backend's `dynamodb_table` argument — still fully
supported and still the right call if you're on a Terraform/provider
version older than the native-locking cutover, but it's one more resource
to provision and IAM-permission before the backend even works.

**Why remote state at all:** a laptop-local `terraform.tfstate` has no
locking (two people can `apply` concurrently and corrupt each other's
state), no shared visibility (nobody else can `plan` against the real
world), and is one `rm -rf` away from losing the only record of what's
actually deployed. State — remote or local — is never committed to git
(`.gitignore` excludes `.terraform/`, `*.tfstate*`).

## 3. Safe EKS upgrades

1. **Control plane first, one minor version at a time** (e.g. 1.29 →
   1.30, never 1.29 → 1.31 directly) — `kubernetes_version` in the
   relevant `envs/*.tfvars`, then `terraform apply`. EKS handles the
   control plane upgrade with no node disruption; this step alone doesn't
   touch running pods.
2. **Check add-on / API compatibility before and after**: run
   [`kubent`](https://github.com/doitintl/kube-no-trouble) or
   [`pluto`](https://github.com/FairwindsOps/pluto) against the cluster to
   catch manifests using APIs removed in the target minor version — fix
   those *before* upgrading, not after.
3. **Node groups next, surge-and-replace, never in-place**: create a new
   `aws_eks_node_group` on the new AMI/version (`create_before_destroy`
   is already set on the node group resource — see `modules/eks/README.md`),
   let it join and go `Ready`, cordon the old group, drain it pod by pod,
   then remove the old node group once it's empty.
4. **PDBs make the drain safe.** This repo's k8s manifests already define
   `PodDisruptionBudget`s for backend and frontend
   (`../k8s/base/pdb.yaml`) — `kubectl drain` respects them, so draining
   an old node group can't take out every replica of a deployment at
   once, regardless of how the EKS upgrade is sequenced.
5. **Check `update_config.max_unavailable`** (set to `1` in
   `modules/eks/main.tf`) before any managed node group version bump done
   via node group in-place update instead of the create-new-group pattern
   above — it bounds how many nodes are replaced concurrently.

## 4. Add/resize node pools

- **New pool**: add another `aws_eks_node_group` resource (or convert
  `modules/eks/main.tf`'s single node group to a `for_each` over a map
  variable, if more than one pool becomes a recurring need) with its own
  instance type/scaling config — useful for a GPU pool, a spot-instance
  pool, or an isolated pool for a noisy workload.
- **Resize an existing pool**: change `node_desired_size` /
  `node_min_size` / `node_max_size` in the relevant `envs/*.tfvars` and
  apply. Note `modules/eks/main.tf` sets
  `lifecycle { ignore_changes = [scaling_config[0].desired_size] }` on the
  node group specifically so a cluster-autoscaler (or a manual
  `kubectl scale`-equivalent AWS API call) adjusting live desired count
  isn't fought by the next `terraform apply` reverting it back to the
  tfvars value — min/max still come from Terraform, desired capacity is
  runtime-owned once the group exists.
- **Zero-downtime pattern for either case**: create the new/resized
  capacity, wait for `Ready`, verify workloads schedule and pass health
  checks on it, only then cordon+drain and remove old capacity. Same
  create-before-destroy shape as the upgrade path in section 3.

## 5. Avoiding downtime during cluster changes

- **Immutable-ish infrastructure, not in-place node mutation.** Nodes are
  never patched or SSH'd into to change their AMI/config — a changed node
  group is a *new* node group (section 3/4), and the old one is drained
  and removed only after the new one is proven healthy.
- **`create_before_destroy`** is set on the node group and both security
  groups (`modules/eks/main.tf`, `modules/eks/security.tf`,
  `modules/rds/main.tf`) so a forced replacement provisions the
  replacement before tearing down the original, avoiding a capacity or
  connectivity gap mid-change.
- **PDBs + multi-replica deployments.** Every app deployment already runs
  2+ replicas across nodes (`../k8s/base/*-deployment.yaml`) with PDBs
  guaranteeing a minimum available count during any voluntary disruption
  — node drains, cluster-autoscaler scale-downs, and the upgrade sequence
  above all go through the same eviction API that PDBs govern.
- **`prevent_destroy` on the EKS cluster and RDS instance** (see section 8)
  stops the single most disruptive possible "change" — an accidental full
  replacement — from ever happening via an unreviewed `apply`.

## 6. dev/staging/production separation

- **Separate state files.** Each environment's `envs/*.tfvars` pairs with
  its own backend `key` (e.g. `devops-assessment/dev/terraform.tfstate`,
  `.../staging/...`, `.../production/...`) in the same S3 bucket —
  distinct state, distinct lock, distinct blast radius (section 1).
- **Separate AWS accounts is the real-world gold standard**, not just
  separate state keys within one account: an IAM policy bug, a
  service-quota exhaustion, or a compromised credential in one account
  structurally cannot reach another account's resources, which is a
  stronger guarantee than any in-account IAM boundary can offer. This repo
  uses one account with tfvars-based separation because provisioning three
  real AWS accounts is out of scope for an assessment that will never be
  applied — but the module/tfvars structure here maps directly onto a
  three-account setup: point each environment's backend config and
  provider credentials (via OIDC role assumption, see section 7) at its
  own account, nothing else in this repo changes.
- **Naming/tagging.** `local.name_prefix = "${var.cluster_name}-${var.environment}"`
  (`main.tf`) means every resource name carries its environment
  unambiguously, and `local.common_tags` (also `main.tf`) stamps
  `Environment`, `ManagedBy`, and `Project` onto everything via the
  provider's `default_tags` — cost allocation and "what environment is
  this" are answerable from the AWS console alone, no tribal knowledge
  required.

## 7. Secrets outside Terraform

- **The database password never exists as a Terraform variable.**
  `manage_master_user_password = true` (`modules/rds/main.tf`) tells RDS to
  generate and hold the master password in AWS Secrets Manager; Terraform
  never reads or writes the plaintext value, so it cannot appear in a
  `.tfvars` file, a `plan` diff, or state. See `modules/rds/README.md` for
  the `random_password` + SSM alternative some teams prefer, and why this
  project defaults to the Secrets-Manager-managed approach instead.
- **Application pods read the real secret at runtime**, not at deploy
  time: External Secrets Operator or the Secrets Store CSI driver, running
  under an IRSA-scoped IAM role (the OIDC provider in `modules/eks/iam.tf`
  is exactly what makes that possible), pulls the Secrets-Manager value
  into the pod. No connection string or password is ever baked into an
  image, a ConfigMap, or a plain Kubernetes `Secret` checked into git —
  this repo's `k8s/base/backend-secret-example.yaml` is explicitly labeled
  local-dev-only for exactly this reason.
- **The pipeline never holds long-lived cloud keys.** `docs/ci-cd.md`
  (section 5) already documents GitHub OIDC federation for the real
  AWS-auth path — `aws-actions/configure-aws-credentials` exchanging a
  short-lived STS token per run, `role-to-assume` scoped to exactly the
  actions that job needs. Nothing about this Terraform phase changes that
  — the same OIDC role would apply `terraform apply` in CI exactly the way
  the mock ECR-push step describes for image pushes.

## 8. "Terraform wants to recreate the cluster — what to check"

Before ever approving a plan that shows the EKS cluster or RDS instance as
force-replaced (`-/+` in the plan, not `~`):

1. **Which specific field triggered it.** `terraform plan` names the
   forces-replacement attribute directly — for `aws_eks_cluster` that's
   almost always `name`, `vpc_config[0].subnet_ids` (changing the subnet
   *set*, not just adding one), or `role_arn`; for `aws_db_instance` it's
   usually `identifier`, `engine` (not `engine_version` — that upgrades
   in place), or the subnet group changing AZ coverage.
2. **A provider version jump.** Check the AWS provider's changelog for the
   version being upgraded to/from — providers occasionally change a
   resource's `ForceNew` behavior on a previously-mutable field between
   minor versions.
3. **A renamed resource in this configuration**, not a renamed AWS
   resource — if a module refactor changed a resource's local name (e.g.
   `aws_eks_cluster.this` → `aws_eks_cluster.main`), Terraform sees a
   delete-then-create by default. Run `terraform state mv` to reassociate
   the existing resource with its new address instead of letting it plan
   a real destroy/create.
4. **Imported or manual drift.** Something changed outside Terraform
   (console click, another automation) that Terraform now wants to
   "correct" via replacement rather than update — `terraform plan` showing
   replacement for a field nobody intentionally touched in this repo is
   the signal to check CloudTrail before applying anything.
5. **The `prevent_destroy` guard is the backstop, not the first line of
   defense.** Both `aws_eks_cluster.this` (`modules/eks/main.tf`) and
   `aws_db_instance.this` (`modules/rds/main.tf`) set
   `lifecycle { prevent_destroy = true }` — Terraform refuses to even
   produce a plan that destroys either resource while this is set, so a
   force-replacement on either one fails loudly at `plan` time instead of
   silently succeeding at `apply` time. Removing that guard is itself a
   reviewed, deliberate code change — never done to "get past" an
   unexplained replacement plan.

## 9. Validation status (honest)

- `terraform fmt -check -recursive` — **passes**, clean.
- `terraform init -backend=false && terraform validate` — **passes**,
  clean, for the root module and every module in `modules/`.
- `terraform plan -var-file=envs/dev.tfvars` (and `staging`/`production`)
  — **passes**, with `AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test`
  placeholder credentials and no real AWS account reachable. Produces a
  coherent 58-resource create plan for `dev`, 0 changes, 0 destroys.
- `tflint --recursive` (with the `aws` ruleset plugin) — **passes**, zero
  findings.
- **This configuration has never been applied, and no AWS account has
  been charged for it.** Two things made a fully credential-free plan
  possible rather than merely aspirational:
  - No data source depends on a live AWS account to resolve during
    `plan`. The one place that pattern would normally show up — AZ
    discovery — is deliberately replaced with `${region}a/b/c` string
    construction in `modules/network/main.tf` instead of
    `data "aws_availability_zones"`, which does need real credentials.
    `data "tls_certificate"` in `modules/eks/iam.tf` depends on the
    cluster's own OIDC issuer URL, which is unknown on a new cluster's
    first plan — Terraform defers data sources with unknown required
    inputs to apply time automatically, so this doesn't block `plan`
    either, it just means the OIDC provider itself is only actually
    creatable on a real `apply` against a real account.
  - `provider.tf` sets `skip_credentials_validation`,
    `skip_requesting_account_id`, and `skip_region_validation` — these
    skip the provider's upfront STS/account-ID ping, nothing more. They do
    not weaken any authorization on real resource calls; an `apply` with
    invalid credentials still fails at the first actual API call exactly
    as it would without these flags.
- **What applying this for real would additionally require:** the S3
  state bucket bootstrapped out-of-band (section 2), `backend.tf`
  uncommented with a real bucket/key, real AWS credentials supplied via
  OIDC federation or SSO (never static long-lived keys, section 7), and —
  given `prevent_destroy` is set on the cluster and database — a
  deliberate decision if either ever needs to be destroyed rather than
  updated in place.
