output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (ALB / NAT tier)."
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "Private app subnet IDs (EKS node tier)."
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "Private db subnet IDs (RDS tier, no NAT route)."
  value       = aws_subnet.private_db[*].id
}

output "azs" {
  description = "Availability zones used by this VPC."
  value       = local.azs
}
