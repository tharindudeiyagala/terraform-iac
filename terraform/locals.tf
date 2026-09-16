locals {
  name_prefix             = "${var.cinema_name}-${var.environment}"
  vpc_name                = var.vpc_name != "" ? var.vpc_name : "${local.name_prefix}-vpc"
  ec2_name                = var.ec2_name != "" ? var.ec2_name : local.name_prefix
  ec2_security_group_name = var.ec2_security_group_name != "" ? var.ec2_security_group_name : "${local.name_prefix}-ec2-sg"
  rds_security_group_name = var.rds_security_group_name != "" ? var.rds_security_group_name : "${local.name_prefix}-rds-sg"
  db_identifier           = var.db_identifier != "" ? var.db_identifier : local.name_prefix
  final_snapshot_name     = var.final_snapshot_identifier != "" ? var.final_snapshot_identifier : "${local.db_identifier}-final"
  common_tags = merge(var.additional_tags, {
    cinema      = var.cinema_name
    Environment = var.environment
  })

  azs = length(var.availability_zones) == 0 ? slice(data.aws_availability_zones.available.names, 0, 2) : var.availability_zones
  public_subnets = {
    for i, cidr in var.public_subnet_cidrs : tostring(i) => {
      cidr = cidr
      az   = local.azs[i]
    }
  }
  private_subnets = {
    for i, cidr in var.private_subnet_cidrs : tostring(i) => {
      cidr = cidr
      az   = local.azs[i]
    }
  }
  nat_subnets = var.nat_mode == "none" ? {} : {
    for k, subnet in local.public_subnets : k => subnet if var.nat_mode == "per_az" || k == "0"
  }

  # Numeric IPv4 interval checks handle unequal subnet sizes and containment.
  all_cidrs = concat([var.vpc_cidr], var.public_subnet_cidrs, var.private_subnet_cidrs)
  cidr_ranges = [
    for cidr in local.all_cidrs : {
      first = try(sum([for i, octet in split(".", cidrhost(cidr, 0)) : tonumber(octet) * pow(256, 3 - i)]), 0)
      last  = try(sum([for i, octet in split(".", cidrhost(cidr, -1)) : tonumber(octet) * pow(256, 3 - i)]), 0)
    }
  ]
  subnets_inside_vpc = alltrue([
    for subnet in slice(local.cidr_ranges, 1, length(local.cidr_ranges)) :
    subnet.first >= local.cidr_ranges[0].first && subnet.last <= local.cidr_ranges[0].last
  ])
  subnets_disjoint = alltrue(flatten([
    for i, a in slice(local.cidr_ranges, 1, length(local.cidr_ranges)) : [
      for j, b in slice(local.cidr_ranges, 1, length(local.cidr_ranges)) :
      i == j || a.last < b.first || b.last < a.first
    ]
  ]))

  # AWS documents CloudFront's rule weight as 55 (not its current IP count).
  cloudfront_rule_weight = 55
  required_ingress_quota = 2 * local.cloudfront_rule_weight + length(var.ssh_allowed_cidrs)
  db_log_exports         = ["audit", "error", "iam-db-auth-error", "slowquery"]
  # MANUAL became nonreserved in 8.4.11; keep older 8.4 overrides accurate.
  mysql_reserved_words = concat(
    [for word in split("\n", file("${path.module}/mysql84-reserved-words.txt")) : trimspace(word) if trimspace(word) != ""],
    try(tonumber(split(".", var.db_engine_version)[2]) < 11, false) ? ["MANUAL"] : []
  )

  weekdays          = { mon = 0, tue = 1, wed = 2, thu = 3, fri = 4, sat = 5, sun = 6 }
  backup_parts      = split("-", var.backup_window)
  maintenance_parts = split("-", var.maintenance_window)
  backup_start      = try(tonumber(split(":", local.backup_parts[0])[0]) * 60 + tonumber(split(":", local.backup_parts[0])[1]), 0)
  backup_end        = try(tonumber(split(":", local.backup_parts[1])[0]) * 60 + tonumber(split(":", local.backup_parts[1])[1]), 0)
  backup_duration   = (local.backup_end - local.backup_start + 1440) % 1440
  maintenance_minutes = [
    for part in local.maintenance_parts :
    try(local.weekdays[split(":", part)[0]] * 1440 + tonumber(split(":", part)[1]) * 60 + tonumber(split(":", part)[2]), 0)
  ]
  maintenance_start    = local.maintenance_minutes[0]
  maintenance_duration = try((local.maintenance_minutes[1] - local.maintenance_start + 10080) % 10080, 0)
  windows_disjoint = alltrue(flatten([
    for day in range(-1, 8) : [
      for shift in [-10080, 0, 10080] :
      local.backup_start + day * 1440 + local.backup_duration <= local.maintenance_start + shift ||
      local.maintenance_start + shift + local.maintenance_duration <= local.backup_start + day * 1440
    ]
  ]))
}
