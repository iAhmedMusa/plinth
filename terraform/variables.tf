variable "environment" {
  description = "Environment name: dev, staging, or production. Used in the name prefix and resource tags."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "production"], var.environment)
    error_message = "environment must be one of: dev, staging, production."
  }
}

variable "region" {
  description = "AWS region to provision into."
  type        = string
  default     = "ap-southeast-1"
}

variable "cluster_name" {
  description = "Base cluster name. The environment is appended to form the actual name prefix (see locals in main.tf)."
  type        = string
  default     = "devops-assessment"
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.30"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "node_instance_type" {
  description = "EC2 instance type for the EKS managed node group."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Desired worker node count."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum worker node count."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum worker node count."
  type        = number
  default     = 4
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_name" {
  description = "Initial application database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "RDS master username. There is deliberately no db_password variable -- see terraform/README.md, section 7."
  type        = string
  default     = "appuser"
}

variable "tags" {
  description = "Common tags applied to every resource via provider default_tags."
  type        = map(string)
  default     = {}
}
