# API infrastructure

The API is a separate ECR repository, ECS Fargate cluster/service, task
definition, CloudWatch log group, ALB, target group, listener and two security
groups. It adds 17 managed resource instances to the existing root module.
It shares the cinema VPC, its two public subnets, routing, Region and common
tags. All taggable API resources inherit `cinema = var.cinema_name` and
`Environment = var.environment`, with a resource-specific `Name` tag.

The existing web, EC2, RDS and EFS resource definitions and state addresses
are preserved. The API is included automatically in the same client workspace;
there is no additional VPC or separate API workspace.

## Requested configuration

| Component | Configuration |
| --- | --- |
| ECR | Private, MUTABLE tags, AES256 encryption |
| API ALB SG | TCP 80/443 from the AWS CloudFront origin-facing IPv4 managed prefix list; all IPv4 outbound |
| API ECS SG | TCP 80/443 from the API ALB SG only; all IPv4 outbound |
| Cluster | FARGATE only; Container Insights disabled; ECS Exec logging DEFAULT |
| Task | FARGATE, Linux X86_64, awsvpc, 1024 CPU units / 2048 MiB |
| Roles | Existing `ecsTaskExecutionRole` for both task and execution roles; configurable independently |
| Container | Essential; image from the API ECR repository; TCP container/host port 80; port name `api`; app protocol `http` |
| Container limits | 1024 CPU units, 2048 MiB hard limit, 1024 MiB soft reservation |
| Container health | `CMD-SHELL`, `curl -f http://localhost/health.php \|\| exit 1`; interval 30s, timeout 5s, retries 3, start period 10s |
| Logs | awslogs; Terraform-managed group, 30-day retention by default, stream prefix `ecs`, non-blocking mode, 25m buffer |
| Target group | IP targets, HTTP:80, IPv4, HTTP1; Target Optimizer disabled |
| ALB health | `/health.php`, traffic port, healthy threshold 5, unhealthy threshold 2, interval 30s, success codes 200-299 |
| ALB | Internet-facing Application Load Balancer, IPv4, both existing public subnets; HTTP:80 listener forwards to the API target group |
| Service | FARGATE launch type, REPLICA, desired count 0, AZ rebalancing ENABLED, health grace 10s |
| Deployment | ECS controller, ROLLING, minimum healthy 100%, maximum 200% |
| Task networking | Both existing public subnets, public IP enabled, API ECS SG only |

The supplied old task JSON is a reference, not an import: its account ID, ARNs,
revision, image tag and registration metadata are not copied. The explicit
10-second health start period is included. Other storage settings retain
the Fargate default (20 GiB on Linux platform 1.4.0 or later), instead of the old
sample's custom 21 GiB. No API volume mounts were requested.
[AWS Fargate storage](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-storage.html)

Terraform creates the log group before the task definition, so the container
does not need `awslogs-create-group` or permission to create groups. The existing
execution role still needs ECR pull and CloudWatch stream/write permissions.
Non-blocking logging can drop messages if its buffer fills.
[AWS task parameters](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html)

## Inputs

All new inputs are optional. Empty name overrides derive from `cinema_name`
and `environment`. Existing client tfvars therefore work without adding API
names. For `new-cinema` / `production`, the defaults are:

| Variable | Derived default |
| --- | --- |
| `api_ecr_repository_name` | `new-cinema-api` |
| `api_ecs_cluster_name` | `new-cinema-api-cluster-prod` |
| `api_ecs_task_family` | `new-cinema-api-td` |
| `api_ecs_container_name` | `new-cinema-api` |
| `api_ecs_service_name` | `new-cinema-api-service` |
| `api_alb_security_group_name` | `new-cinema-production-api-alb-sg` |
| `api_ecs_security_group_name` | `new-cinema-production-api-ecs-sg` |
| `api_alb_name` | `new-cinema-prod-api-alb` |
| `api_alb_target_group_name` | `new-cinema-production-api-tg` |
| `api_ecs_log_group_name` | `/ecs/new-cinema-production/api` |

Other environments include their name in repositories, task families and
services to avoid production collisions. Long derived ALB/target-group names
use a stable hash suffix to fit AWS's 32-character limit. Explicit name
overrides must be unique in their applicable account/Region scope.

