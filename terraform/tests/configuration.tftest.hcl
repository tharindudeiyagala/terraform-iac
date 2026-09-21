# All AWS calls are mocked. These tests do not check regional service availability.
# Run with TF_WORKSPACE=new-cinema-production; see README.
mock_provider "aws" {
  mock_data "aws_iam_role" {
    defaults = { arn = "arn:aws:iam::123456789012:role/ecsTaskExecutionRole" }
  }
  mock_resource "aws_ecr_repository" {
    override_during = plan
    defaults = {
      arn            = "arn:aws:ecr:ap-south-1:123456789012:repository/new-cinema-web"
      repository_url = "123456789012.dkr.ecr.ap-south-1.amazonaws.com/new-cinema-web"
    }
  }
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
  expect_failures = [aws_security_group.ec2, aws_security_group.alb, aws_security_group.api_alb]
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

# Distinct SG IDs make it possible to catch accidentally allowing EC2 into EFS.
override_resource {
  target          = aws_security_group.alb
  override_during = plan
  values          = { id = "sg-00000000000000001" }
}

override_resource {
  target          = aws_security_group.ecs
  override_during = plan
  values          = { id = "sg-00000000000000002" }
}

override_resource {
  target          = aws_security_group.ec2
  override_during = plan
  values          = { id = "sg-00000000000000003" }
}

run "web_ingress_is_restricted" {
  command = plan
  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.alb_cloudfront) == 2 &&
      alltrue([for k, r in aws_vpc_security_group_ingress_rule.alb_cloudfront :
        r.prefix_list_id == data.aws_ec2_managed_prefix_list.cloudfront.id &&
        r.cidr_ipv4 == null && r.ip_protocol == "tcp" &&
        r.from_port == (k == "http" ? 80 : 443) && r.to_port == r.from_port
      ]) &&
      local.alb_required_ingress_quota == 110
    )
    error_message = "ALB ingress must remain CloudFront-only on exactly 80 and 443."
  }
  assert {
    condition = alltrue([for r in aws_vpc_security_group_ingress_rule.ecs_alb :
      r.referenced_security_group_id == aws_security_group.alb.id &&
      r.cidr_ipv4 == null && contains([80, 443], r.from_port) && r.to_port == r.from_port
    ])
    error_message = "Only the ALB SG may send web traffic to the ECS SG."
  }
  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.efs_ecs.referenced_security_group_id == aws_security_group.ecs.id &&
      aws_vpc_security_group_ingress_rule.efs_ecs.referenced_security_group_id != aws_security_group.ec2.id &&
      aws_vpc_security_group_ingress_rule.efs_ecs.from_port == 2049 &&
      aws_vpc_security_group_ingress_rule.efs_ecs.to_port == 2049 &&
      aws_vpc_security_group_ingress_rule.efs_ecs.cidr_ipv4 == null
    )
    error_message = "The single NFS source must be ECS, never EC2 or a CIDR."
  }
}

run "zero_task_fargate_service" {
  command = plan
  assert {
    condition = (
      aws_ecs_service.web.desired_count == 0 &&
      aws_ecs_service.web.launch_type == "FARGATE" &&
      aws_ecs_service.web.scheduling_strategy == "REPLICA" &&
      length(aws_ecs_service.web.capacity_provider_strategy) == 0 &&
      aws_ecs_cluster_capacity_providers.web.capacity_providers == toset(["FARGATE"]) &&
      aws_ecs_service.web.availability_zone_rebalancing == "ENABLED" &&
      aws_ecs_service.web.deployment_configuration[0].strategy == "ROLLING" &&
      aws_ecs_service.web.deployment_controller[0].type == "ECS" &&
      aws_ecs_service.web.deployment_minimum_healthy_percent == 100 &&
      aws_ecs_service.web.deployment_maximum_percent == 200 &&
      aws_ecs_service.web.health_check_grace_period_seconds == 10 &&
      aws_ecs_service.web.network_configuration[0].assign_public_ip
    )
    error_message = "The initial service must be zero-task Fargate with the requested rolling deployment settings."
  }
  assert {
    condition = (
      aws_ecs_cluster.web.configuration[0].execute_command_configuration[0].logging == "DEFAULT" &&
      one(aws_ecs_cluster.web.setting).value == "disabled" &&
      one(aws_ecs_cluster.web.setting).name == "containerInsights"
    )
    error_message = "Cluster logging settings must match the request."
  }
  assert {
    condition = (
      aws_ecr_repository.web.image_tag_mutability == "MUTABLE" &&
      aws_ecr_repository.web.encryption_configuration[0].encryption_type == "AES256"
    )
    error_message = "ECR must retain the requested tag mutability and AES256 encryption."
  }
}

