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
