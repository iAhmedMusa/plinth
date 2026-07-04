# Created BEFORE the cluster, and the cluster depends on it. With
# enabled_cluster_log_types set, EKS auto-creates
# /aws/eks/<name>/cluster the moment the control plane comes up -- if
# Terraform tried to create the same group afterwards (e.g. from a
# monitoring module that runs after this one), the first apply would fail
# with ResourceAlreadyExistsException. Owning it here, pre-cluster, means
# Terraform controls the retention policy too.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.name_prefix}-eks/cluster"
  retention_in_days = var.log_retention_days

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eks-cluster-logs"
  })
}

resource "aws_eks_cluster" "this" {
  name     = "${var.name_prefix}-eks"
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = var.private_app_subnet_ids
    security_group_ids      = [aws_security_group.cluster.id]
    endpoint_private_access = true
    # Public endpoint stays reachable so this cluster is manageable without
    # a bastion/VPN for the assessment, but access is restricted to
    # public_access_cidrs. The fully hardened option is
    # endpoint_public_access = false with a bastion host or VPN as the
    # only path to the private endpoint -- see module README for the
    # trade-off.
    endpoint_public_access = true
    public_access_cidrs    = var.public_access_cidrs
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eks"
  })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    # Log group must exist before EKS starts shipping control plane logs,
    # otherwise EKS creates it itself and Terraform's own create collides.
    aws_cloudwatch_log_group.cluster,
  ]

  lifecycle {
    # A cluster recreate is disruptive enough (new endpoint, new CA, every
    # node group replaced) that it should never happen silently from an
    # unreviewed plan -- see terraform/README.md, section 8.
    prevent_destroy = true
  }
}

resource "aws_eks_node_group" "default" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${var.name_prefix}-default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_app_subnet_ids
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_readonly,
  ]

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [scaling_config[0].desired_size]
  }
}
