# Remote state in S3 with S3-native locking (`use_lockfile`, Terraform
# >= 1.10 / AWS provider backend support) -- no DynamoDB table to
# provision and keep in sync with the backend config. The bucket itself is
# created out-of-band (chicken-and-egg: Terraform can't create the bucket
# that stores its own state), with versioning and SSE enabled by hand or
# via a one-time bootstrap script -- never by this configuration. See
# README.md, section 2, for the full rationale and the legacy
# DynamoDB-table-locking alternative.
#
# Values are intentionally commented out: this repo has no real bucket to
# point at, and committing a real bucket name/key here would be the first
# step toward a real deployment this assessment explicitly does not make.
# Uncomment and fill in before ever running `terraform init` for real.
#
# terraform {
#   backend "s3" {
#     bucket       = "devops-assessment-tfstate-<account-id>"
#     key          = "devops-assessment/<environment>/terraform.tfstate"
#     region       = "ap-southeast-1"
#     encrypt      = true
#     use_lockfile = true
#   }
# }
