terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.region

  # These three flags only skip the provider's upfront "ping" calls
  # (STS GetCallerIdentity for the account ID, a region-name lookup, and an
  # initial credential check) that run before any plan/apply logic. They do
  # not relax any authorization on the actual resource calls Terraform makes
  # -- an apply with invalid credentials still fails at the first real API
  # call, exactly as it would without these flags. They exist here solely so
  # `terraform plan` can run with placeholder credentials for this
  # assessment (see README.md, section 9); leaving them set is harmless
  # against a real account too; the account ID Terraform would have cached
  # from that ping is simply never used anywhere in this configuration.
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_region_validation      = true

  default_tags {
    tags = var.tags
  }
}
