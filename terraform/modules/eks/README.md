# eks module

## Purpose

EKS control plane, managed node group, IAM roles built from scratch, and
an OIDC provider for IRSA.

## Inputs

| Name | Description | Default |
|---|---|---|
| `name_prefix` | Resource name prefix | (required) |
| `kubernetes_version` | Control plane version | (required) |
| `vpc_id` | VPC ID | (required) |
| `private_app_subnet_ids` | Subnets for control plane ENIs + nodes | (required) |
| `public_access_cidrs` | CIDRs allowed to hit the public API endpoint | `["0.0.0.0/0"]` |
| `node_instance_type` | Node group instance type | (required) |
| `node_desired_size` / `node_min_size` / `node_max_size` | Node group scaling | (required) |
| `tags` | Common tags | `{}` |

## Outputs

| Name | Description |
|---|---|
| `cluster_name` | EKS cluster name |
| `cluster_endpoint` | API server endpoint |
| `cluster_ca` | CA cert, base64 (sensitive) |
| `node_security_group_id` | Node SG ID -- consumed by the rds module |
| `oidc_provider_arn` | IRSA OIDC provider ARN |
| `oidc_provider_url` | IRSA OIDC issuer URL (no scheme) |

## Design notes

- **IAM built from scratch.** Cluster and node roles are each a single
  `aws_iam_role` with only the AWS-managed policies EKS documents as
  required (`AmazonEKSClusterPolicy` for the control plane;
  `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`,
  `AmazonEC2ContainerRegistryReadOnly` for nodes). No inline wildcard
  policy anywhere.
- **Endpoint access.** `endpoint_private_access = true` always;
  `endpoint_public_access = true` restricted to `public_access_cidrs` so
  the cluster is reachable for this assessment without standing up a
  bastion/VPN. The fully hardened option for real production is
  `endpoint_public_access = false` with a bastion host or client VPN as
  the only path to the private endpoint — flip it once a VPN/bastion
  exists; nothing else in this module has to change.
- **Two security groups, minimal rules.** Cluster SG allows node->API
  (443 inbound) and control-plane->kubelet (10250 outbound). Node SG
  allows all traffic between nodes (CNI/kube-proxy/DNS), control
  plane->kubelet (10250) and control-plane->webhook (443) inbound, and
  unrestricted egress (nodes need to reach ECR, S3, STS, and pull images).
  Every rule is its own resource with a one-line reason in its
  `description`.
- **OIDC / IRSA.** The `tls_certificate` data source reads the cluster's
  own OIDC issuer certificate to derive the thumbprint the
  `aws_iam_openid_connect_provider` needs. Both the issuer URL and the
  thumbprint are unknown until the cluster exists, so on a brand-new
  cluster this data source and resource only resolve during `apply`, not
  the initial `plan` — Terraform defers data sources with unknown inputs
  automatically, so this does not break `terraform plan` (see root
  `README.md`, section 9). IRSA is what lets individual pods (e.g. External
  Secrets Operator) assume scoped IAM roles instead of every pod inheriting
  the node's IAM role wholesale.
- **`prevent_destroy` on the cluster.** A cluster replacement means a new
  endpoint, a new CA, and every node group rebuilt — costly enough that it
  should never happen from an unreviewed `plan`/`apply`. See root
  `README.md`, section 8, for what to check before ever removing this.
- **Node group `create_before_destroy` + `ignore_changes` on
  `desired_size`.** Replacing a node group (e.g. new AMI, new instance
  type) provisions the new one before tearing down the old, avoiding a
  capacity gap. `desired_size` is ignored post-creation so a
  cluster-autoscaler or manual scaling action isn't fought by the next
  `terraform apply`.