| Variable | Default |
| --- | --- |
| `api_ecs_task_role_name`, `api_ecs_execution_role_name` | `ecsTaskExecutionRole` |
| `api_ecs_image_tag` | `latest` |
| `api_ecs_task_cpu`, `api_ecs_container_cpu` | `1024` |
| `api_ecs_task_memory`, `api_ecs_container_memory` | `2048` MiB |
| `api_ecs_container_memory_reservation` | `1024` MiB |
| `api_ecs_desired_count` | `0` |
| `api_ecs_log_retention_days` | `30` (`0` keeps logs indefinitely) |
| `api_ecs_log_stream_prefix` | `ecs` |

Sizing uses the same supported Linux Fargate combinations as
[the web stack](WEB-INFRASTRUCTURE.md), up to 16 vCPU. API inputs affect only the
API workload. The existing web task-count input is `ecs_desired_count`.

## Prerequisites and application access

- Use the existing client workspace and state. Existing shared resources must
  remain in that state; do not create an empty API workspace.
- Both selected IAM roles must exist, trust `ecs-tasks.amazonaws.com`, and
  grant the required runtime permissions. The deployer needs `iam:GetRole`
  and `iam:PassRole` plus ECR/ECS/ELB/Logs/VPC management permissions. Terraform
  reads these roles and does not create or modify them.
  [AWS execution role](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html)
- Each ALB SG needs quota for 110 weighted inbound rules. The existing EC2 SG
  needs 110 plus its SSH CIDRs (111 with one CIDR). These are per-group limits,
  not a sum across ALBs. Existing quota 120 is sufficient for these rules.
  Terraform checks regional VPC quota `L-0EA8095F`.
  [AWS prefix-list weights](https://docs.aws.amazon.com/vpc/latest/userguide/working-with-aws-managed-prefix-lists.html)
- ALB public subnets must be /27 or larger with enough free addresses for both
  ALBs and running tasks. Live subnet capacity and account quotas still need
  to be available; offline tests cannot establish them.
- Before starting tasks, push a Linux AMD64 API image with a shell and `curl`.
  The application must listen on `0.0.0.0:80` and serve `/health.php`.
- CloudFront is not provisioned by this extension. The ALB accepts origin
  traffic only from the CloudFront prefix list, so direct browser requests
  to the ALB DNS are blocked. Only HTTP:80 has a listener; allowing 443 in the
  SG does not create HTTPS or install a certificate.
- API database credentials/environment settings are application configuration.
  The current RDS SG permits MySQL from EC2 only; API-to-RDS access would need
  an explicit SG rule. Existing EFS permits NFS from the web ECS SG only.
  No API-to-RDS/EFS access or mounts are added by this request.

## Short deployment steps for Lanka Cinema

Use PowerShell with your working AWS credentials. Run each command separately
and stop on errors:

~~~powershell
Set-Location C:\Data\terraform-iac\terraform
aws sts get-caller-identity
terraform init
terraform workspace select lanka-cinema-production
terraform validate
terraform apply "-var-file=lanka-cinema-prod.tfvars"
~~~

Enter the existing MySQL master password if the database exists, or the intended
new password if it is being recreated. Review the plan, then type `yes` to apply.
If the original stack still exists in state, this extension adds API resources.
If it was destroyed, apply recreates the full configured stack. Investigate
unexpected replacement/deletion before confirming; a moving Ubuntu AMI can
also produce an unrelated EC2 replacement.

No edits to the real Lanka tfvars are required for API defaults. For example,
the repository derives `lanka-cinema-api`. Do not overwrite the client tfvars
with the sanitized example. All password/state precautions in the root README
still apply.

After applying:

~~~powershell
terraform output api_ecr_repository_url
terraform output api_ecs_cluster_name
terraform output api_alb_dns_name
~~~

To run the API, push the application image to that repository, set
`api_ecs_image_tag` to its tag and `api_ecs_desired_count = 1` in the client tfvars,
then run the same apply command again. Prefer a new image tag for each release;
overwriting a mutable tag alone does not update existing running tasks.

## Removal and verification

API resources are part of the same full-stack destroy. Empty the API and web ECR
repositories before destroy if they contain images; forced deletion is not
enabled. Apply the RDS deletion-protection change first as described in the
root README. Do not delete the state file or select an empty workspace.

Verified with Terraform 1.12.0 and AWS provider 6.64.0: formatting and
`terraform validate` passed; the full mocked suite passed **40 tests, 0 failed**.
New tests cover separate API routing/security, exact health and log
configuration, zero-task defaults, independent overrides, invalid sizing/names,
and client/environment naming. All AWS calls in these tests are mocked; no live
AWS plan or apply was run for this extension.
