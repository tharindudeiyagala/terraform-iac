output "vpc_id" {
  description = "Cinema VPC ID."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs in availability_zones order."
  value       = [for k in ["0", "1"] : aws_subnet.public[k].id]
}

output "private_subnet_ids" {
  description = "Private subnet IDs in availability_zones order."
  value       = [for k in ["0", "1"] : aws_subnet.private[k].id]
}

output "availability_zones" {
  description = "Selected Availability Zones in subnet order."
  value       = local.azs
}

output "ec2_instance_id" {
  description = "Cinema EC2 instance ID."
  value       = aws_instance.this.id
}

output "ec2_public_ip" {
  description = "Automatically assigned EC2 public IPv4; can change after stop/start."
  value       = aws_instance.this.public_ip
}

output "ec2_public_dns" {
  description = "Public DNS name of the EC2 instance."
  value       = aws_instance.this.public_dns
}

output "ec2_security_group_id" {
  description = "EC2 security group ID."
  value       = aws_security_group.ec2.id
}

output "rds_security_group_id" {
  description = "RDS security group ID."
  value       = aws_security_group.rds.id
}

output "rds_endpoint" {
  description = "Private RDS endpoint including port."
  value       = aws_db_instance.this.endpoint
}

output "rds_port" {
  description = "MySQL listener port."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Initial MySQL database name."
  value       = aws_db_instance.this.db_name
}

output "ecr_repository_url" {
  description = "Private ECR repository URL; append the configured image tag."
  value       = aws_ecr_repository.web.repository_url
}

output "ecr_repository_arn" {
  description = "Private ECR repository ARN."
  value       = aws_ecr_repository.web.arn
}

output "ecs_cluster_name" {
  description = "Fargate cluster name."
  value       = aws_ecs_cluster.web.name
}

output "ecs_cluster_arn" {
  description = "Fargate cluster ARN."
  value       = aws_ecs_cluster.web.arn
}

output "ecs_service_name" {
  description = "ECS service name; initially has zero tasks."
  value       = aws_ecs_service.web.name
}

output "ecs_task_definition_arn" {
  description = "Current task-definition revision ARN."
  value       = aws_ecs_task_definition.web.arn
}

output "ecs_log_group_name" {
  description = "Container CloudWatch log group."
  value       = aws_cloudwatch_log_group.ecs.name
}

output "ecs_image_uri" {
  description = "Image URI that must exist before starting tasks."
  value       = "${aws_ecr_repository.web.repository_url}:${var.ecs_image_tag}"
}

output "alb_security_group_id" {
  description = "ALB security group ID."
  value       = aws_security_group.alb.id
}

output "ecs_security_group_id" {
  description = "ECS security group ID."
  value       = aws_security_group.ecs.id
}

output "efs_security_group_id" {
  description = "EFS security group ID."
  value       = aws_security_group.efs.id
}

output "alb_dns_name" {
  description = "ALB DNS name; ingress is restricted to CloudFront."
  value       = aws_lb.web.dns_name
}

output "alb_arn" {
  description = "Application Load Balancer ARN."
  value       = aws_lb.web.arn
}

output "alb_listener_arn" {
  description = "HTTP port 80 listener ARN."
  value       = aws_lb_listener.http.arn
}

output "alb_target_group_arn" {
  description = "IP target group ARN; ECS manages target registration."
  value       = aws_lb_target_group.web.arn
}

output "efs_id" {
  description = "Regional encrypted EFS file-system ID."
  value       = aws_efs_file_system.web.id
}

output "efs_dns_name" {
  description = "Regional EFS DNS name; mounts are a separate application configuration step."
  value       = aws_efs_file_system.web.dns_name
}

output "efs_mount_target_ids" {
  description = "EFS mount targets keyed by the existing private-subnet indices."
  value       = { for k, target in aws_efs_mount_target.web : k => target.id }
}
