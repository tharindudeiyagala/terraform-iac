locals {
  web_environment_suffix = var.environment == "production" ? "prod" : var.environment
  # Production keeps the requested names; other environments include their
  # suffix so that repositories and task families do not collide across states.
  web_workload_prefix     = var.environment == "production" ? var.cinema_name : local.name_prefix
  ecr_repository_name     = var.ecr_repository_name != "" ? var.ecr_repository_name : "${local.web_workload_prefix}-web"
  ecs_cluster_name        = var.ecs_cluster_name != "" ? var.ecs_cluster_name : "${var.cinema_name}-web-cluster-${local.web_environment_suffix}"
  ecs_service_name        = var.ecs_service_name != "" ? var.ecs_service_name : "${local.web_workload_prefix}-web-service"
  ecs_task_family         = var.ecs_task_family != "" ? var.ecs_task_family : "${local.web_workload_prefix}-web-td"
  ecs_container_name      = var.ecs_container_name != "" ? var.ecs_container_name : "${local.web_workload_prefix}-web"
  alb_security_group_name = var.alb_security_group_name != "" ? var.alb_security_group_name : "${local.name_prefix}-alb-sg"
  ecs_security_group_name = var.ecs_security_group_name != "" ? var.ecs_security_group_name : "${local.name_prefix}-ecs-sg"
  efs_security_group_name = var.efs_security_group_name != "" ? var.efs_security_group_name : "${local.name_prefix}-efs-sg"

  # ALB/TG names have a 32-character limit. Long derived names get a stable hash
  # suffix to retain uniqueness instead of silently truncating client identity.
  alb_name_base          = "${var.cinema_name}-${local.web_environment_suffix}-web-alb"
  target_group_name_base = "${local.name_prefix}-web-tg"
  alb_name = var.alb_name != "" ? var.alb_name : (
    length(local.alb_name_base) <= 32 ? local.alb_name_base : "${substr(local.alb_name_base, 0, 23)}-${substr(sha256(local.alb_name_base), 0, 8)}"
  )
  alb_target_group_name = var.alb_target_group_name != "" ? var.alb_target_group_name : (
    length(local.target_group_name_base) <= 32 ? local.target_group_name_base : "${substr(local.target_group_name_base, 0, 23)}-${substr(sha256(local.target_group_name_base), 0, 8)}"
  )

  ecs_log_group_name         = var.ecs_log_group_name != "" ? var.ecs_log_group_name : "/ecs/${local.name_prefix}/web"
  efs_name                   = var.efs_name != "" ? var.efs_name : "${var.cinema_name}-${local.web_environment_suffix}"
  efs_creation_token         = var.efs_creation_token != "" ? var.efs_creation_token : "${local.name_prefix}-efs"
  alb_required_ingress_quota = 2 * local.cloudfront_rule_weight

  # This module supports the Linux Fargate sizes up to 16 vCPU.
  fargate_memory_by_cpu = {
    "256"   = [512, 1024, 2048]
    "512"   = range(1024, 4097, 1024)
    "1024"  = range(2048, 8193, 1024)
    "2048"  = range(4096, 16385, 1024)
    "4096"  = range(8192, 30721, 1024)
    "8192"  = range(16384, 61441, 4096)
    "16384" = range(32768, 122881, 8192)
  }
}
