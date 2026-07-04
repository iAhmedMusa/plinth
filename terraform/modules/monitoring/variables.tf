variable "name_prefix" {
  description = "Prefix applied to every resource name in this module."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name -- used to name the cluster log group and to install the Container Insights addon."
  type        = string
}

variable "db_instance_id" {
  description = "RDS instance identifier the free-storage alarm watches."
  type        = string
}

variable "log_retention_days" {
  description = "CloudWatch log group retention, in days."
  type        = number
  default     = 30
}

variable "sns_topic_arn" {
  description = "SNS topic ARN alarms notify. Empty string = alarms exist with no notification target (visible in the console/API, nobody paged) -- wire this once an on-call channel exists."
  type        = string
  default     = ""
}

variable "node_cpu_alarm_threshold" {
  description = "Node CPU utilization percentage that triggers the high-CPU alarm."
  type        = number
  default     = 80
}

variable "rds_free_storage_threshold_bytes" {
  description = "RDS free storage space (bytes) below which the low-storage alarm fires."
  type        = number
  default     = 2000000000 # 2 GiB
}

variable "tags" {
  description = "Common tags merged onto every resource."
  type        = map(string)
  default     = {}
}
