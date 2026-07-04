# --- Cluster security group ---
# Attached to the control plane's cross-account ENIs placed in the private
# app subnets. Ingress is limited to node-to-control-plane traffic; nodes
# reach the API server on 443, the control plane reaches kubelet on 10250
# for exec/logs/port-forward.

resource "aws_security_group" "cluster" {
  name_prefix = "${var.name_prefix}-eks-cluster-"
  description = "EKS control plane ENIs"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-eks-cluster"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "cluster_ingress_from_nodes" {
  description              = "Nodes to control plane API (443)"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
}

resource "aws_security_group_rule" "cluster_egress_to_nodes" {
  description              = "Control plane to kubelet (10250) for exec/logs/port-forward"
  type                     = "egress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
}

# Symmetric to the node SG's "control plane to webhook (443)" ingress rule
# below -- without this egress leg, that ingress rule could never carry
# traffic through this SG pair (admission webhooks, aggregated API
# servers like metrics-server).
resource "aws_security_group_rule" "cluster_egress_to_nodes_webhook" {
  description              = "Control plane to webhook / aggregated API (443)"
  type                     = "egress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.cluster.id
  source_security_group_id = aws_security_group.node.id
}

# --- Node security group ---

resource "aws_security_group" "node" {
  name_prefix = "${var.name_prefix}-eks-node-"
  description = "EKS worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name                                           = "${var.name_prefix}-eks-node"
    "kubernetes.io/cluster/${var.name_prefix}-eks" = "owned"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "node_ingress_self" {
  description       = "Node to node (CNI, kube-proxy, DNS, etc.)"
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  security_group_id = aws_security_group.node.id
  self              = true
}

resource "aws_security_group_rule" "node_ingress_from_cluster" {
  description              = "Control plane to kubelet (10250)"
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
}

resource "aws_security_group_rule" "node_ingress_from_cluster_dns" {
  description              = "Control plane to CoreDNS webhook / admission (443)"
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node.id
  source_security_group_id = aws_security_group.cluster.id
}

resource "aws_security_group_rule" "node_egress_all" {
  description       = "Nodes reach the internet via NAT (image pulls, AWS APIs) and each other"
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.node.id
}
