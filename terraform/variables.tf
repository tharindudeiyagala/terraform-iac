variable "cinema_name" {
  description = "Client identifier and mandatory cinema tag; use a lowercase slug."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.cinema_name)) && length(var.cinema_name) <= 30
    error_message = "Use a lowercase slug starting with a letter, up to 30 characters."
  }
}

variable "environment" {
  description = "Environment suffix used in supporting names and state workspace."
  type        = string
  default     = "production"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.environment)) && length(var.environment) <= 15
    error_message = "Use a lowercase slug starting with a letter, up to 15 characters."
  }
}

variable "aws_region" {
  description = "AWS Region. Mumbai is an example assumption; change for each client."
  type        = string
  default     = "ap-south-1"
  nullable    = false

  validation {
    condition     = can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.aws_region))
    error_message = "Supply an AWS Region code."
  }
}

variable "additional_tags" {
  description = "Additional tags. Mandatory cinema, Environment, and resource Name tags take precedence."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "name_overrides" {
  description = "Optional supporting Name overrides; see README for accepted keys."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition     = alltrue([for k, value in var.name_overrides : contains(["internet_gateway", "public_route_table", "public_subnet_0", "public_subnet_1", "private_subnet_0", "private_subnet_1", "private_route_table_0", "private_route_table_1", "nat_gateway_0", "nat_gateway_1", "nat_eip_0", "nat_eip_1", "db_subnet_group", "db_option_group", "db_parameter_group"], k) && length(trimspace(value)) > 0])
    error_message = "Use documented supporting resource keys and non-empty names."
  }
}

variable "vpc_name" {
  description = "VPC Name tag; empty derives it from cinema_name and environment."
  type        = string
  default     = ""
  nullable    = false
}

variable "ec2_name" {
  description = "EC2 Name tag; empty derives it from cinema_name and environment."
  type        = string
  default     = ""
  nullable    = false
}

variable "ec2_security_group_name" {
  description = "EC2 security group name; empty derives it from cinema_name and environment."
  type        = string
  default     = ""
  nullable    = false
}

variable "rds_security_group_name" {
  description = "RDS security group name; empty derives it from cinema_name and environment."
  type        = string
  default     = ""
  nullable    = false
}

variable "db_identifier" {
  description = "RDS DB instance identifier; empty derives it from cinema_name and environment."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.db_identifier == "" || (can(regex("^[a-z][a-z0-9-]{0,62}$", var.db_identifier)) && !endswith(var.db_identifier, "-") && !strcontains(var.db_identifier, "--"))
    error_message = "Use 1-63 lowercase letters, digits, and hyphens, starting with a letter; no trailing or consecutive hyphens."
  }
}

variable "vpc_cidr" {
  description = "Canonical IPv4 VPC CIDR, prefix /16 through /28."
  type        = string
  default     = "10.0.0.0/16"
  nullable    = false

  validation {
    condition     = try(cidrnetmask(var.vpc_cidr) != "" && tonumber(split("/", var.vpc_cidr)[1]) >= 16 && tonumber(split("/", var.vpc_cidr)[1]) <= 28 && cidrhost(var.vpc_cidr, 0) == split("/", var.vpc_cidr)[0], false)
    error_message = "Use a canonical IPv4 CIDR with a prefix between /16 and /28."
  }
}

variable "availability_zones" {
  description = "Exactly two distinct standard AZ names in aws_region; empty selects the first two available AZs."
  type        = list(string)
  default     = []
  nullable    = false

  validation {
    condition     = length(var.availability_zones) == 0 || (length(var.availability_zones) == 2 && length(distinct(var.availability_zones)) == 2)
    error_message = "Provide exactly two distinct AZ names, or an empty list for discovery."
  }
}

variable "public_subnet_cidrs" {
  description = "Two canonical IPv4 subnet CIDRs, in the same order as availability_zones."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
  nullable    = false

  validation {
    condition     = length(var.public_subnet_cidrs) == 2 && alltrue([for c in var.public_subnet_cidrs : try(cidrnetmask(c) != "" && tonumber(split("/", c)[1]) >= 16 && tonumber(split("/", c)[1]) <= 28 && cidrhost(c, 0) == split("/", c)[0], false)])
    error_message = "Provide exactly two canonical IPv4 subnet CIDRs with prefixes between /16 and /28."
  }
}