run "x86_web_container_contract" {
  command = plan
  assert {
    condition = (
      aws_ecs_task_definition.web.network_mode == "awsvpc" &&
      aws_ecs_task_definition.web.runtime_platform[0].cpu_architecture == "X86_64" &&
      aws_ecs_task_definition.web.runtime_platform[0].operating_system_family == "LINUX" &&
      aws_ecs_task_definition.web.requires_compatibilities == toset(["FARGATE"]) &&
      aws_ecs_task_definition.web.cpu == "1024" && aws_ecs_task_definition.web.memory == "2048"
    )
    error_message = "ECS must be Linux X86_64 Fargate, independently of the ARM64 EC2 instance."
  }
  assert {
    condition = (
      jsondecode(aws_ecs_task_definition.web.container_definitions)[0].image == "123456789012.dkr.ecr.ap-south-1.amazonaws.com/new-cinema-web:latest" &&
      jsondecode(aws_ecs_task_definition.web.container_definitions)[0].essential &&
      jsondecode(aws_ecs_task_definition.web.container_definitions)[0].cpu == 1024 &&
      jsondecode(aws_ecs_task_definition.web.container_definitions)[0].memory == 2048 &&
      jsondecode(aws_ecs_task_definition.web.container_definitions)[0].memoryReservation == 1024 &&
      jsondecode(aws_ecs_task_definition.web.container_definitions)[0].portMappings == [{
        containerPort = 80, protocol = "tcp", name = "web", appProtocol = "http"
      }] &&
      jsondecode(aws_ecs_task_definition.web.container_definitions)[0].healthCheck == {
        command  = ["CMD-SHELL", "curl -f http://localhost/api/health || exit 1"]
        interval = 30, timeout = 5, retries = 3, startPeriod = 10
      } &&
      jsondecode(aws_ecs_task_definition.web.container_definitions)[0].logConfiguration.logDriver == "awslogs" &&
      jsondecode(aws_ecs_task_definition.web.container_definitions)[0].logConfiguration.options["awslogs-region"] == var.aws_region
    )
    error_message = "Container image, resources, port, health check and logging must match the application contract."
  }
}

run "http_alb_and_unmounted_regional_efs" {
  command = plan
  assert {
    condition = (
      !aws_lb.web.internal && aws_lb.web.load_balancer_type == "application" &&
      aws_lb.web.ip_address_type == "ipv4" &&
      aws_lb_listener.http.port == 80 && aws_lb_listener.http.protocol == "HTTP" &&
      aws_lb_target_group.web.target_type == "ip" && aws_lb_target_group.web.protocol_version == "HTTP1" &&
      aws_lb_target_group.web.target_control_port == null &&
      aws_lb_target_group.web.health_check[0].path == "/api/health" &&
      aws_lb_target_group.web.health_check[0].matcher == "200-299"
    )
    error_message = "ALB must use HTTP, IP targets, the health endpoint and no Target Optimizer."
  }
  assert {
    condition = (
      aws_efs_file_system.web.encrypted &&
      aws_efs_file_system.web.creation_token == "new-cinema-production-efs" &&
      aws_efs_file_system.web.performance_mode == "generalPurpose" &&
      aws_efs_file_system.web.throughput_mode == "elastic" &&
      length(aws_efs_file_system.web.lifecycle_policy) == 0 &&
      aws_efs_backup_policy.web.backup_policy[0].status == "DISABLED" &&
      keys(aws_efs_mount_target.web) == ["0", "1"] &&
      length(aws_ecs_task_definition.web.volume) == 0 &&
      !contains(keys(jsondecode(aws_ecs_task_definition.web.container_definitions)[0]), "mountPoints")
    )
    error_message = "EFS must be Regional, encrypted, Elastic, without backups/transitions or invented task mounts."
  }
}

