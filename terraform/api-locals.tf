locals {
  api_environment_suffix = var.environment == "production" ? "prod" : var.environment
  api_workload_prefix    = var.environment == "production" ? var.cinema_name : local.name_prefix

  api_ecr_repository_name     = var.api_ecr_repository_name != "" ? var.api_ecr_repository_name : "${local.api_workload_prefix}-api"
  api_ecs_cluster_name        = var.api_ecs_cluster_name != "" ? var.api_ecs_cluster_name : "${var.cinema_name}-api-cluster-${local.api_environment_suffix}"
  api_ecs_service_name        = var.api_ecs_service_name != "" ? var.api_ecs_service_name : "${local.api_workload_prefix}-api-service"
  api_ecs_task_family         = var.api_ecs_task_family != "" ? var.api_ecs_task_family : "${local.api_workload_prefix}-api-td"
  api_ecs_container_name      = var.api_ecs_container_name != "" ? var.api_ecs_container_name : "${local.api_workload_prefix}-api"
  api_alb_security_group_name = var.api_alb_security_group_name != "" ? var.api_alb_security_group_name : "${local.name_prefix}-api-alb-sg"
  api_ecs_security_group_name = var.api_ecs_security_group_name != "" ? var.api_ecs_security_group_name : "${local.name_prefix}-api-ecs-sg"
  api_ecs_log_group_name      = var.api_ecs_log_group_name != "" ? var.api_ecs_log_group_name : "/ecs/${local.name_prefix}/api"

  # AWS limits ALB and target-group names to 32 characters.
  api_alb_name_base          = "${var.cinema_name}-${local.api_environment_suffix}-api-alb"
  api_target_group_name_base = "${local.name_prefix}-api-tg"
  api_alb_name = var.api_alb_name != "" ? var.api_alb_name : (
    length(local.api_alb_name_base) <= 32 ? local.api_alb_name_base : "${substr(local.api_alb_name_base, 0, 23)}-${substr(sha256(local.api_alb_name_base), 0, 8)}"
  )
  api_alb_target_group_name = var.api_alb_target_group_name != "" ? var.api_alb_target_group_name : (
    length(local.api_target_group_name_base) <= 32 ? local.api_target_group_name_base : "${substr(local.api_target_group_name_base, 0, 23)}-${substr(sha256(local.api_target_group_name_base), 0, 8)}"
  )
}
