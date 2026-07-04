variable "name_prefix" {
  description = "Prefix applied to every resource name in this module."
  type        = string
}

variable "vpc_id" {
  description = "VPC the database and its security group live in."
  type        = string
}

variable "private_db_subnet_ids" {
  description = "Private db-tier subnet IDs (no NAT route) the DB subnet group spans."
  type        = list(string)
}

variable "node_security_group_id" {
  description = "EKS node security group ID -- the ONLY source allowed to reach the database on 5432. Security-group-to-security-group reference, never a CIDR, so the rule tracks the actual node fleet automatically."
  type        = string
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
}

variable "db_username" {
  description = "Master username. There is deliberately no db_password variable -- see README for why."
  type        = string
}

variable "multi_az" {
  description = "Enable Multi-AZ standby. false here (single-AZ, cost trade-off for this assessment); set true for real production HA."
  type        = bool
  default     = false
}

variable "backup_retention_days" {
  description = "Automated backup retention window, in days."
  type        = number
  default     = 7
}

variable "tags" {
  description = "Common tags merged onto every resource."
  type        = map(string)
  default     = {}
}
