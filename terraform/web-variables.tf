variable "ecr_repository_name" {
  description = "Private ECR repository name; empty derives <cinema>-web in production, adding environment otherwise."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.ecr_repository_name == "" || (length(var.ecr_repository_name) >= 2 && length(var.ecr_repository_name) <= 256 && can(regex("^[a-z][a-z0-9]*([._/-][a-z0-9]+)*$", var.ecr_repository_name)))
    error_message = "Use a 2-256 character lowercase ECR name starting with a letter, with valid path/separator segments."
  }
}

variable "ecs_cluster_name" {
  description = "ECS cluster name; empty derives <cinema>-web-cluster-<environment suffix>."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.ecs_cluster_name == "" || can(regex("^[A-Za-z0-9_-]{1,255}$", var.ecs_cluster_name))
    error_message = "Use 1-255 letters, digits, underscores or hyphens."
  }
}

variable "ecs_service_name" {
  description = "ECS service name; empty derives <cinema>-web-service in production, adding environment otherwise."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.ecs_service_name == "" || can(regex("^[A-Za-z0-9_-]{1,255}$", var.ecs_service_name))
    error_message = "Use 1-255 letters, digits, underscores or hyphens."
  }
}

variable "ecs_task_family" {
  description = "Task-definition family; empty derives <cinema>-web-td in production, adding environment otherwise."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.ecs_task_family == "" || can(regex("^[A-Za-z0-9_-]{1,255}$", var.ecs_task_family))
    error_message = "Use 1-255 letters, digits, underscores or hyphens."
  }
}

variable "ecs_container_name" {
  description = "Essential web container name; empty derives <cinema>-web in production, adding environment otherwise."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.ecs_container_name == "" || can(regex("^[A-Za-z0-9_-]{1,255}$", var.ecs_container_name))
    error_message = "Use 1-255 letters, digits, underscores or hyphens."
  }
}

variable "alb_security_group_name" {
  description = "ALB security group name; empty derives <cinema>-<environment>-alb-sg."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.alb_security_group_name == "" || (length(var.alb_security_group_name) <= 255 && can(regex("^[a-zA-Z0-9 ._:/()#,@+=&;{}!$*-]+$", var.alb_security_group_name)) && !startswith(var.alb_security_group_name, "sg-"))
    error_message = "Use 1-255 EC2 security-group name characters; names must not start with sg-."
  }
}

variable "ecs_security_group_name" {
  description = "ECS security group name; empty derives <cinema>-<environment>-ecs-sg."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.ecs_security_group_name == "" || (length(var.ecs_security_group_name) <= 255 && can(regex("^[a-zA-Z0-9 ._:/()#,@+=&;{}!$*-]+$", var.ecs_security_group_name)) && !startswith(var.ecs_security_group_name, "sg-"))
    error_message = "Use 1-255 EC2 security-group name characters; names must not start with sg-."
  }
}

variable "efs_security_group_name" {
  description = "EFS security group name; empty derives <cinema>-<environment>-efs-sg."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.efs_security_group_name == "" || (length(var.efs_security_group_name) <= 255 && can(regex("^[a-zA-Z0-9 ._:/()#,@+=&;{}!$*-]+$", var.efs_security_group_name)) && !startswith(var.efs_security_group_name, "sg-"))
    error_message = "Use 1-255 EC2 security-group name characters; names must not start with sg-."
  }
}

variable "alb_name" {
  description = "ALB name; empty uses a deterministic client/environment name shortened to 32 characters if needed."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.alb_name == "" || (length(var.alb_name) <= 32 && can(regex("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", var.alb_name)) && !startswith(lower(var.alb_name), "internal-"))
    error_message = "Use 1-32 alphanumeric characters or hyphens, with no leading/trailing hyphen; ALB names cannot start with internal-."
  }
}

variable "alb_target_group_name" {
  description = "Target group name; empty uses a deterministic client/environment name shortened to 32 characters if needed."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.alb_target_group_name == "" || (length(var.alb_target_group_name) <= 32 && can(regex("^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$", var.alb_target_group_name)))
    error_message = "Use 1-32 alphanumeric characters or hyphens, with no leading/trailing hyphen; ALB names cannot start with internal-."
  }
}

variable "ecs_image_tag" {
  description = "Tag to pull from the new ECR repository. Push a linux/amd64 image before starting tasks."
  type        = string
  default     = "latest"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$", var.ecs_image_tag))
    error_message = "Use a valid image tag of 1-128 characters."
  }
}

variable "ecs_task_role_name" {
  description = "Existing IAM task role name, without its path. The role is only read, never created or modified."
  type        = string
  default     = "ecsTaskExecutionRole"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", var.ecs_task_role_name))
    error_message = "Use an existing IAM role name of 1-64 valid characters, without an ARN or path."
  }
}

