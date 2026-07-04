output "identifier" {
  description = "RDS instance identifier -- consumed by the monitoring module's free-storage alarm."
  value       = aws_db_instance.this.identifier
}

output "endpoint" {
  description = "RDS connection endpoint (host:port)."
  value       = aws_db_instance.this.endpoint
  sensitive   = true
}

output "port" {
  description = "RDS port."
  value       = aws_db_instance.this.port
}

output "security_group_id" {
  description = "RDS security group ID."
  value       = aws_security_group.db.id
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN holding the RDS-managed master password."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}