variable "private_subnet_cidrs" {
  description = "Two canonical IPv4 subnet CIDRs, in the same order as availability_zones."
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]
  nullable    = false

  validation {
    condition     = length(var.private_subnet_cidrs) == 2 && alltrue([for c in var.private_subnet_cidrs : try(cidrnetmask(c) != "" && tonumber(split("/", c)[1]) >= 16 && tonumber(split("/", c)[1]) <= 28 && cidrhost(c, 0) == split("/", c)[0], false)])
    error_message = "Provide exactly two canonical IPv4 subnet CIDRs with prefixes between /16 and /28."
  }
}

variable "nat_mode" {
  description = "Private subnet internet egress: none, single in public subnet 0, or per_az."
  type        = string
  default     = "none"
  nullable    = false

  validation {
    condition     = contains(["none", "single", "per_az"], var.nat_mode)
    error_message = "nat_mode must be none, single, or per_az."
  }
}

variable "ec2_public_subnet_index" {
  description = "Public subnet index for the EC2 instance: 0 or 1."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = contains([0, 1], var.ec2_public_subnet_index)
    error_message = "Select public subnet 0 or 1."
  }
}

variable "ami_id" {
  description = "Optional regional AMI override. Must remain Ubuntu 24.04 ARM64; empty uses Canonical SSM."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.ami_id == "" || can(regex("^ami-[0-9a-f]{8,17}$", var.ami_id))
    error_message = "Use an AMI ID or an empty string."
  }
}

variable "instance_type" {
  description = "ARM64-capable EC2 instance type."
  type        = string
  default     = "t4g.micro"
  nullable    = false
}

variable "key_pair_name" {
  description = "Existing EC2 key pair in the selected Region; private key is managed outside Terraform."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.key_pair_name)) > 0
    error_message = "Supply an existing EC2 key pair name."
  }
}

variable "root_volume_size" {
  description = "Root EBS size in GiB; must fit the selected AMI."
  type        = number
  default     = 50
  nullable    = false

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 16384 && floor(var.root_volume_size) == var.root_volume_size
    error_message = "Use an integer from 8 to 16384 GiB; it must also fit the selected AMI."
  }
}

variable "root_volume_type" {
  description = "Root EBS type; gp2 and gp3 need no explicit IOPS configuration."
  type        = string
  default     = "gp3"
  nullable    = false

  validation {
    condition     = contains(["gp2", "gp3"], var.root_volume_type)
    error_message = "Use gp2 or gp3."
  }
}

variable "ssh_allowed_cidrs" {
  description = "IPv4 SSH sources. The requested default permits SSH from anywhere; restrict for each client."
  type        = set(string)
  default     = ["0.0.0.0/0"]
  nullable    = false

  validation {
    condition     = length(var.ssh_allowed_cidrs) > 0 && alltrue([for c in var.ssh_allowed_cidrs : try(cidrnetmask(c) != "" && cidrhost(c, 0) == split("/", c)[0], false)])
    error_message = "Supply at least one canonical IPv4 CIDR."
  }
}

variable "db_engine_version" {
  description = "Exact MySQL 8.4 version; never automatically substitute an available version."
  type        = string
  default     = "8.4.11"
  nullable    = false

  validation {
    condition     = can(regex("^8\\.4\\.[0-9]+$", var.db_engine_version))
    error_message = "Use an exact MySQL 8.4 patch version, for example 8.4.11."
  }
}

variable "db_instance_class" {
  description = "RDS instance class; verified against the exact engine version in the selected Region."
  type        = string
  default     = "db.t4g.micro"
  nullable    = false
}

variable "db_username" {
  description = "Self-managed MySQL master username."
  type        = string
  default     = "root"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,15}$", var.db_username)) && !contains(local.mysql_reserved_words, upper(var.db_username)) && lower(var.db_username) != "rdsadmin"
    error_message = "Use 1-16 letters, digits, or underscores, starting with a letter; reserved usernames are not allowed."
  }
}

