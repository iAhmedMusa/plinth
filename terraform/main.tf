# Wiring only -- every actual resource lives inside modules/*. Nothing in
# this file provisions anything directly.

locals {
  name_prefix = "${var.cluster_name}-${var.environment}"

  common_tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = var.cluster_name
  })
}

module "network" {
  source = "./modules/network"

  name_prefix = local.name_prefix
  region      = var.region
  vpc_cidr    = var.vpc_cidr
  tags        = local.common_tags
}

module "eks" {
  source = "./modules/eks"

  name_prefix            = local.name_prefix
  kubernetes_version     = var.kubernetes_version
  vpc_id                 = module.network.vpc_id
  private_app_subnet_ids = module.network.private_app_subnet_ids
  node_instance_type     = var.node_instance_type
  node_desired_size      = var.node_desired_size
  node_min_size          = var.node_min_size
  node_max_size          = var.node_max_size
  tags                   = local.common_tags
}

module "ecr" {
  source = "./modules/ecr"

  name_prefix      = local.name_prefix
  repository_names = ["backend", "frontend"]
  tags             = local.common_tags
}

module "rds" {
  source = "./modules/rds"

  name_prefix            = local.name_prefix
  vpc_id                 = module.network.vpc_id
  private_db_subnet_ids  = module.network.private_db_subnet_ids
  node_security_group_id = module.eks.node_security_group_id
  db_instance_class      = var.db_instance_class
  db_name                = var.db_name
  db_username            = var.db_username
  tags                   = local.common_tags
}

module "monitoring" {
  source = "./modules/monitoring"

  name_prefix    = local.name_prefix
  cluster_name   = module.eks.cluster_name
  db_instance_id = module.rds.identifier
  tags           = local.common_tags
}