variable "ecs_execution_role_name" {
  description = "Existing IAM task execution role name, without its path. The role is only read, never created or modified."
  type        = string
  default     = "ecsTaskExecutionRole"
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9_+=,.@-]{1,64}$", var.ecs_execution_role_name))
    error_message = "Use an existing IAM role name of 1-64 valid characters, without an ARN or path."
  }
}

variable "ecs_task_cpu" {
  description = "Fargate task CPU units (1024 = 1 vCPU). Supported combinations are checked with ecs_task_memory."
  type        = number
  default     = 1024
  nullable    = false

  validation {
    condition     = contains([256, 512, 1024, 2048, 4096, 8192, 16384], var.ecs_task_cpu)
    error_message = "Use a supported CPU value: 256, 512, 1024, 2048, 4096, 8192 or 16384."
  }
}

variable "ecs_task_memory" {
  description = "Task memory in MiB. Must be a supported Linux Fargate CPU/memory combination."
  type        = number
  default     = 2048
  nullable    = false

  validation {
    condition     = contains(lookup(local.fargate_memory_by_cpu, tostring(var.ecs_task_cpu), []), var.ecs_task_memory)
    error_message = "Unsupported Fargate CPU/memory combination; see the table in WEB-INFRASTRUCTURE.md."
  }
}

variable "ecs_container_cpu" {
  description = "CPU units allocated to the single web container; cannot exceed task CPU."
  type        = number
  default     = 1024
  nullable    = false

  validation {
    condition     = var.ecs_container_cpu >= 2 && floor(var.ecs_container_cpu) == var.ecs_container_cpu && var.ecs_container_cpu <= var.ecs_task_cpu
    error_message = "Container CPU must be an integer from 2 up to task CPU."
  }
}

variable "ecs_container_memory" {
  description = "Container hard memory limit in MiB; cannot exceed task memory."
  type        = number
  default     = 2048
  nullable    = false

  validation {
    condition     = var.ecs_container_memory >= 6 && floor(var.ecs_container_memory) == var.ecs_container_memory && var.ecs_container_memory <= var.ecs_task_memory
    error_message = "Container hard memory must be an integer from 6 MiB up to task memory."
  }
}

variable "ecs_container_memory_reservation" {
  description = "Container soft memory reservation in MiB; must be lower than its hard limit."
  type        = number
  default     = 1024
  nullable    = false

  validation {
    condition     = var.ecs_container_memory_reservation >= 6 && floor(var.ecs_container_memory_reservation) == var.ecs_container_memory_reservation && var.ecs_container_memory_reservation < var.ecs_container_memory
    error_message = "Container reservation must be at least 6 MiB and strictly less than the hard limit."
  }
}

variable "ecs_desired_count" {
  description = "Service task count. Keep zero for initial deployment; start tasks only after pushing the image."
  type        = number
  default     = 0
  nullable    = false

  validation {
    condition     = var.ecs_desired_count >= 0 && floor(var.ecs_desired_count) == var.ecs_desired_count
    error_message = "Desired count must be a nonnegative integer."
  }
}

variable "ecs_log_group_name" {
  description = "CloudWatch log group name; empty derives /ecs/<cinema>-<environment>/web."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.ecs_log_group_name == "" || (can(regex("^[A-Za-z0-9_./#-]{1,512}$", var.ecs_log_group_name)) && !startswith(var.ecs_log_group_name, "aws/"))
    error_message = "Use 1-512 valid CloudWatch log group characters; cannot start with aws/."
  }
}

variable "ecs_log_retention_days" {
  description = "Container log retention in days; 0 keeps logs indefinitely."
  type        = number
  default     = 30
  nullable    = false

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.ecs_log_retention_days)
    error_message = "Choose a supported CloudWatch Logs retention period, or 0 for no expiration."
  }
}

variable "ecs_log_stream_prefix" {
  description = "awslogs stream prefix; task streams are <prefix>/<container>/<task ID>."
  type        = string
  default     = "web"
  nullable    = false

  validation {
    condition     = can(regex("^[^:*]{1,128}$", var.ecs_log_stream_prefix))
    error_message = "Use a nonempty prefix up to 128 characters, excluding colon and asterisk."
  }
}

variable "efs_name" {
  description = "EFS Name tag; empty derives <cinema>-<environment suffix>."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = length(var.efs_name) <= 256
    error_message = "EFS Name tag cannot exceed 256 characters."
  }
}

variable "efs_creation_token" {
  description = "Stable EFS idempotency token; empty derives <cinema>-<environment>-efs. Changing this replaces the file system."
  type        = string
  default     = ""
  nullable    = false

  validation {
    condition     = var.efs_creation_token == "" || can(regex("^[A-Za-z0-9_-]{1,64}$", var.efs_creation_token))
    error_message = "Use a stable token of 1-64 letters, digits, underscores or hyphens."
  }
}