run "separate_existing_roles_and_custom_tag" {
  command = plan
  variables {
    ecs_task_role_name      = "cinemaAppRole"
    ecs_execution_role_name = "cinemaExecutionRole"
    ecs_image_tag           = "release-2026-09"
  }
  override_data {
    target = data.aws_iam_role.ecs_task
    values = { arn = "arn:aws:iam::123456789012:role/cinemaAppRole" }
  }
  override_data {
    target = data.aws_iam_role.ecs_execution
    values = { arn = "arn:aws:iam::123456789012:role/cinemaExecutionRole" }
  }
  assert {
    condition = (
      aws_ecs_task_definition.web.task_role_arn == "arn:aws:iam::123456789012:role/cinemaAppRole" &&
      aws_ecs_task_definition.web.execution_role_arn == "arn:aws:iam::123456789012:role/cinemaExecutionRole" &&
      endswith(jsondecode(aws_ecs_task_definition.web.container_definitions)[0].image, ":release-2026-09")
    )
    error_message = "Role names and image tags must remain separately configurable."
  }
}

run "unsupported_task_memory_rejected" {
  command = plan
  variables { ecs_task_memory = 3073 }
  expect_failures = [var.ecs_task_memory]
}

run "oversized_container_rejected" {
  command = plan
  variables { ecs_container_memory = 4096 }
  expect_failures = [var.ecs_container_memory]
}

run "invalid_memory_reservation_rejected" {
  command = plan
  variables { ecs_container_memory_reservation = 2048 }
  expect_failures = [var.ecs_container_memory_reservation]
}

run "invalid_alb_name_rejected" {
  command = plan
  variables { alb_name = "internal-invalid-name" }
  expect_failures = [var.alb_name]
}

run "alb_subnets_too_small_rejected" {
  command = plan
  variables { public_subnet_cidrs = ["10.0.1.0/28", "10.0.2.0/28"] }
  expect_failures = [aws_lb.web, aws_lb.api]
}

run "web_subnet_placement" {
  command = plan
  override_resource {
    target          = aws_subnet.public["0"]
    override_during = plan
    values          = { id = "subnet-00000000000000001" }
  }
  override_resource {
    target          = aws_subnet.public["1"]
    override_during = plan
    values          = { id = "subnet-00000000000000002" }
  }
  override_resource {
    target          = aws_subnet.private["0"]
    override_during = plan
    values          = { id = "subnet-00000000000000003" }
  }
  override_resource {
    target          = aws_subnet.private["1"]
    override_during = plan
    values          = { id = "subnet-00000000000000004" }
  }
  assert {
    condition = (
      aws_lb.web.subnets == toset(["subnet-00000000000000001", "subnet-00000000000000002"]) &&
      aws_ecs_service.web.network_configuration[0].subnets == toset(["subnet-00000000000000001", "subnet-00000000000000002"]) &&
      aws_efs_mount_target.web["0"].subnet_id == "subnet-00000000000000003" &&
      aws_efs_mount_target.web["1"].subnet_id == "subnet-00000000000000004"
    )
    error_message = "ALB/ECS must use both public subnets; EFS must use the private subnet in each AZ."
  }
}

run "nonproduction_names_are_isolated" {
  command = plan
  variables { environment = "staging" }
  # The test workspace intentionally stays new-cinema-production.
  expect_failures = [aws_vpc.this]
  assert {
    condition = (
      aws_ecr_repository.web.name == "new-cinema-staging-web" &&
      aws_ecs_task_definition.web.family == "new-cinema-staging-web-td" &&
      aws_efs_file_system.web.creation_token == "new-cinema-staging-efs"
    )
    error_message = "Environment changes must not reuse a production repository, task family or EFS token."
  }
}

run "long_derived_alb_names_fit" {
  command = plan
  variables { cinema_name = "cinema-with-a-very-long-name" }
  expect_failures = [aws_vpc.this]
  assert {
    condition = (
      length(local.alb_name) == 32 && length(local.alb_target_group_name) == 32 &&
      local.alb_name != local.alb_target_group_name &&
      !endswith(local.alb_name, "-") && !endswith(local.alb_target_group_name, "-")
    )
    error_message = "Long client names must produce distinct, stable ALB/TG names within AWS's 32-character limit."
  }
}

