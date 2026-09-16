data "aws_rds_engine_version" "mysql" {
  engine                 = "mysql"
  version                = var.db_engine_version
  parameter_group_family = "mysql8.4"

  lifecycle {
    postcondition {
      condition     = self.supports_log_exports_to_cloudwatch && length(setsubtract(toset(local.db_log_exports), self.exportable_log_types)) == 0
      error_message = "The exact MySQL version in this Region must support all four requested log exports. No version or log substitution is performed."
    }
  }
}

data "aws_rds_orderable_db_instance" "mysql" {
  engine                       = "mysql"
  engine_version               = data.aws_rds_engine_version.mysql.version
  instance_class               = var.db_instance_class
  license_model                = "general-public-license"
  storage_type                 = "gp3"
  vpc                          = true
  supported_network_types      = ["IPV4"]
  supports_storage_encryption  = true
  supports_storage_autoscaling = true
}

resource "aws_db_subnet_group" "this" {
  name        = lookup(var.name_overrides, "db_subnet_group", "${local.name_prefix}-db-subnets")
  description = "Private subnets in two AZs for the Single-AZ cinema database"
  subnet_ids  = [for k in ["0", "1"] : aws_subnet.private[k].id]
  tags        = { Name = lookup(var.name_overrides, "db_subnet_group", "${local.name_prefix}-db-subnets") }
}

resource "aws_db_option_group" "audit" {
  name                     = lookup(var.name_overrides, "db_option_group", "${local.name_prefix}-mysql84-audit")
  option_group_description = "MySQL 8.4 audit logging"
  engine_name              = "mysql"
  major_engine_version     = "8.4"

  # AWS supports this option on MySQL 8.4. Verify availability and minimum
  # minor version in the target Region using the read-only README commands.
  option {
    option_name = "MARIADB_AUDIT_PLUGIN"

    option_settings {
      name  = "SERVER_AUDIT_EVENTS"
      value = "CONNECT,QUERY"
    }
  }

  tags = { Name = lookup(var.name_overrides, "db_option_group", "${local.name_prefix}-mysql84-audit") }
}

resource "aws_db_parameter_group" "slow_query" {
  count       = var.enable_slow_query_logging ? 1 : 0
  name        = lookup(var.name_overrides, "db_parameter_group", "${local.name_prefix}-mysql84-slowquery")
  family      = "mysql8.4"
  description = "Write slow queries to files for CloudWatch export"

  parameter {
    name         = "slow_query_log"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_output"
    value        = "FILE"
    apply_method = "immediate"
  }

  tags = { Name = lookup(var.name_overrides, "db_parameter_group", "${local.name_prefix}-mysql84-slowquery") }
}

resource "aws_cloudwatch_log_group" "rds" {
  for_each = toset(local.db_log_exports)
  name     = "/aws/rds/instance/${local.db_identifier}/${each.value}"
  # Retention is unspecified: keep CloudWatch's default of never expiring.
  tags = { Name = "${local.db_identifier}-${each.value}" }
}

resource "aws_db_instance" "this" {
  identifier     = local.db_identifier
  engine         = "mysql"
  engine_version = data.aws_rds_engine_version.mysql.version
  instance_class = data.aws_rds_orderable_db_instance.mysql.instance_class
  multi_az       = false
  db_name        = var.db_name
  username       = var.db_username
  password       = var.db_password
  # Omit manage_master_user_password: the provider conflicts with password
  # even when that argument is explicitly false. Omission keeps self-management.
  iam_database_authentication_enabled = false

  storage_type          = "gp3"
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_max_allocated_storage
  storage_encrypted     = true
  # With kms_key_id omitted, RDS uses its regional AWS-managed alias/aws/rds.
  # This also works in a new account where that key has not been created yet.

  network_type           = "IPV4"
  db_subnet_group_name   = aws_db_subnet_group.this.name
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.rds.id]
  parameter_group_name   = var.enable_slow_query_logging ? aws_db_parameter_group.slow_query[0].name : var.db_parameter_group_name
  option_group_name      = aws_db_option_group.audit.name
  monitoring_interval    = 0

  backup_retention_period         = var.backup_retention_period
  backup_window                   = var.backup_window
  maintenance_window              = var.maintenance_window
  copy_tags_to_snapshot           = true
  auto_minor_version_upgrade      = true
  enabled_cloudwatch_logs_exports = local.db_log_exports

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : local.final_snapshot_name
  tags                      = { Name = local.db_identifier }
  # Create tagged log groups before RDS starts publishing.
  depends_on = [aws_cloudwatch_log_group.rds]

  lifecycle {
    precondition {
      condition     = var.db_max_allocated_storage >= ceil(var.db_allocated_storage * 1.1)
      error_message = "Autoscaling maximum must be at least 10% larger than allocated storage."
    }
    precondition {
      condition     = var.db_allocated_storage >= data.aws_rds_orderable_db_instance.mysql.min_storage_size && var.db_max_allocated_storage <= data.aws_rds_orderable_db_instance.mysql.max_storage_size
      error_message = "Storage settings are outside this regional instance/engine offering's limits."
    }
    precondition {
      condition     = alltrue([for az in local.azs : contains(data.aws_rds_orderable_db_instance.mysql.availability_zones, az)])
      error_message = "The requested DB class and exact engine version must be offered in both selected subnet AZs."
    }
    precondition {
      condition     = local.backup_duration >= 30 && local.maintenance_duration >= 30 && local.windows_disjoint
      error_message = "Backup and maintenance windows must each last at least 30 minutes and must not overlap, including across midnight or the end of the week."
    }
  }
}
