# Sanitized client example; copy to new-cinema-prod.tfvars before customization.
# Create/select workspace new-cinema-production before using this file.
cinema_name = "new-cinema"
environment = "production"
aws_region  = "ap-south-1" # Example assumption: choose your target Region.

vpc_name             = "new-cinema-prod-vpc"
vpc_cidr             = "10.0.0.0/16"
availability_zones   = ["ap-south-1a", "ap-south-1b"]
public_subnet_cidrs  = ["10.0.1.0/24", "10.0.2.0/24"]
private_subnet_cidrs = ["10.0.11.0/24", "10.0.12.0/24"]
nat_mode             = "none"

ec2_name                = "new-cinema-production"
ec2_security_group_name = "new-cinema-production-ec2-sg"
instance_type           = "t4g.micro"
ec2_public_subnet_index = 0
ami_id                  = "" # Resolve official Canonical Ubuntu 24.04 ARM64.
key_pair_name           = "replace-with-existing-key-pair"
root_volume_size        = 50
root_volume_type        = "gp3"
ssh_allowed_cidrs       = ["0.0.0.0/0"] # Requested default; restrict for your operators.

rds_security_group_name   = "new-cinema-production-rds-sg"
db_identifier             = "new-cinema-production"
db_engine_version         = "8.4.11"
db_instance_class         = "db.t4g.micro"
db_username               = "root"
db_name                   = "newcinema_production"
db_allocated_storage      = 50
db_max_allocated_storage  = 100
db_parameter_group_name   = "default.mysql8.4"
enable_slow_query_logging = false

backup_retention_period   = 30
backup_window             = "06:00-06:30"
maintenance_window        = "mon:07:00-mon:07:30"
deletion_protection       = true
skip_final_snapshot       = false
final_snapshot_identifier = "" # Derives new-cinema-production-final.

additional_tags = {
  ManagedBy = "Terraform"
}

# Required db_password deliberately omitted. Supply via secure prompt/environment.