# Distinct API values catch accidental wiring to the web workload.
override_resource {
  target          = aws_ecr_repository.api
  override_during = plan
  values = {
    arn            = "arn:aws:ecr:ap-south-1:123456789012:repository/new-cinema-api"
    repository_url = "123456789012.dkr.ecr.ap-south-1.amazonaws.com/new-cinema-api"
  }
}

override_resource {
  target          = aws_security_group.api_alb
  override_during = plan
  values          = { id = "sg-00000000000000005" }
}

override_resource {
  target          = aws_security_group.api_ecs
  override_during = plan
  values          = { id = "sg-00000000000000006" }
}

run "api_defaults_and_web_isolation" {
  command = plan
  assert {
    condition = (
      aws_ecr_repository.api.name == "new-cinema-api" &&
      aws_ecs_cluster.api.name == "new-cinema-api-cluster-prod" &&
      aws_ecs_task_definition.api.family == "new-cinema-api-td" &&
      aws_ecs_service.api.name == "new-cinema-api-service" &&
      aws_security_group.api_alb.name == "new-cinema-production-api-alb-sg" &&
      aws_security_group.api_ecs.name == "new-cinema-production-api-ecs-sg" &&
      aws_lb.api.name == "new-cinema-prod-api-alb" &&
      aws_lb_target_group.api.name == "new-cinema-production-api-tg" &&
      aws_cloudwatch_log_group.api_ecs.name == "/ecs/new-cinema-production/api" &&
      local.common_tags.cinema == "new-cinema" &&
      aws_ecr_repository.web.name == "new-cinema-web" &&
      aws_lb_target_group.web.health_check[0].path == "/api/health"
    )
    error_message = "API defaults must match the requested names while preserving the web workload."
  }
  assert {
    condition = (
      aws_ecr_repository.api.image_tag_mutability == "MUTABLE" &&
      aws_ecr_repository.api.encryption_configuration[0].encryption_type == "AES256" &&
      aws_ecs_service.api.desired_count == 0 &&
      aws_ecs_service.api.launch_type == "FARGATE" &&
      aws_ecs_service.api.scheduling_strategy == "REPLICA" &&
      length(aws_ecs_service.api.capacity_provider_strategy) == 0 &&
      aws_ecs_cluster_capacity_providers.api.capacity_providers == toset(["FARGATE"]) &&
      aws_ecs_service.api.availability_zone_rebalancing == "ENABLED" &&
      aws_ecs_service.api.deployment_controller[0].type == "ECS" &&
      aws_ecs_service.api.deployment_configuration[0].strategy == "ROLLING" &&
      aws_ecs_service.api.deployment_minimum_healthy_percent == 100 &&
      aws_ecs_service.api.deployment_maximum_percent == 200 &&
      aws_ecs_service.api.health_check_grace_period_seconds == 10 &&
      one(aws_ecs_cluster.api.setting).name == "containerInsights" &&
      one(aws_ecs_cluster.api.setting).value == "disabled" &&
      aws_ecs_cluster.api.configuration[0].execute_command_configuration[0].logging == "DEFAULT"
    )
    error_message = "API must start at zero tasks with the specified Fargate and rolling deployment settings."
  }
}

