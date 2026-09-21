# ECS web infrastructure extension

This extension adds private ECR, a Fargate ECS cluster/task definition/service,
an internet-facing ALB and IP target group, three security groups, and Regional
EFS. It reuses the original VPC, both public/private subnet pairs, common tags,
AWS Region and client workspace convention. Existing EC2, RDS and networking
resource definitions are unchanged.

**The initial service has desired count 0.** There are no running tasks and no
healthy targets until an operator pushes a compatible image and increases the
count. Terraform does not build/push images or deploy application code. The ALB
exists and incurs charges even with zero tasks.

## Traffic and resource behavior

- CloudFront IPv4 origin-facing prefix list -> ALB SG: TCP 80 and 443.
- ALB SG -> ECS SG: TCP 80 and 443. Tasks use both existing public subnets and
  receive public IPv4 addresses for ECR/CloudWatch access through the existing
  Internet Gateway. NAT is not needed for this path.
- ECS SG -> EFS SG: exactly one TCP 2049 rule. There is no EC2-to-EFS rule.
  EFS mount targets occupy private subnet keys `"0"` and `"1"`.
- These groups permit all outbound IPv4 traffic. The prefix list and quota data
  sources from `security-groups.tf` are reused, without hardcoded prefix IDs.
- The ALB is application/IPv4/internet-facing, using both public subnets. Its
  only listener is HTTP 80 and forwards to HTTP 80 IP targets using HTTP1.
  ECS owns target registration. Target Optimizer is disabled by leaving the
  target-control port unset.
- The ALB health check uses HTTP, traffic port, `/api/health`, healthy threshold 5,
  unhealthy threshold 2, interval 30 seconds and matcher `200-299`. Other target
  settings retain defaults.
- Allowing 443 in a security group **does not enable HTTPS**. An HTTPS listener,
  certificate and any application TLS configuration are separate work.
  A browser/curl request from a laptop to the ALB DNS name is blocked by the
  CloudFront-only rule. No CloudFront distribution or certificate is created.
- ECS is Fargate only, without Spot or EC2 capacity. The cluster associates only
  `FARGATE`; the service explicitly uses `launch_type = "FARGATE"` and has no
  capacity-provider strategy. Container Insights is disabled. ECS Exec logging
  is configured as `DEFAULT`; this does not enable ECS Exec on the service.
- The service uses REPLICA scheduling, Availability Zone rebalancing ENABLED,
  ECS rolling deployments, 100/200 minimum/maximum healthy percentages and a
  10-second health-check grace period. It depends on the ALB listener.
- Private ECR uses MUTABLE tags and AES256 encryption. Scanning, lifecycle,
  force deletion and other repository options keep provider/AWS defaults.
- EFS is Regional (no single AZ specified), encrypted using the AWS-managed
  `alias/aws/elasticfilesystem` key, General Purpose, and Elastic throughput.
  Automatic backups are explicitly DISABLED. No IA/Archive lifecycle transitions
  are configured. The creation token is stable per client/environment.
- **EFS is not mounted into the task.** No container path was supplied, so there
  are no task volumes, container mount points, access points or invented paths.
  Define that application contract separately before adding an EFS volume.
- Existing RDS access remains EC2-only. This extension does not grant ECS
  database access or supply database credentials/environment variables.

All taggable new resources inherit `cinema = var.cinema_name` and the shared
additional tags, with a resource-specific `Name`. EFS mount targets, EFS backup
policies and ECS capacity-provider associations do not support resource tags.
The existing IAM roles are read-only data sources.

## New inputs

Names default to an empty string, which enables the derived values below.
The table shows derived defaults for `cinema_name = "new-cinema"` and
`environment = "production"`. Names remain configurable for every client.

| Variable | Derived production value / purpose |
| --- | --- |
| `ecr_repository_name` | `new-cinema-web` |
| `ecs_cluster_name` | `new-cinema-web-cluster-prod` |
| `ecs_service_name` | `new-cinema-web-service` |
| `ecs_task_family` | `new-cinema-web-td` |
| `ecs_container_name` | `new-cinema-web` |
| `alb_security_group_name` | `new-cinema-production-alb-sg` |
| `ecs_security_group_name` | `new-cinema-production-ecs-sg` |
| `efs_security_group_name` | `new-cinema-production-efs-sg` |
| `alb_name` | `new-cinema-prod-web-alb` |
| `alb_target_group_name` | `new-cinema-production-web-tg` |
| `efs_name` | `new-cinema-prod` (Name tag) |
| `efs_creation_token` | `new-cinema-production-efs` (stable idempotency token) |
| `ecs_log_group_name` | `/ecs/new-cinema-production/web` |

