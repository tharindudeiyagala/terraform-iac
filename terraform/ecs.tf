data "aws_iam_role" "ecs_task" {
  name = var.ecs_task_role_name
}

data "aws_iam_role" "ecs_execution" {
  name = var.ecs_execution_role_name
}

resource "aws_ecs_cluster" "web" {
  name = local.ecs_cluster_name

  setting {
    name  = "containerInsights"
    value = "disabled"
  }

  configuration {
    execute_command_configuration {
      logging = "DEFAULT"
    }
  }

  tags = { Name = local.ecs_cluster_name }
}

resource "aws_ecs_cluster_capacity_providers" "web" {
  cluster_name       = aws_ecs_cluster.web.name
  capacity_providers = ["FARGATE"]
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = local.ecs_log_group_name
  retention_in_days = var.ecs_log_retention_days
  tags              = { Name = local.ecs_log_group_name }
}

resource "aws_ecs_task_definition" "web" {
  family                   = local.ecs_task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.ecs_task_cpu)
  memory                   = tostring(var.ecs_task_memory)
  task_role_arn            = data.aws_iam_role.ecs_task.arn
  execution_role_arn       = data.aws_iam_role.ecs_execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name              = local.ecs_container_name
    essential         = true
    image             = "${aws_ecr_repository.web.repository_url}:${var.ecs_image_tag}"
    cpu               = var.ecs_container_cpu
    memory            = var.ecs_container_memory
    memoryReservation = var.ecs_container_memory_reservation

    portMappings = [{
      containerPort = 80
      protocol      = "tcp"
      name          = "web"
      appProtocol   = "http"
    }]

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.ecs.name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = var.ecs_log_stream_prefix
      }
    }

    healthCheck = {
      command     = ["CMD-SHELL", "curl -f http://localhost/api/health || exit 1"]
      interval    = 30
      timeout     = 5
      retries     = 3
      startPeriod = 10
    }
  }])

  # EFS is provisioned separately; no application mount path was specified.
  tags = { Name = local.ecs_task_family }
}

resource "aws_ecs_service" "web" {
  name                               = local.ecs_service_name
  cluster                            = aws_ecs_cluster.web.id
  task_definition                    = aws_ecs_task_definition.web.arn
  launch_type                        = "FARGATE"
  scheduling_strategy                = "REPLICA"
  desired_count                      = var.ecs_desired_count
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
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = local.ecs_container_name
    container_port   = 80
  }

  tags = { Name = local.ecs_service_name }

  depends_on = [
    aws_lb_listener.http,
    aws_ecs_cluster_capacity_providers.web,
    aws_route.public_internet,
    aws_route_table_association.public,
    aws_vpc_security_group_ingress_rule.ecs_alb,
    aws_vpc_security_group_egress_rule.ecs,
  ]
}
