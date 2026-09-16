# All AWS calls are mocked. These tests do not check regional service availability.
# Run with TF_WORKSPACE=new-cinema-production; see README.
mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = { names = ["ap-south-1a", "ap-south-1b", "ap-south-1c"] }
  }
  mock_data "aws_servicequotas_service_quota" {
    defaults = { value = 120 }
  }
  mock_data "aws_ec2_managed_prefix_list" {
    defaults = { id = "pl-0123456789abcdef0" }
  }
  mock_data "aws_ssm_parameter" {
    defaults = { value = "ami-0123456789abcdef0" }
  }
  mock_data "aws_ami" {
    defaults = {
      id           = "ami-0123456789abcdef0"
      architecture = "arm64"
    }
  }
  mock_data "aws_ec2_instance_type" {
    defaults = { supported_architectures = ["arm64"] }
  }
  mock_data "aws_rds_engine_version" {
    defaults = {
      version_actual                     = "8.4.11"
      exportable_log_types               = ["audit", "error", "iam-db-auth-error", "slowquery"]
      supports_log_exports_to_cloudwatch = true
    }
  }
  mock_data "aws_rds_orderable_db_instance" {
    defaults = {
      availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
      min_storage_size   = 20
      max_storage_size   = 65536
    }
  }
}

variables {
  cinema_name   = "new-cinema"
  environment   = "production"
  key_pair_name = "mock-existing-key"
  db_name       = "newcinema_production"
  # Synthetic test-only value, never a deployed or real credential.
  db_password = "MockOnly-NotARealSecret"
}

run "default_private_network_and_database" {
  command = plan

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2 && length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0 && length(aws_route.private_internet) == 0
    error_message = "Default topology must have four subnets and no NAT egress."
  }
  assert {
    condition     = !aws_db_instance.this.publicly_accessible && !aws_db_instance.this.multi_az && aws_db_instance.this.storage_encrypted && !aws_db_instance.this.iam_database_authentication_enabled
    error_message = "RDS must stay private, encrypted, Single-AZ, and password-authenticated."
  }
  assert {
    condition     = aws_db_instance.this.parameter_group_name == "default.mysql8.4" && length(aws_db_parameter_group.slow_query) == 0 && aws_db_instance.this.deletion_protection && !aws_db_instance.this.skip_final_snapshot
    error_message = "Keep the default parameter group and production deletion defaults."
  }
  assert {
    condition     = length(aws_cloudwatch_log_group.rds) == 4 && aws_db_instance.this.enabled_cloudwatch_logs_exports == toset(["audit", "error", "iam-db-auth-error", "slowquery"])
    error_message = "All requested exports must have tagged log groups, even if some remain empty."
  }
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.cloudfront) == 2 && aws_vpc_security_group_ingress_rule.cloudfront["http"].from_port == 80 && aws_vpc_security_group_ingress_rule.cloudfront["https"].to_port == 443 && alltrue([for r in aws_vpc_security_group_ingress_rule.cloudfront : r.prefix_list_id == data.aws_ec2_managed_prefix_list.cloudfront.id && r.cidr_ipv4 == null]) && local.required_ingress_quota == 111
    error_message = "HTTP/HTTPS must use only the CloudFront prefix list, with quota weight accounted for."
  }
}

run "single_nat" {
  command = plan
  variables { nat_mode = "single" }
  assert {
    condition     = keys(aws_nat_gateway.this) == ["0"] && length(aws_eip.nat) == 1 && length(aws_route.private_internet) == 2
    error_message = "Single NAT must use public subnet 0 and serve both private route tables."
  }
}

run "per_az_nat_and_slow_queries" {
  command = plan
  variables {
    nat_mode                  = "per_az"
    enable_slow_query_logging = true
    ec2_public_subnet_index   = 1
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 2 && length(aws_eip.nat) == 2 && length(aws_route.private_internet) == 2
    error_message = "Per-AZ NAT must create two gateways, EIPs and private default routes."
  }
  assert {
    condition     = length(aws_db_parameter_group.slow_query) == 1 && alltrue([for p in aws_db_parameter_group.slow_query[0].parameter : (p.name == "slow_query_log" && p.value == "1") || (p.name == "log_output" && p.value == "FILE")]) && length(aws_db_parameter_group.slow_query[0].parameter) == 2
    error_message = "Optional slow-query logging needs both required parameters."
  }
}

run "overlapping_subnet_rejected" {
  command = plan
  variables { private_subnet_cidrs = ["10.0.1.128/25", "10.0.12.0/24"] }
  expect_failures = [aws_vpc.this]
}

run "subnet_outside_vpc_rejected" {
  command = plan
  variables { private_subnet_cidrs = ["10.1.11.0/24", "10.0.12.0/24"] }
  expect_failures = [aws_vpc.this]
}

run "wrong_client_workspace_rejected" {
  command = plan
  variables { cinema_name = "another-cinema" }
  expect_failures = [aws_vpc.this]
}

run "reserved_database_name_rejected" {
  command = plan
  variables { db_name = "SeLeCt" }
  expect_failures = [var.db_name]
}

run "invalid_database_name_rejected" {
  command = plan
  variables { db_name = "new-cinema" }
  expect_failures = [var.db_name]
}

run "insufficient_quota_rejected" {
  command = plan
  override_data {
    target = data.aws_servicequotas_service_quota.sg_rules
    values = { value = 60 }
  }
  expect_failures = [aws_security_group.ec2]
}

run "multiple_ssh_sources_count_toward_quota" {
  command = plan
  variables { ssh_allowed_cidrs = ["192.0.2.1/32", "198.51.100.1/32"] }
  override_data {
    target = data.aws_servicequotas_service_quota.sg_rules
    values = { value = 111 }
  }
  expect_failures = [aws_security_group.ec2]
}

run "missing_log_export_rejected" {
  command = plan
  override_data {
    target = data.aws_rds_engine_version.mysql
    values = {
      exportable_log_types               = ["audit", "error", "slowquery"]
      supports_log_exports_to_cloudwatch = true
    }
  }
  expect_failures = [data.aws_rds_engine_version.mysql]
}

run "overlapping_windows_rejected" {
  command = plan
  variables { maintenance_window = "mon:06:15-mon:06:45" }
  expect_failures = [aws_db_instance.this]
}

run "week_boundary_overlap_rejected" {
  command = plan
  variables {
    backup_window      = "00:00-00:30"
    maintenance_window = "sun:23:45-mon:00:15"
  }
  expect_failures = [aws_db_instance.this]
}

run "adjacent_midnight_windows_accepted" {
  command = plan
  variables {
    backup_window      = "23:30-00:00"
    maintenance_window = "mon:00:00-mon:00:30"
  }
}

run "short_window_rejected" {
  command = plan
  variables { backup_window = "06:00-06:15" }
  expect_failures = [aws_db_instance.this]
}

run "insufficient_autoscaling_headroom_rejected" {
  command = plan
  variables { db_max_allocated_storage = 54 }
  expect_failures = [aws_db_instance.this]
}

run "x86_ami_rejected" {
  command = plan
  override_data {
    target = data.aws_ami.selected
    values = { architecture = "x86_64" }
  }
  expect_failures = [aws_instance.this]
}

run "explicit_ami_skips_ssm" {
  command = plan
  variables { ami_id = "ami-0123456789abcdef0" }
  assert {
    condition     = length(data.aws_ssm_parameter.ubuntu) == 0
    error_message = "Explicit AMIs should not depend on a successful SSM lookup."
  }
}
