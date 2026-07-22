# Upgrades

EKS, node group, and Terraform upgrade paths. Pulled from
[`terraform/README.md`](../../terraform/README.md) sections 3–5, which
remain the source of truth for the underlying Terraform mechanics — this
page is the operational summary.

## 1. EKS control plane upgrades

1. **One minor version at a time** (e.g. 1.29 → 1.30, never 1.29 → 1.31
   directly) — bump `kubernetes_version` in the relevant
   `envs/*.tfvars`, then `terraform apply`. EKS handles the control
   plane upgrade with no node disruption; this step alone doesn't touch
   running pods.
2. **Check add-on / API compatibility before and after** — run
   [`kubent`](https://github.com/doitintl/kube-no-trouble) or
   [`pluto`](https://github.com/FairwindsOps/pluto) against the cluster
   to catch manifests using APIs removed in the target minor version.
   Fix those *before* upgrading, not after.

## 2. Node group upgrades

3. **Surge-and-replace, never in-place.** Create a new
   `aws_eks_node_group` on the new AMI/version
   (`create_before_destroy` is already set — see
   `terraform/modules/eks/README.md`), let it join and go `Ready`,
   cordon the old group, drain it pod by pod, then remove the old node
   group once it's empty.
4. **PDBs make the drain safe.** `k8s/base/pdb.yaml` already defines
   `PodDisruptionBudget`s for backend and frontend — `kubectl drain`
   respects them, so draining an old node group can't take out every
   replica of a deployment at once.
5. **`update_config.max_unavailable`** (set to `1` in
   `terraform/modules/eks/main.tf`) bounds how many nodes are replaced
   concurrently if you use an in-place node group version bump instead
   of the create-new-group pattern above.

## 3. Adding or resizing node pools

- **New pool:** add another `aws_eks_node_group` resource (or convert
  the module's single node group to a `for_each` over a map variable, if
  more than one pool becomes a recurring need) — useful for a GPU pool,
  a spot-instance pool, or an isolated pool for a noisy workload.
- **Resize an existing pool:** change `node_desired_size` /
  `node_min_size` / `node_max_size` in the relevant `envs/*.tfvars` and
  apply. `terraform/modules/eks/main.tf` sets
  `lifecycle { ignore_changes = [scaling_config[0].desired_size] }` so a
  cluster-autoscaler adjusting live desired count isn't fought by the
  next `terraform apply` reverting it back to the tfvars value —
  min/max still come from Terraform, desired capacity is runtime-owned
  once the group exists.
- **Zero-downtime pattern for either case:** create the new/resized
  capacity, wait for `Ready`, verify workloads schedule and pass health
  checks on it, only then cordon+drain and remove old capacity. Same
  create-before-destroy shape as the control-plane upgrade path above.

## 4. Terraform provider and module upgrades

- Check the AWS provider's changelog for `ForceNew` behavior changes on
  any field this repo sets before bumping `required_providers` — a
  provider upgrade changing a previously-mutable field's `ForceNew`
  status is the most common cause of an unexpected replacement plan
  (see [`docs/operations/runbook.md`](runbook.md), scenario 11).
- Run `terraform plan` for every environment (`dev`, `staging`,
  `production`) after any provider or module version bump, before
  merging — a clean `dev` plan does not guarantee a clean `production`
  plan if the environments have diverged in tfvars.

## 5. Avoiding downtime during any of the above

- **Immutable-ish infrastructure, not in-place node mutation.** Nodes
  are never patched or SSH'd into to change their AMI/config — a
  changed node group is a *new* node group, and the old one is drained
  and removed only after the new one is proven healthy.
- **`create_before_destroy`** is set on the node group and both
  security groups (`terraform/modules/eks/main.tf`,
  `terraform/modules/eks/security.tf`, `terraform/modules/rds/main.tf`)
  so a forced replacement provisions the replacement before tearing
  down the original.
- **`prevent_destroy` on the EKS cluster and RDS instance** stops the
  single most disruptive possible "change" — an accidental full
  replacement — from happening via an unreviewed `apply`. See
  [`docs/operations/runbook.md`](runbook.md) scenario 11 for what to do
  when a plan shows one anyway.
