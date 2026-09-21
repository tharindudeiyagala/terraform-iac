data "aws_iam_role" "api_ecs_task" {
  name = var.api_ecs_task_role_name
}

data "aws_iam_role" "api_ecs_execution" {
  name = var.api_ecs_execution_role_name
}

resource "aws_ecs_cluster" "api" {
  name = local.api_ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }

  tags = { Name = local.api_ecs_cluster_name }
}

resource "aws_ecs_cluster_capacity_providers" "api" {
  cluster_name       = aws_ecs_cluster.api.name
  capacity_providers = ["FARGATE"]
}

resource "aws_cloudwatch_log_group" "api_ecs" {
  name              = local.api_ecs_log_group_name
  retention_in_days = var.api_ecs_log_retention_days
  tags              = { Name = local.api_ecs_log_group_name }
}

resource "aws_ecs_task_definition" "api" {
  family                   = local.api_ecs_task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.api_ecs_task_cpu)
  memory                   = tostring(var.api_ecs_task_memory)
  task_role_arn            = data.aws_iam_role.api_ecs_task.arn
  execution_role_arn       = data.aws_iam_role.api_ecs_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name              = local.api_ecs_container_name
    essential         = true
    image             = "${aws_ecr_repository.api.repository_url}:${var.api_ecs_image_tag}"
    cpu               = var.api_ecs_container_cpu
    memory            = var.api_ecs_container_memory
    memoryReservation = var.api_ecs_container_memory_reservation

    portMappings = [{
      containerPort = 80
      hostPort      = 80
      protocol      = "tcp"
      name          = "api"
      appProtocol   = "http"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.api_ecs.name
        awslogs-region        = var.aws_region
        mode                  = "non-blocking"
        max-buffer-size       = "25m"
        awslogs-stream-prefix = var.api_ecs_log_stream_prefix
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost/health.php || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }
  }])

  # The API has no requested volumes. Terraform creates its log group before task registration.
  tags = { Name = local.api_ecs_task_family }
}

resource "aws_ecs_service" "api" {
  name                               = local.api_ecs_service_name
  cluster                            = aws_ecs_cluster.api.id
  task_definition                    = aws_ecs_task_definition.api.arn
  launch_type                        = "FARGATE"
  scheduling_strategy                = "REPLICA"
  desired_count                      = var.api_ecs_desired_count
  availability_zone_rebalancing      = "ENABLED"
  health_check_grace_period_seconds  = 10
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  deployment_controller {
    type = "ECS"
  }

  deployment_configuration {
    strategy = "ROLLING"
  }

  network_configuration {
    subnets          = [for k in ["0", "1"] : aws_subnet.public[k].id]
    security_groups  = [aws_security_group.api_ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = local.api_ecs_container_name
    container_port   = 80
  }

  tags = { Name = local.api_ecs_service_name }

  depends_on = [
    aws_lb_listener.api_http,
    aws_ecs_cluster_capacity_providers.api,
    aws_route.public_internet,
    aws_route_table_association.public,
    aws_vpc_security_group_ingress_rule.api_ecs_alb,
    aws_vpc_security_group_egress_rule.api_ecs,
  ]
}
