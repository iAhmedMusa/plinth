# Three AZ suffixes derived from the region string rather than a live
# `data "aws_availability_zones"` lookup. That data source needs valid AWS
# credentials to resolve at plan time; hardcoding the a/b/c suffixes keeps
# `terraform plan` runnable with placeholder credentials, which is a hard
# requirement for this assessment (see terraform/README.md, section 9).
# Every commercial AWS region has at least 3 AZs, so a/b/c is safe.
locals {
  azs = [
    "${var.region}a",
    "${var.region}b",
    "${var.region}c",
  ]

  # Three tiers x 3 AZs = 9 subnets. cidrsubnet carves the VPC CIDR into
  # /20 blocks (16 available with a /16 VPC); tiers are laid out in
  # contiguous blocks so the CIDR ranges are easy to reason about from the
  # VPC CIDR alone.
  public_subnet_cidrs = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_app_cidrs   = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i + 3)]
  private_db_cidrs    = [for i in range(3) : cidrsubnet(var.vpc_cidr, 4, i + 6)]
  nat_gateway_count   = var.single_nat_gateway ? 1 : 3
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, {
    Name = var.name_prefix
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-igw"
  })
}

# --- Public tier: ALB / NAT gateways only. No workload ever runs here. ---

resource "aws_subnet" "public" {
  count                   = 3
  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public-${local.azs[count.index]}"
    Tier = "public"
    # Required by the AWS Load Balancer Controller to auto-discover
    # subnets for internet-facing ALBs/NLBs it provisions.
    "kubernetes.io/role/elb" = "1"
  })
}

# --- Private app tier: EKS worker nodes. Outbound via NAT, no inbound from the internet. ---

resource "aws_subnet" "private_app" {
  count             = 3
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_app_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-app-${local.azs[count.index]}"
    Tier = "private-app"
    # Required by the AWS Load Balancer Controller to auto-discover
    # subnets for internal ALBs/NLBs it provisions.
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# --- Private db tier: RDS only. No NAT route -- fully isolated, not even outbound internet. ---
# The database never needs to reach the internet (no package installs, no
# outbound calls), so it gets no default route at all. This is a stronger
# guarantee than a security group alone: even a misconfigured SG can't leak
# a connection out through a NAT path that doesn't exist.

resource "aws_subnet" "private_db" {
  count             = 3
  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_db_cidrs[count.index]
  availability_zone = local.azs[count.index]

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-db-${local.azs[count.index]}"
    Tier = "private-db"
  })
}

# --- NAT gateways: single by default (cost trade-off), one per AZ if single_nat_gateway=false ---
# A single NAT gateway is a shared failure point across all 3 AZs -- one
# per AZ removes that at ~3x the hourly + data-processing cost. Defaulting
# to single here is a deliberate cost choice for this assessment; flip
# single_nat_gateway=false for real production HA.

resource "aws_eip" "nat" {
  count  = local.nat_gateway_count
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-eip-${count.index}"
  })
}

resource "aws_nat_gateway" "this" {
  count         = local.nat_gateway_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-nat-${count.index}"
  })

  depends_on = [aws_internet_gateway.this]
}

# --- Route tables ---

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-public"
  })
}

resource "aws_route_table_association" "public" {
  count          = 3
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One private route table per AZ so each AZ's app subnet only egresses
# through its own NAT gateway when single_nat_gateway=false (avoids
# cross-AZ NAT data-processing charges); with a single NAT they all just
# point at the same gateway.
resource "aws_route_table" "private_app" {
  count  = 3
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-app-${local.azs[count.index]}"
  })
}

resource "aws_route_table_association" "private_app" {
  count          = 3
  subnet_id      = aws_subnet.private_app[count.index].id
  route_table_id = aws_route_table.private_app[count.index].id
}

# Db route table has NO default route -- no IGW, no NAT. Only the local
# VPC route that AWS adds implicitly. This is what "fully isolated" means
# in practice: there is no path out of these subnets to anywhere but the
# VPC itself.
resource "aws_route_table" "private_db" {
  vpc_id = aws_vpc.this.id

  tags = merge(var.tags, {
    Name = "${var.name_prefix}-private-db"
  })
}

resource "aws_route_table_association" "private_db" {
  count          = 3
  subnet_id      = aws_subnet.private_db[count.index].id
  route_table_id = aws_route_table.private_db.id
}
