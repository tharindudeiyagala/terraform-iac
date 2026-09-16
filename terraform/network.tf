data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

resource "aws_vpc" "this" {
  cidr_block                       = var.vpc_cidr
  instance_tenancy                 = "default"
  assign_generated_ipv6_cidr_block = false
  enable_dns_support               = true
  enable_dns_hostnames             = true
  tags                             = { Name = local.vpc_name }

  # No VPC encryption control resource or VPC endpoints are created.
  lifecycle {
    precondition {
      condition     = local.subnets_inside_vpc && local.subnets_disjoint
      error_message = "All four subnet CIDRs must be inside the VPC and must not overlap."
    }
    precondition {
      condition     = length(local.azs) == 2 && alltrue([for az in local.azs : contains(data.aws_availability_zones.available.names, az)])
      error_message = "Select two available standard Availability Zones in aws_region."
    }
    precondition {
      condition     = terraform.workspace == local.name_prefix
      error_message = "Select or create the client workspace named ${local.name_prefix} before planning. Changing tfvars alone must not reuse another client's state."
    }
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = lookup(var.name_overrides, "internet_gateway", "${local.name_prefix}-igw") }
}

resource "aws_subnet" "public" {
  for_each                = local.public_subnets
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true
  tags                    = { Name = lookup(var.name_overrides, "public_subnet_${each.key}", "${local.name_prefix}-public-${each.key}") }
}

resource "aws_subnet" "private" {
  for_each                = local.private_subnets
  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = false
  tags                    = { Name = lookup(var.name_overrides, "private_subnet_${each.key}", "${local.name_prefix}-private-${each.key}") }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = lookup(var.name_overrides, "public_route_table", "${local.name_prefix}-public-rt") }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = local.private_subnets
  vpc_id   = aws_vpc.this.id
  tags     = { Name = lookup(var.name_overrides, "private_route_table_${each.key}", "${local.name_prefix}-private-rt-${each.key}") }
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_eip" "nat" {
  for_each = local.nat_subnets
  domain   = "vpc"
  tags     = { Name = lookup(var.name_overrides, "nat_eip_${each.key}", "${local.name_prefix}-nat-eip-${each.key}") }
}

resource "aws_nat_gateway" "this" {
  for_each      = local.nat_subnets
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = { Name = lookup(var.name_overrides, "nat_gateway_${each.key}", "${local.name_prefix}-nat-${each.key}") }
  depends_on    = [aws_internet_gateway.this, aws_route.public_internet, aws_route_table_association.public]
}

resource "aws_route" "private_internet" {
  for_each               = var.nat_mode == "none" ? {} : local.private_subnets
  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.nat_mode == "single" ? "0" : each.key].id
}