For other environments, repository, service, task-family and container defaults
include the environment to avoid sharing names across client states. For example,
`new-cinema`/`staging` derives repository `new-cinema-staging-web`. Cluster, ALB,
security-group, EFS and log names also distinguish the environment. Explicit
overrides must remain unique where AWS requires it. Long derived ALB/target-group
names use a deterministic hash suffix to fit AWS's 32-character limit.

| Variable | Default | Meaning |
| --- | --- | --- |
| `ecs_task_role_name` | `ecsTaskExecutionRole` | Existing application/task role |
| `ecs_execution_role_name` | `ecsTaskExecutionRole` | Existing execution role |
| `ecs_image_tag` | `latest` | Image tag appended to the new repository URL |
| `ecs_task_cpu` | `1024` | Task CPU units (1 vCPU) |
| `ecs_task_memory` | `2048` | Task memory in MiB |
| `ecs_container_cpu` | `1024` | Container CPU units, no greater than task CPU |
| `ecs_container_memory` | `2048` | Container hard memory limit in MiB |
| `ecs_container_memory_reservation` | `1024` | Soft reservation, lower than hard limit |
| `ecs_desired_count` | `0` | Keep zero until image and IAM prerequisites pass |
| `ecs_log_retention_days` | `30` | Assumed retention; configurable, 0 means no expiration |
| `ecs_log_stream_prefix` | `web` | Streams follow prefix/container/task-ID |

`web-variables.tf` validates names, retention periods, nonnegative task count and
container limits. The module supports these Linux Fargate task sizes:

| CPU units | Task memory in MiB |
| --- | --- |
| 256 | 512, 1024, 2048 |
| 512 | 1024-4096 in steps of 1024 |
| 1024 | 2048-8192 in steps of 1024 |
| 2048 | 4096-16384 in steps of 1024 |
| 4096 | 8192-30720 in steps of 1024 |
| 8192 | 16384-61440 in steps of 4096 |
| 16384 | 32768-122880 in steps of 8192 |

Larger CPU choices need Linux Fargate platform 1.4.0 or later; this module leaves
platform selection at the service default. This module deliberately supports
sizes only up to 16 vCPU. Adjust container resources together when reducing
task size; the original 1024/2048/1024 container settings cannot fit every size.
See [AWS Fargate task parameters](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_definition_parameters.html).

## Image contract

The image URI is `<new ECR repository URL>:<ecs_image_tag>`. The essential
container is Linux **X86_64**, so the image must support **linux/amd64**.
The original Ubuntu EC2 instance is ARM64; an image built there must explicitly
target amd64 (or include amd64 in a multi-architecture manifest).

The image must contain a shell and `curl`, listen on port 80 on all interfaces,
and serve `/api/health`. Its port mapping is TCP 80, named `web`, with HTTP
application protocol. Container definitions are generated with `jsonencode`.
The exact container health check is:

~~~json
{
  "command": ["CMD-SHELL", "curl -f http://localhost/api/health || exit 1"],
  "interval": 30,
  "timeout": 5,
  "retries": 3,
  "startPeriod": 10
}
~~~

Both the container and ALB checks must succeed after tasks start. The container
check is the exact requested curl command; the ALB separately requires 200-299.
A mutable tag does not automatically redeploy running tasks. For controlled
updates, push a new tag and update `ecs_image_tag` so the task revision changes.

## IAM and account prerequisites

Both role variables default to the existing `ecsTaskExecutionRole` as requested.
No shared role, policy or trust policy is created or changed. The application
therefore inherits the permissions of that role; the separate inputs also allow
an existing dedicated task role to be selected later.

The role administrator must verify:

1. Each selected role trusts service principal `ecs-tasks.amazonaws.com` for
   `sts:AssumeRole`, with any source-account/source-ARN conditions permitting
   this client and account.
