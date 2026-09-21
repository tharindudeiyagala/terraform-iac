output "api_ecr_repository_url" {
  description = "Private API ECR repository URL."
  value       = aws_ecr_repository.api.repository_url
}

output "api_ecr_repository_arn" {
  description = "Private API ECR repository ARN."
  value       = aws_ecr_repository.api.arn
}

output "api_ecs_image_uri" {
  description = "API image URI that must exist before starting tasks."
  value       = "${aws_ecr_repository.api.repository_url}:${var.api_ecs_image_tag}"
}

output "api_ecs_cluster_name" {
  description = "API Fargate cluster name."
  value       = aws_ecs_cluster.api.name
}

output "api_ecs_cluster_arn" {
  description = "API Fargate cluster ARN."
  value       = aws_ecs_cluster.api.arn
}

output "api_ecs_service_name" {
  description = "API ECS service name; starts with zero tasks by default."
  value       = aws_ecs_service.api.name
}

output "api_ecs_task_definition_arn" {
  description = "Current API task-definition revision ARN."
  value       = aws_ecs_task_definition.api.arn
}

output "api_ecs_log_group_name" {
  description = "API CloudWatch log group."
  value       = aws_cloudwatch_log_group.api_ecs.name
}

output "api_alb_security_group_id" {
  description = "API ALB security group ID."
  value       = aws_security_group.api_alb.id
}

output "api_ecs_security_group_id" {
  description = "API ECS security group ID."
  value       = aws_security_group.api_ecs.id
}

output "api_alb_dns_name" {
  description = "API ALB DNS name; ingress is restricted to CloudFront."
  value       = aws_lb.api.dns_name
}

output "api_alb_arn" {
  description = "API Application Load Balancer ARN."
  value       = aws_lb.api.arn
}

output "api_alb_listener_arn" {
  description = "API HTTP port 80 listener ARN."
  value       = aws_lb_listener.api_http.arn
}

output "api_alb_target_group_arn" {
  description = "API IP target group ARN; ECS manages target registration."
  value       = aws_lb_target_group.api.arn
}
