output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_ca" {
  description = "Base64-encoded cluster CA certificate."
  value       = module.eks.cluster_ca
  sensitive   = true
}

output "ecr_repository_urls" {
  description = "Map of short repository name -> ECR repository URL."
  value       = module.ecr.repository_urls
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "private_subnet_ids" {
  description = "Private app-tier subnet IDs (EKS nodes)."
  value       = module.network.private_app_subnet_ids
}

output "rds_endpoint" {
  description = "RDS connection endpoint."
  value       = module.rds.endpoint
  sensitive   = true
}

output "log_group_names" {
  description = "CloudWatch log group names (cluster + application)."
  value = {
    cluster     = module.monitoring.cluster_log_group_name
    application = module.monitoring.application_log_group_name
  }
}