2. The execution role permits `ecr:GetAuthorizationToken` on `*` and
   `ecr:BatchCheckLayerAvailability`, `ecr:GetDownloadUrlForLayer` and
   `ecr:BatchGetImage` on the new repository. It also permits
   `logs:CreateLogStream` and `logs:PutLogEvents` on the configured log-group
   streams. `AmazonECSTaskExecutionRolePolicy` normally supplies these actions;
   permissions boundaries/SCPs and explicit denies still apply.
3. The deployment principal can `iam:GetRole` and `iam:PassRole` both selected
   roles, with `iam:PassedToService = ecs-tasks.amazonaws.com` where conditioned.
   It also needs management/tagging permissions for ECR, ECS, ELBv2, EFS, Logs
   and EC2 security groups in addition to the original module's permissions.
   First use of ECS/ELB may require service-linked-role creation permissions.
4. The task role has whatever application permissions the image needs. No
   application-specific permissions are invented here. EFS IAM mount permissions
   are a separate consideration if IAM-authorized mounting is added later.

References: [execution roles](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task_execution_IAM_role.html),
[task roles](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/task-iam-roles.html)
and [PassRole examples](https://docs.aws.amazon.com/AmazonECS/latest/developerguide/security_iam_id-based-policy-examples.html).

These read-only checks use the current client's Region and role names; change
the example values to match the tfvars. They do not modify shared roles:

~~~powershell
$region = 'us-east-1' # Match aws_region in your real client tfvars.
$taskRole = 'ecsTaskExecutionRole'
$executionRole = 'ecsTaskExecutionRole'
aws sts get-caller-identity
foreach ($roleName in (@($taskRole, $executionRole) | Select-Object -Unique)) {
    aws iam get-role --role-name $roleName --query 'Role.{Arn:Arn,Trust:AssumeRolePolicyDocument,Boundary:PermissionsBoundary}' --output json
    aws iam list-attached-role-policies --role-name $roleName --output table
    aws iam list-role-policies --role-name $roleName --output table
}
aws service-quotas get-service-quota --region $region --service-code vpc --quota-code L-0EA8095F --query 'Quota.{Name:QuotaName,Value:Value}' --output table
~~~

Listing policy names alone is not permission verification. Inspect each attached
policy's default version using `aws iam get-policy` followed by
`aws iam get-policy-version`; inspect inline policies with
`aws iam get-role-policy --role-name <role> --policy-name <policy>`.
Have the role/account administrator confirm the actions, resources, conditions,
trust and deployer PassRole permission above before applying.

The ALB SG needs **110** inbound rule capacity (2 x CloudFront weight 55).
The existing EC2 SG still needs **111** with one SSH CIDR. The requirement is
per group: these values are not added together. Request an increase of regional
VPC quota `L-0EA8095F` if needed; the same read-only lookup and a blocking
precondition enforce the ALB requirement. No ports/sources are broadened.
See [AWS prefix-list weights](https://docs.aws.amazon.com/vpc/latest/userguide/working-with-aws-managed-prefix-lists.html).

Both public subnets must be /27 or larger, with at least eight free addresses
each for ALB operation plus room for task ENIs. Terraform validates CIDR size;
confirm available addresses in the account when extending an existing VPC.
See [ALB subnet requirements](https://docs.aws.amazon.com/elasticloadbalancing/latest/application/application-load-balancers.html).
Before scaling tasks, also verify the Region's Fargate On-Demand vCPU quota.
The existing EC2 key pair, RDS version/class checks and VPC quotas still apply.

## Deploying the extension

Use the existing account, Region, client tfvars and workspace. **Do not switch
Region to work around a quota** or copy the example over a real client file.
For an existing client with no new overrides, all new inputs have defaults and
derive its names. Keep `ecs_desired_count = 0`. The sanitized example includes
explicit `new-cinema` names; change those or omit them when using another client.

This extension needs AWS provider **>=6.64.0, <7.0.0** and keeps the previously
selected 6.64.0 version. Terraform remains >=1.9, <2.0. From the Terraform folder,
using the Lanka client's existing credentials:

~~~powershell
terraform init
if ($LASTEXITCODE -ne 0) { throw 'Initialization failed' }
terraform workspace select lanka-cinema-production
if ($LASTEXITCODE -ne 0) { throw 'Select the existing client workspace before continuing' }
terraform workspace show
aws sts get-caller-identity
terraform validate
~~~

For another client, select its existing `<cinema_name>-<environment>` workspace.
The repository's local backend/state isolation is unchanged. Preserve your state
and encrypted backups; do not create a fresh empty workspace for an existing
deployment.

The original RDS password input is still required because this is the same root
configuration. Read it securely and make a new plan:

~~~powershell
$securePassword = Read-Host 'Existing MySQL master password' -AsSecureString
try {
    $env:TF_VAR_db_password = [System.Net.NetworkCredential]::new('', $securePassword).Password
    terraform plan "-var-file=lanka-cinema-prod.tfvars" "-out=lanka-cinema-web.tfplan"
    if ($LASTEXITCODE -ne 0) { throw 'Plan failed; do not apply' }
} finally {
    Remove-Item Env:TF_VAR_db_password -ErrorAction SilentlyContinue
    $securePassword.Dispose()
}
terraform show "lanka-cinema-web.tfplan"
~~~

For an unchanged, fully deployed baseline, expect the web additions and no
unexpected EC2/RDS/network replacement or deletion. Stop and investigate any
such change. The original AMI lookup follows Canonical's latest image, which can
independently propose an EC2 replacement; pin the existing verified AMI if that
upgrade is not intended. RDS minor upgrades or prior out-of-band edits can also
cause unrelated differences. If the baseline was destroyed, a plan will include
its recreation. Changing a file does not authorize destroying existing state.

After reviewing the actual account plan, the operator can run:

~~~powershell
terraform apply "lanka-cinema-web.tfplan"
terraform output
~~~

No apply is run by the implementation or tests. Plan/state files remain sensitive.
Never reuse a saved plan after changing variables or after a partial apply.

## Before starting tasks

1. Verify the existing roles and permissions above.
2. Push a compatible linux/amd64 image to `ecs_image_uri` using a separate
   application build/push workflow. No Docker build/push is part of Terraform.
3. Check the configured tag exists, using the actual repository name and Region:

~~~powershell
aws ecr describe-images --region us-east-1 --repository-name lanka-cinema-web --image-ids imageTag=latest --query 'imageDetails[].{Digest:imageDigest,Tags:imageTags}' --output json
~~~

An image tag being present does not prove architecture, shell/curl availability
or endpoint behavior; verify those as part of the application image build.
Only then explicitly raise `ecs_desired_count` and review/apply a fresh plan.
With zero tasks, a CloudFront request reaching this ALB has no application target
to serve it. ALB DNS access from your laptop remains blocked by the SG even
after healthy tasks exist. Configuring a CloudFront distribution is separate.

EFS mount targets alone do not expose files inside containers. A later change
must specify the application mount path, task volume, mount permissions and any
desired access point. EFS automatic backups are disabled as requested, so plan
data recovery before writing persistent application data.
See [EFS creation/encryption options](https://docs.aws.amazon.com/efs/latest/ug/creating-using-create-fs.html).

## Outputs and teardown

New outputs include ECR URL/ARN/image URI, ECS cluster name/ARN, service name,
task-definition ARN, log-group name, all three SG IDs, ALB DNS/ARN, listener ARN,
target-group ARN, EFS ID/DNS and mount-target IDs keyed by private subnet index.
The original outputs are preserved.

Destroying this workspace includes the original EC2/RDS/network resources as
well as this extension. RDS deletion protection/final-snapshot behavior is
unchanged. ECR retains the default protection against deleting a nonempty
repository; after images are pushed, an intentional teardown requires separately
handling those images. EFS deletion destroys its data and no automatic EFS
backups are configured. Existing shared IAM roles and the EC2 key pair are not
managed or deleted by this extension.

## Validation record

On 2026-09-17, the extension was checked with Terraform 1.12.0 and AWS 6.64.0:
formatting, `init -backend=false -input=false`, validation and **31 passing offline
provider mock tests**. The original EC2, RDS, network, security group, provider and locals
files, plus real Lanka tfvars, were verified unchanged by SHA-256 comparison.

AWS credentials and `TF_VAR_db_password` were unavailable in this tool session,
so no live plan, IAM permission verification or account quota check was run.
Offline tests do not establish AWS availability or prove that an account plan
has no replacements. Those prerequisites remain for the deployer. No apply,
image build/push, shared-role changes or application deployment was performed.
