variable "name_prefix" {
  description = "Prefix applied to every repository name."
  type        = string
}

variable "repository_names" {
  description = "Short names for each repository, e.g. [\"backend\", \"frontend\"]. Full repo name is name_prefix-<repository_name>."
  type        = list(string)
  default     = ["backend", "frontend"]
}

variable "tags" {
  description = "Common tags merged onto every resource."
  type        = map(string)
  default     = {}
}
