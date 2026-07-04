resource "aws_db_subnet_group" "this" {
  name       = "${var.name_prefix}-db"
  subnet_ids = var.private_db_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db"
  })
}

# Security-group-to-security-group reference (not a CIDR) is the network-
# level enforcement of "only the backend can reach the database": as the
# node fleet scales up/down or gets replaced, this rule tracks it
# automatically with no CIDR to keep in sync, and no other resource in the
# VPC -- however it's addressed -- can reach 5432 without also being a
# member of the node security group.
resource "aws_security_group" "db" {
  name_prefix = "${var.name_prefix}-rds-"
  description = "RDS PostgreSQL -- inbound only from EKS worker nodes"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-rds"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "db_ingress_from_nodes" {
  description              = "EKS nodes to PostgreSQL"
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.db.id
  source_security_group_id = var.node_security_group_id
}

resource "aws_db_instance" "this" {
  identifier     = "${var.name_prefix}-db"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username
  # No plaintext password anywhere in this config, in state, or in tfvars.
  # RDS generates and stores the master password in Secrets Manager, and
  # rotates/retrieves it entirely outside Terraform's knowledge. See
  # README for the random_password + SSM alternative and why this is
  # preferred.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.db.id]

  # THE core requirement for this database: it is never reachable from
  # the internet, full stop -- reinforced by the db-tier subnets having no
  # route to an internet gateway or NAT gateway at all (see network
  # module), so this flag is redundant-by-design, not the only guard.
  publicly_accessible = false

  multi_az = var.multi_az

  backup_retention_period   = var.backup_retention_days
  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${var.name_prefix}-db-final-${formatdate("YYYYMMDDhhmmss", timestamp())}"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-db"
  })

  lifecycle {
    # Mirrors the EKS cluster's guard: a forced replacement here means
    # data loss unless the final snapshot is restored first. Never let
    # that happen from an unreviewed plan. See root README, section 8.
    prevent_destroy = true
    # timestamp() in final_snapshot_identifier would otherwise show a
    # perpetual diff on every plan; the identifier only matters at the
    # moment of an actual delete, not on every unrelated plan.
    ignore_changes = [final_snapshot_identifier]
  }
}
