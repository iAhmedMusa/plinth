variable "name_prefix" {
  description = "Prefix applied to every resource name in this module (e.g. devops-assessment-production)."
  type        = string
}

variable "region" {
  description = "AWS region the VPC is created in. Drives the AZ list -- see azs local in main.tf."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Must be large enough for 9 /20-or-smaller subnets across 3 tiers x 3 AZs."
  type        = string
  default     = "10.0.0.0/16"
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for all AZs instead of one per AZ. true = cost-optimized (this assessment); false = one NAT per AZ for real HA production."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Common tags merged onto every resource."
  type        = map(string)
  default     = {}
}