run "api_container_health_and_logging" {
  command = plan
  assert {
    condition = (
      aws_ecs_task_definition.api.requires_compatibilities == toset(["FARGATE"]) &&
      aws_ecs_task_definition.api.network_mode == "awsvpc" &&
      aws_ecs_task_definition.api.runtime_platform[0].cpu_architecture == "X86_64" &&
      aws_ecs_task_definition.api.runtime_platform[0].operating_system_family == "LINUX" &&
      aws_ecs_task_definition.api.cpu == "1024" && aws_ecs_task_definition.api.memory == "2048" &&
      aws_ecs_task_definition.api.task_role_arn == "arn:aws:iam::123456789012:role/ecsTaskExecutionRole" &&
      aws_ecs_task_definition.api.execution_role_arn == "arn:aws:iam::123456789012:role/ecsTaskExecutionRole" &&
      length(aws_ecs_task_definition.api.volume) == 0 &&
      length(aws_ecs_task_definition.api.ephemeral_storage) == 0
    )
    error_message = "API must use the existing roles, Linux X86_64, 1 vCPU/2 GiB and default storage."
  }
  assert {
    condition = (
      length(jsondecode(aws_ecs_task_definition.api.container_definitions)) == 1 &&
      jsondecode(aws_ecs_task_definition.api.container_definitions)[0].name == "new-cinema-api" &&
      jsondecode(aws_ecs_task_definition.api.container_definitions)[0].essential &&
      jsondecode(aws_ecs_task_definition.api.container_definitions)[0].image == "123456789012.dkr.ecr.ap-south-1.amazonaws.com/new-cinema-api:latest" &&
      jsondecode(aws_ecs_task_definition.api.container_definitions)[0].cpu == 1024 &&
      jsondecode(aws_ecs_task_definition.api.container_definitions)[0].memory == 2048 &&
      jsondecode(aws_ecs_task_definition.api.container_definitions)[0].memoryReservation == 1024 &&
      jsondecode(aws_ecs_task_definition.api.container_definitions)[0].portMappings == [{
        containerPort = 80, hostPort = 80, protocol = "tcp", name = "api", appProtocol = "http"
      }] &&
      jsondecode(aws_ecs_task_definition.api.container_definitions)[0].healthCheck == {
        command  = ["CMD-SHELL", "curl -f http://localhost/health.php || exit 1"]
        interval = 30, timeout = 5, retries = 3, startPeriod = 10
      } &&
      jsondecode(aws_ecs_task_definition.api.container_definitions)[0].logConfiguration == {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/new-cinema-production/api"
          awslogs-region        = "ap-south-1"
          awslogs-stream-prefix = "ecs"
          mode                  = "non-blocking"
          max-buffer-size       = "25m"
        }
      }
    )
    error_message = "API image, health check, resource limits, port and logs must match its contract."
  }
}