variable "db_name" {
  description = "Initial MySQL database name: 1-64 characters, starts with a letter, no reserved keywords."
  type        = string
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9_]{0,63}$", var.db_name)) && !contains(local.mysql_reserved_words, upper(var.db_name)) && !contains(["mysql", "information_schema", "performance_schema", "sys"], lower(var.db_name))
    error_message = "Use 1-64 letters, digits, or underscores starting with a letter; MySQL reserved keywords and system schemas are forbidden."
  }
}

variable "db_password" {
  description = "Required self-managed master password. Sensitive, but stored in Terraform state and saved plans."
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.db_password) >= 8 && length(var.db_password) <= 41 && can(regex("^[!-~]+$", var.db_password)) && !can(regex("[/@\"]", var.db_password))
    error_message = "Use 8-41 printable ASCII characters, excluding slash, double quote, at sign, and spaces."
  }
}

variable "db_allocated_storage" {
  description = "RDS gp3 storage in GiB; maximum must be at least 10% above allocated storage."
  type        = number
  default     = 50
  nullable    = false

  validation {
    condition     = var.db_allocated_storage >= 20 && var.db_allocated_storage <= 65536 && floor(var.db_allocated_storage) == var.db_allocated_storage
    error_message = "Use an integer from 20 to 65536 GiB."
  }
}

variable "db_max_allocated_storage" {
  description = "RDS gp3 storage in GiB; maximum must be at least 10% above allocated storage."
  type        = number
  default     = 100
  nullable    = false

  validation {
    condition     = var.db_max_allocated_storage >= 20 && var.db_max_allocated_storage <= 65536 && floor(var.db_max_allocated_storage) == var.db_max_allocated_storage
    error_message = "Use an integer from 20 to 65536 GiB."
  }
}

variable "db_parameter_group_name" {
  description = "Existing MySQL 8.4 parameter group used when optional slow-query logging is disabled."
  type        = string
  default     = "default.mysql8.4"
  nullable    = false
}

variable "enable_slow_query_logging" {
  description = "Create and attach a mysql8.4 parameter group with slow_query_log=1 and log_output=FILE."
  type        = bool
  default     = false
  nullable    = false
}

variable "backup_retention_period" {
  description = "Automated backup retention in days."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = var.backup_retention_period >= 1 && var.backup_retention_period <= 35 && floor(var.backup_retention_period) == var.backup_retention_period
    error_message = "Use an integer from 1 to 35 days."
  }
}

variable "backup_window" {
  description = "Daily UTC backup window; assumed 30 minutes from the supplied 06:00 start."
  type        = string
  default     = "06:00-06:30"
  nullable    = false

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]-([01][0-9]|2[0-3]):[0-5][0-9]$", var.backup_window))
    error_message = "Use HH:MM-HH:MM in UTC."
  }
}

variable "maintenance_window" {
  description = "Weekly UTC maintenance window; assumed 30 minutes from the supplied Monday 07:00 start."
  type        = string
  default     = "mon:07:00-mon:07:30"
  nullable    = false

  validation {
    condition     = can(regex("^(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]-(mon|tue|wed|thu|fri|sat|sun):([01][0-9]|2[0-3]):[0-5][0-9]$", var.maintenance_window))
    error_message = "Use ddd:HH:MM-ddd:HH:MM in UTC."
  }
}

variable "deletion_protection" {
  description = "Prevent RDS deletion; disable and apply separately before an intentional destroy."
  type        = bool
  default     = true
  nullable    = false
}

variable "skip_final_snapshot" {
  description = "Skip the final RDS snapshot on deletion. Production default is false."
  type        = bool
  default     = false
  nullable    = false
}

variable "final_snapshot_identifier" {
  description = "Optional final snapshot identifier; empty derives <DB identifier>-final. Must be unique at deletion."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.final_snapshot_identifier == "" || (can(regex("^[a-z][a-z0-9-]{0,254}$", var.final_snapshot_identifier)) && !endswith(var.final_snapshot_identifier, "-") && !strcontains(var.final_snapshot_identifier, "--"))
    error_message = "Use a lowercase snapshot identifier starting with a letter, with no trailing or consecutive hyphens."
  }
}
