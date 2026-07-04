variable "name_prefix" {
  description = "Prefix applied to every resource name in this module."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS control plane version, e.g. 1.30."
  type        = string
}

variable "vpc_id" {
  description = "VPC the cluster and nodes live in."
  type        = string
}

variable "private_app_subnet_ids" {
  description = "Private app-tier subnet IDs the control plane ENIs and worker nodes are placed into."
  type        = list(string)
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public Kubernetes API endpoint. Restrict to office/VPN ranges in real production -- the fully-hardened option is endpoint_public_access=false plus a bastion/VPN, see module README."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group."
  type        = string
}

variable "node_desired_size" {
  description = "Desired worker node count."
  type        = number
}

variable "node_min_size" {
  description = "Minimum worker node count."
  type        = number
}

variable "node_max_size" {
  description = "Maximum worker node count."
  type        = number
}

variable "tags" {
  description = "Common tags merged onto every resource."
  type        = map(string)
  default     = {}
}
