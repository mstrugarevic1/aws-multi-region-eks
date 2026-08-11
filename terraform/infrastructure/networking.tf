# Purpose: Creates both regional VPCs and cross-region database connectivity.
# Modules: Uses terraform-aws-modules/vpc/aws once per region.

data "aws_availability_zones" "primary" {
  provider = aws.primary
  state    = "available"
}

data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  state    = "available"
}

module "primary_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  providers = { aws = aws.primary }

  name = "${var.project_name}-primary"
  cidr = var.primary_vpc_cidr
  azs  = slice(data.aws_availability_zones.primary.names, 0, 2)

  public_subnets   = [for i in range(2) : cidrsubnet(var.primary_vpc_cidr, 4, i)]
  private_subnets  = [for i in range(2) : cidrsubnet(var.primary_vpc_cidr, 4, i + 2)]
  database_subnets = [for i in range(2) : cidrsubnet(var.primary_vpc_cidr, 4, i + 4)]

  enable_nat_gateway                 = true
  single_nat_gateway                 = true
  enable_dns_support                 = true
  enable_dns_hostnames               = true
  create_database_subnet_route_table = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

module "secondary_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  providers = { aws = aws.secondary }

  name = "${var.project_name}-secondary"
  cidr = var.secondary_vpc_cidr
  azs  = slice(data.aws_availability_zones.secondary.names, 0, 2)

  public_subnets   = [for i in range(2) : cidrsubnet(var.secondary_vpc_cidr, 4, i)]
  private_subnets  = [for i in range(2) : cidrsubnet(var.secondary_vpc_cidr, 4, i + 2)]
  database_subnets = [for i in range(2) : cidrsubnet(var.secondary_vpc_cidr, 4, i + 4)]

  enable_nat_gateway                 = true
  single_nat_gateway                 = true
  enable_dns_support                 = true
  enable_dns_hostnames               = true
  create_database_subnet_route_table = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Peering carries cross-region database traffic, including writes from the
# secondary application to the current global writer.
resource "aws_vpc_peering_connection" "primary_to_secondary" {
  provider    = aws.primary
  vpc_id      = module.primary_vpc.vpc_id
  peer_vpc_id = module.secondary_vpc.vpc_id
  peer_region = var.secondary_region

  tags = { Name = "${var.project_name}-primary-secondary" }
}

resource "aws_vpc_peering_connection_accepter" "secondary" {
  provider                  = aws.secondary
  vpc_peering_connection_id = aws_vpc_peering_connection.primary_to_secondary.id
  auto_accept               = true
}

# Remote DNS resolution keeps private Aurora endpoint names usable across the
# peering connection.
resource "aws_vpc_peering_connection_options" "primary" {
  provider                  = aws.primary
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.secondary.id

  requester { allow_remote_vpc_dns_resolution = true }
}

resource "aws_vpc_peering_connection_options" "secondary" {
  provider                  = aws.secondary
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.secondary.id

  accepter { allow_remote_vpc_dns_resolution = true }
}

resource "aws_route" "primary_to_secondary" {
  provider = aws.primary
  for_each = {
    application = module.primary_vpc.private_route_table_ids[0]
    database    = module.primary_vpc.database_route_table_ids[0]
  }

  route_table_id            = each.value
  destination_cidr_block    = var.secondary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.secondary.id
}

resource "aws_route" "secondary_to_primary" {
  provider = aws.secondary
  for_each = {
    application = module.secondary_vpc.private_route_table_ids[0]
    database    = module.secondary_vpc.database_route_table_ids[0]
  }

  route_table_id            = each.value
  destination_cidr_block    = var.primary_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection_accepter.secondary.id
}
