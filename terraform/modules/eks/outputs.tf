output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.this.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_ca" {
  description = "Base64-encoded cluster CA certificate."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "node_security_group_id" {
  description = "Security group ID attached to worker nodes -- referenced by RDS to allow only cluster nodes to reach the database."
  value       = aws_security_group.node.id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for IRSA."
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "cluster_log_group_name" {
  description = "CloudWatch log group for the EKS control plane -- owned here, pre-cluster, so Terraform (not EKS auto-creation) controls it."
  value       = aws_cloudwatch_log_group.cluster.name
}

output "oidc_provider_url" {
  description = "IAM OIDC provider issuer URL (without https://), used when writing IRSA trust policies."
  value       = replace(aws_eks_cluster.this.identity[0].oidc[0].issuer, "https://", "")
}