run "api_network_and_routing_are_independent" {
  command = plan
  override_resource {
    target          = aws_vpc.this
    override_during = plan
    values          = { id = "vpc-00000000000000001" }
  }
  override_resource {
    target          = aws_subnet.public["0"]
    override_during = plan
    values          = { id = "subnet-00000000000000001" }
  }
  override_resource {
    target          = aws_subnet.public["1"]
    override_during = plan
    values          = { id = "subnet-00000000000000002" }
  }
  override_resource {
    target          = aws_lb.api
    override_during = plan
    values          = { arn = "arn:aws:elasticloadbalancing:ap-south-1:123456789012:loadbalancer/app/api/0123456789abcdef" }
  }
  override_resource {
    target          = aws_lb_target_group.api
    override_during = plan
    values          = { arn = "arn:aws:elasticloadbalancing:ap-south-1:123456789012:targetgroup/api/0123456789abcdef" }
  }
  override_resource {
    target          = aws_ecs_cluster.api
    override_during = plan
    values          = { id = "arn:aws:ecs:ap-south-1:123456789012:cluster/new-cinema-api-cluster-prod" }
  }
  override_resource {
    target          = aws_ecs_task_definition.api
    override_during = plan
    values          = { arn = "arn:aws:ecs:ap-south-1:123456789012:task-definition/new-cinema-api-td:1" }
  }
  assert {
    condition = (
      aws_security_group.api_alb.vpc_id == aws_vpc.this.id &&
      aws_security_group.api_ecs.vpc_id == aws_vpc.this.id &&
      aws_lb_target_group.api.vpc_id == aws_vpc.this.id &&
      aws_lb.api.subnets == toset(["subnet-00000000000000001", "subnet-00000000000000002"]) &&
      aws_lb.api.security_groups == toset([aws_security_group.api_alb.id]) &&
      aws_ecs_service.api.network_configuration[0].subnets == aws_lb.api.subnets &&
      aws_ecs_service.api.network_configuration[0].security_groups == toset([aws_security_group.api_ecs.id]) &&
      aws_ecs_service.api.network_configuration[0].assign_public_ip &&
      aws_ecs_service.api.cluster == aws_ecs_cluster.api.id &&
      aws_ecs_service.api.task_definition == aws_ecs_task_definition.api.arn &&
      aws_lb_listener.api_http.load_balancer_arn == aws_lb.api.arn &&
      aws_lb_listener.api_http.default_action[0].target_group_arn == aws_lb_target_group.api.arn &&
      aws_lb_listener.api_http.default_action[0].type == "forward" &&
      one(aws_ecs_service.api.load_balancer).target_group_arn == aws_lb_target_group.api.arn &&
      one(aws_ecs_service.api.load_balancer).container_name == local.api_ecs_container_name &&
      one(aws_ecs_service.api.load_balancer).container_port == 80
    )
    error_message = "API routing must connect its own cluster, task, ALB, SGs and target group in the existing public subnets."
  }
  assert {
    condition = (
      !aws_lb.api.internal && aws_lb.api.load_balancer_type == "application" &&
      aws_lb.api.ip_address_type == "ipv4" &&
      aws_lb_listener.api_http.protocol == "HTTP" && aws_lb_listener.api_http.port == 80 &&
      aws_lb_target_group.api.target_type == "ip" &&
      aws_lb_target_group.api.protocol == "HTTP" && aws_lb_target_group.api.port == 80 &&
      aws_lb_target_group.api.protocol_version == "HTTP1" &&
      aws_lb_target_group.api.ip_address_type == "ipv4" &&
      aws_lb_target_group.api.target_control_port == null &&
      aws_lb_target_group.api.health_check[0].path == "/health.php" &&
      aws_lb_target_group.api.health_check[0].healthy_threshold == 5 &&
      aws_lb_target_group.api.health_check[0].unhealthy_threshold == 2 &&
      aws_lb_target_group.api.health_check[0].interval == 30 &&
      aws_lb_target_group.api.health_check[0].matcher == "200-299"
    )
    error_message = "The API ALB must use HTTP/IP targets, the PHP health endpoint and no Target Optimizer."
  }
  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.api_alb_cloudfront) == 2 &&
      alltrue([for k, r in aws_vpc_security_group_ingress_rule.api_alb_cloudfront :
        r.security_group_id == aws_security_group.api_alb.id &&
        r.prefix_list_id == data.aws_ec2_managed_prefix_list.cloudfront.id &&
        r.cidr_ipv4 == null && r.cidr_ipv6 == null && r.ip_protocol == "tcp" &&
        r.from_port == (k == "http" ? 80 : 443) && r.to_port == r.from_port
      ]) &&
      length(aws_vpc_security_group_ingress_rule.api_ecs_alb) == 2 &&
      alltrue([for k, r in aws_vpc_security_group_ingress_rule.api_ecs_alb :
        r.security_group_id == aws_security_group.api_ecs.id &&
        r.referenced_security_group_id == aws_security_group.api_alb.id &&
        r.referenced_security_group_id != aws_security_group.alb.id &&
        r.cidr_ipv4 == null && r.cidr_ipv6 == null && r.ip_protocol == "tcp" &&
        r.from_port == (k == "http" ? 80 : 443) && r.to_port == r.from_port
      ]) &&
      aws_vpc_security_group_egress_rule.api_alb.cidr_ipv4 == "0.0.0.0/0" &&
      aws_vpc_security_group_egress_rule.api_alb.ip_protocol == "-1" &&
      aws_vpc_security_group_egress_rule.api_ecs.cidr_ipv4 == "0.0.0.0/0" &&
      aws_vpc_security_group_egress_rule.api_ecs.ip_protocol == "-1"
    )
    error_message = "API ingress must be CloudFront to API ALB to API ECS only, with all IPv4 egress."
  }
}

run "api_overrides_do_not_change_web" {
  command = plan
  variables {
    api_ecr_repository_name     = "custom-api"
    api_ecs_cluster_name        = "custom-api-cluster"
    api_ecs_task_family         = "custom-api-task"
    api_ecs_service_name        = "custom-api-service"
    api_ecs_container_name      = "custom-api-container"
    api_alb_name                = "custom-api-alb"
    api_alb_target_group_name   = "custom-api-tg"
    api_alb_security_group_name = "custom-api-alb-sg"
    api_ecs_security_group_name = "custom-api-ecs-sg"
    api_ecs_task_role_name      = "apiAppRole"
    api_ecs_execution_role_name = "apiExecutionRole"
    api_ecs_image_tag           = "release-2"
    api_ecs_desired_count       = 2
    api_ecs_log_group_name      = "/ecs/custom-api"
    api_ecs_log_stream_prefix   = "custom"
    api_ecs_log_retention_days  = 7
  }
  override_data {
    target = data.aws_iam_role.api_ecs_task
    values = { arn = "arn:aws:iam::123456789012:role/apiAppRole" }
  }
  override_data {
    target = data.aws_iam_role.api_ecs_execution
    values = { arn = "arn:aws:iam::123456789012:role/apiExecutionRole" }
  }
  assert {
    condition = (
      aws_ecr_repository.api.name == "custom-api" &&
      aws_ecs_cluster.api.name == "custom-api-cluster" &&
      aws_ecs_task_definition.api.family == "custom-api-task" &&
      aws_ecs_service.api.name == "custom-api-service" &&
      jsondecode(aws_ecs_task_definition.api.container_definitions)[0].name == "custom-api-container" &&
      endswith(jsondecode(aws_ecs_task_definition.api.container_definitions)[0].image, ":release-2") &&
      aws_lb.api.name == "custom-api-alb" && aws_lb_target_group.api.name == "custom-api-tg" &&
      aws_security_group.api_alb.name == "custom-api-alb-sg" &&
      aws_security_group.api_ecs.name == "custom-api-ecs-sg" &&
      aws_ecs_service.api.desired_count == 2 &&
      aws_ecs_task_definition.api.task_role_arn == "arn:aws:iam::123456789012:role/apiAppRole" &&
      aws_ecs_task_definition.api.execution_role_arn == "arn:aws:iam::123456789012:role/apiExecutionRole" &&
      aws_cloudwatch_log_group.api_ecs.name == "/ecs/custom-api" &&
      aws_cloudwatch_log_group.api_ecs.retention_in_days == 7 &&
      jsondecode(aws_ecs_task_definition.api.container_definitions)[0].logConfiguration.options["awslogs-stream-prefix"] == "custom" &&
      aws_ecs_service.web.desired_count == 0 && aws_ecs_task_definition.web.family == "new-cinema-web-td" &&
      aws_ecs_task_definition.web.task_role_arn == "arn:aws:iam::123456789012:role/ecsTaskExecutionRole"
    )
    error_message = "API inputs must affect only API resources and reuse the selected existing roles."
  }
}

run "api_invalid_task_size_rejected" {
  command = plan
  variables { api_ecs_task_memory = 3073 }
  expect_failures = [var.api_ecs_task_memory]
}

run "api_invalid_reservation_rejected" {
  command = plan
  variables { api_ecs_container_memory_reservation = 2048 }
  expect_failures = [var.api_ecs_container_memory_reservation]
}

run "api_invalid_alb_name_rejected" {
  command = plan
  variables { api_alb_name = "internal-api" }
  expect_failures = [var.api_alb_name]
}

run "api_environment_names_are_isolated" {
  command = plan
  variables { environment = "staging" }
  expect_failures = [aws_vpc.this]
  # A rejected workspace can stop downstream service expansion in Terraform 1.12.
  # Check the naming expressions directly; resource wiring is tested above.
  assert {
    condition = (
      local.api_ecr_repository_name == "new-cinema-staging-api" &&
      local.api_ecs_cluster_name == "new-cinema-api-cluster-staging" &&
      local.api_ecs_task_family == "new-cinema-staging-api-td" &&
      local.api_ecs_service_name == "new-cinema-staging-api-service" &&
      local.api_ecs_log_group_name == "/ecs/new-cinema-staging/api"
    )
    error_message = "API names must remain separate across client environments."
  }
}

run "api_long_names_fit" {
  command = plan
  variables { cinema_name = "cinema-with-a-very-long-name" }
  expect_failures = [aws_vpc.this]
  assert {
    condition = (
      length(local.api_alb_name) == 32 && length(local.api_alb_target_group_name) == 32 &&
      local.api_alb_name != local.alb_name &&
      local.api_alb_target_group_name != local.alb_target_group_name &&
      local.api_alb_name != local.api_alb_target_group_name
    )
    error_message = "Long API names must fit AWS limits and stay distinct from the web resources."
  }
}
