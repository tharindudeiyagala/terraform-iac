# Reusable cinema infrastructure

This root module creates one cinema environment in one AWS Region. Customize
variables for each client; resource definitions are shared. No resources have
been deployed as part of this implementation.

The root now also provisions ECR, an ECS Fargate web service (initial desired
count **0**), an ALB and Regional EFS. See [WEB-INFRASTRUCTURE.md](WEB-INFRASTRUCTURE.md)
for all new variables, existing IAM role prerequisites, image requirements,
CloudFront quotas, EFS mount limitations and extension deployment steps.

## Files

| File | Purpose |
| --- | --- |
| `versions.tf`, `providers.tf`, `.terraform.lock.hcl` | Version constraints, credential chain, tags, pinned provider |
| `variables.tf`, `locals.tf` | Client inputs, derived names, CIDR and schedule checks |
| `network.tf` | IPv4 VPC, four subnets, routing, optional NAT |
| `security-groups.tf` | EC2/RDS groups, CloudFront lookup and quota check |
| `ec2.tf` | Canonical Ubuntu AMI discovery and public EC2 |
| `rds.tf` | Private MySQL, audit options, optional slow-query parameters, log groups |
| `web-variables.tf`, `web-locals.tf` | Web resource names, sizing, logs and defaults |
| `ecr.tf`, `ecs.tf` | Private image repository, Fargate cluster, task and zero-task service |
| `alb.tf`, `web-security-groups.tf` | HTTP ALB, IP target group and three restricted security groups |
| `efs.tf` | Encrypted Regional EFS, disabled backups and private mount targets |
| `outputs.tf` | Network, instance, security group and database connection outputs |
| `new-cinema-prod.example.tfvars` | Sanitized example without a database password |
| `mysql84-reserved-words.txt` | MySQL 8.4 reserved keywords for input validation |
| `tests/configuration.tftest.hcl` | Offline tests using a mocked AWS provider |

## Topology and assumptions

- VPC: `10.0.0.0/16`, default tenancy, DNS resolution and hostnames enabled.
  No IPv6, VPC encryption control, or VPC endpoints.
- Two standard AZs, each with a public and private subnet. CIDRs must be canonical
  IPv4 networks inside the VPC and pairwise non-overlapping; unequal subnet
  sizes are supported. VPC and subnet prefixes must be /16â€“/28.
- Region was unspecified. The example uses `ap-south-1` (Mumbai), with
  `ap-south-1a` and `ap-south-1b`. Set these for the client. An empty AZ list
  discovers the first two available standard AZs; explicit names provide stable
  selection. AZ letter mappings differ by account.
- NAT was unspecified, so `nat_mode = "none"` is the default. Private subnets
  retain VPC-local connectivity, including EC2-to-RDS access, without a default
  internet route. RDS-managed backups/log exports do not require your NAT.

| NAT mode | Gateways / EIPs | Private internet routes |
| --- | --- | --- |
| `none` | 0 / 0 | None |
| `single` | 1 / 1 in public subnet 0 | Both private subnets use it; adds cross-AZ traffic and an AZ dependency |
| `per_az` | 2 / 2 | Each private subnet uses its own AZ's gateway |

- EC2: Ubuntu Server 24.04 LTS ARM64, `t4g.micro`, public subnet index 0,
  automatically assigned public IPv4, and 50 GiB gp3 root volume. IP/DNS can
  change after stop/start. Other EC2/EBS settings use defaults. No application
  software, instance profile, private key, or CloudFront distribution is created.
- SSH TCP 22 defaults to `0.0.0.0/0` as requested. Set operator CIDRs for actual
  clients. HTTP 80 and HTTPS 443 accept only the AWS-managed CloudFront IPv4
  origin-facing prefix list. It covers CloudFront origins generally and does
  not identify a particular distribution.
- RDS: regular MySQL DB instance, `8.4.11`, `db.t4g.micro`, Single-AZ, IPv4-only,
  private, port 3306 accessible only from the EC2 security group. Both private
  subnets are in the DB subnet group. AWS selects the DB's AZ.
  Both security groups allow outbound IPv4 traffic.
- RDS gp3 starts at 50 GiB and autoscales to 100 GiB. The maximum must be at least
  10% above initial allocation. IOPS and throughput are unset. Encryption is
  enabled; omitting `kms_key_id` selects the regional AWS-managed RDS key,
  `alias/aws/rds`, including when AWS first creates that key. No customer-managed
  key is created. See [RDS CreateDBInstance KMS behavior](https://docs.aws.amazon.com/AmazonRDS/latest/APIReference/API_CreateDBInstance.html).
- Master credentials are self-managed, with username `root` by default.
  IAM database authentication and Enhanced Monitoring are disabled.
- Backups are retained for 30 days. Backup `06:00-06:30` and maintenance
  `mon:07:00-mon:07:30` are UTC. **The 30-minute durations are assumptions**
  because only starting hours were supplied. Both windows are configurable and
  checked for minimum duration and overlap, including midnight/week boundaries.
  Tags copy to snapshots; automatic minor upgrades are enabled.
- Every Terraform-created resource that supports tagging receives `cinema`,
  `Environment`, and an appropriate `Name`. Additional tags are supported.
  AWS-created default VPC resources are not managed here. Routes and route-table
  associations do not support tags.

## Client inputs and names

Required inputs without defaults: `cinema_name`, `key_pair_name`, `db_name`,
and sensitive `db_password`. The key pair must already exist in the Region;
keep its private key outside the repository.

Names derive from `<cinema_name>-<environment>` (`production` by default).
`vpc_name`, `ec2_name`, `ec2_security_group_name`, `rds_security_group_name` and
`db_identifier` override primary names; empty strings retain derivation.
The example uses `new-cinema-prod-vpc` and `new-cinema-production` as requested.

Use `aws_region`, `availability_zones`, `vpc_cidr`, `public_subnet_cidrs`,
`private_subnet_cidrs` and `nat_mode` for networking. Subnet positions match AZ
positions. `ec2_public_subnet_index` chooses 0 or 1. Use `instance_type`,
`root_volume_size`, `root_volume_type` and `ssh_allowed_cidrs` for EC2.

The Canonical SSM parameter is
`/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id`.
Its value is checked using EC2 image metadata; both AMI and instance type must
support ARM64. An explicit `ami_id` bypasses SSM; the operator must verify the
override is a trusted Ubuntu Server 24.04 image. Following `current` may produce
a replacement when Canonical publishes a new image; pin a verified AMI for
controlled upgrades. See [Canonical AMI discovery](https://documentation.ubuntu.com/aws/aws-how-to/instances/find-ubuntu-images/).

Database variables cover exact 8.4 patch version, class, username, initial name,
storage, parameter group, optional slow-query logging, backup retention,
schedules and deletion behavior. MySQL names allow 1â€“64 ASCII letters, digits or
underscores, starting with a letter; reserved words and existing system schemas
are rejected. The checked-in table reflects [MySQL 8.4 keywords](https://dev.mysql.com/doc/refman/8.4/en/keywords.html);
`MANUAL` is additionally rejected for versions before 8.4.11. Review it when
updating the engine series. See [RDS database-name constraints](https://docs.aws.amazon.com/AmazonRDS/latest/APIReference/API_CreateDBInstance.html).

`name_overrides` accepts these supporting name keys:
`internet_gateway`, `public_route_table`, `public_subnet_0`, `public_subnet_1`,
`private_subnet_0`, `private_subnet_1`, `private_route_table_0`,
`private_route_table_1`, `nat_gateway_0`, `nat_gateway_1`, `nat_eip_0`,
`nat_eip_1`, `db_subnet_group`, `db_option_group` and `db_parameter_group`.
For DB group names use lowercase letters, digits and single hyphens, beginning
with a letter and with no trailing hyphen. Changing immutable names can replace
resources; review the plan. Mandatory tags take precedence over additional tags.

## Logging: exports versus records

All four requested exports are selected. Terraform creates their tagged groups
at `/aws/rds/instance/<identifier>/<log-type>` before RDS publishes.
Retention is unspecified, so CloudWatch uses no expiration; storage is billable.

| Export | Actual generation |
| --- | --- |
| `audit` | Enabled by the MySQL 8.4 option group containing `MARIADB_AUDIT_PLUGIN`; records connections and queries (`CONNECT,QUERY`). |
| `error` | MySQL enables its error log by default; records depend on database activity/errors. |
| `slowquery` | Export selected but disabled under the default parameter group. Set `enable_slow_query_logging = true` to attach a custom `mysql8.4` group with `slow_query_log = 1` and `log_output = FILE`. Only qualifying slow queries produce records. |
| `iam-db-auth-error` | Export selected, but IAM authentication stays disabled. No IAM authentication error records are expected under password-only operation. |

The default remains `default.mysql8.4`. An existing custom group can be passed
with `db_parameter_group_name` when the optional managed group is disabled.
Enabling the optional group takes precedence over that input. Existing DBs may
need a reboot when changing parameter-group associations; inspect pending-reboot
status and schedule it explicitly. AWS warns audit option changes can cause an
outage. Audit queries may contain application data; control log access.
Empty log groups do not prove a logging failure.

These behaviors follow [AWS MySQL log-export requirements](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_LogAccess.MySQLDB.PublishtoCloudWatchLogs.html)
and [MySQL audit-plugin support and settings](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Appendix.MySQL.Options.AuditPlugin.html).
Regional option/version compatibility still requires the checks below.

## Read-only AWS prerequisites

Use Terraform >=1.9, <2.0 and AWS provider >=6.64.0, <7.0. Commit
`.terraform.lock.hcl` (currently AWS 6.64.0). Install AWS CLI, preferably v2.
Authenticate using the standard credential chain, `AWS_PROFILE`, SSO, or an IAM
role; never put access keys in Terraform. For example, set
`$env:AWS_PROFILE = 'cinema-deployer'` in PowerShell and use your organization's
normal login workflow.

The deployer needs EC2/VPC, RDS and CloudWatch Logs management permissions,
plus the ECR/ECS/ELB/EFS and existing-role permissions described in
[the extension prerequisites](WEB-INFRASTRUCTURE.md#iam-and-account-prerequisites),
Canonical SSM read access, and `servicequotas:GetServiceQuota`. RDS may require
creation of its service-linked role on first use. Terraform also reads AZs,
images, key pairs, instance types and RDS offerings. No IAM policies are created.

Run these **read-only** PowerShell commands with values matching the client
tfvars. Commands work with CLI v1/v2; stop on a failure or empty result.

~~~powershell
$env:AWS_PAGER = ''
$region = 'ap-south-1'
$engineVersion = '8.4.11'
$dbClass = 'db.t4g.micro'
$keyPair = 'replace-with-existing-key-pair'

aws sts get-caller-identity
aws ec2 describe-availability-zones --region $region --filters Name=state,Values=available Name=zone-type,Values=availability-zone --query 'AvailabilityZones[].ZoneName' --output table

aws rds describe-db-engine-versions --region $region --engine mysql --engine-version $engineVersion --query 'DBEngineVersions[].{Version:EngineVersion,Status:Status,Family:DBParameterGroupFamily,LogExport:SupportsLogExportsToCloudwatchLogs,Logs:ExportableLogTypes}' --output json

aws rds describe-orderable-db-instance-options --region $region --engine mysql --engine-version $engineVersion --db-instance-class $dbClass --vpc --query "OrderableDBInstanceOptions[?StorageType=='gp3'].{Version:EngineVersion,Class:DBInstanceClass,AZs:AvailabilityZones[].Name,Network:SupportedNetworkTypes,Encrypted:SupportsStorageEncryption,Autoscaling:SupportsStorageAutoscaling,MinGiB:MinStorageSize,MaxGiB:MaxStorageSize,License:LicenseModel}" --output json

aws rds describe-option-group-options --region $region --engine-name mysql --major-engine-version 8.4 --query "OptionGroupOptions[?Name=='MARIADB_AUDIT_PLUGIN'].{Name:Name,MinimumMinor:MinimumRequiredMinorEngineVersion,Versions:OptionGroupOptionVersions,Settings:OptionGroupOptionSettings}" --output json

aws rds describe-db-parameter-groups --region $region --db-parameter-group-name default.mysql8.4 --query 'DBParameterGroups[].{Name:DBParameterGroupName,Family:DBParameterGroupFamily}' --output table
aws rds describe-engine-default-parameters --region $region --db-parameter-group-family mysql8.4 --query "EngineDefaults.Parameters[?ParameterName=='slow_query_log' || ParameterName=='log_output'].{Name:ParameterName,Value:ParameterValue,Modifiable:IsModifiable,ApplyType:ApplyType,Allowed:AllowedValues}" --output table

aws ec2 describe-managed-prefix-lists --region $region --filters Name=prefix-list-name,Values=com.amazonaws.global.cloudfront.origin-facing Name=owner-id,Values=AWS --query 'PrefixLists[].{ID:PrefixListId,Name:PrefixListName,Family:AddressFamily}' --output table
aws service-quotas get-service-quota --region $region --service-code vpc --quota-code L-0EA8095F --query 'Quota.{Name:QuotaName,Value:Value,Adjustable:Adjustable}' --output table

$ami = aws ssm get-parameter --region $region --name /aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id --query Parameter.Value --output text
if ($LASTEXITCODE -ne 0) { throw 'Canonical AMI lookup failed' }
aws ec2 describe-images --region $region --image-ids $ami --query 'Images[].{ID:ImageId,Owner:OwnerId,Name:Name,Architecture:Architecture,State:State,Root:RootDeviceType}' --output table
aws ec2 describe-instance-types --region $region --instance-types t4g.micro --query 'InstanceTypes[].ProcessorInfo.SupportedArchitectures' --output json
aws ec2 describe-instance-type-offerings --region $region --location-type availability-zone --filters Name=instance-type,Values=t4g.micro --query 'InstanceTypeOfferings[].Location' --output table
aws ec2 describe-key-pairs --region $region --key-names $keyPair --query 'KeyPairs[].KeyName' --output text
~~~

Require an **available exact `8.4.11`** result with family `mysql8.4` and all four
exports. Require a gp3 `db.t4g.micro` offering in both chosen AZs, IPv4,
encryption/autoscaling support, with 50/100 GiB inside the storage bounds.
Require the audit option and ensure its minimum minor version permits the exact
engine version; check `CONNECT,QUERY` is an allowed setting.
If any combination is absent, stop and choose a Region or explicitly revise
inputs with the client. No version, class, export or source is silently
substituted. Terraform's RDS data sources also check exact version/class
offerings and exports during a real plan. Audit option availability/minimum
version is a separate required CLI check.

CloudFront's documented weight is **55 per prefix-list reference**. Two ports
plus one SSH CIDR need **111 inbound rules per security group**, or
`110 + number of distinct SSH CIDRs`. The typical default of 60 is insufficient.
Request a regional increase for VPC quota `L-0EA8095F` through Service Quotas
and wait until effective. Terraform blocks on insufficient quota; it does not
request increases automatically or broaden access to bypass the limit.
See [AWS-managed prefix-list weights](https://docs.aws.amazon.com/vpc/latest/userguide/working-with-aws-managed-prefix-lists.html).

## Separate state for every client

This root uses the local backend by default. **Each client/environment must use
a workspace named exactly `<cinema_name>-<environment>`.** A precondition rejects
mismatched workspaces, including `default`. Switching only tfvars is unsafe
and is blocked by that check.

~~~powershell
Set-Location terraform
Copy-Item new-cinema-prod.example.tfvars new-cinema-prod.tfvars
# Edit the copy: Region/AZs, existing key pair, client names and operator CIDRs.
terraform init
terraform workspace new new-cinema-production
# For an existing workspace instead:
# terraform workspace select new-cinema-production
terraform workspace show
~~~

The local state path is
`terraform.tfstate.d/new-cinema-production/terraform.tfstate` under this directory.
For another client, create a new ignored tfvars file with distinct
`cinema_name`/environment/names, then create/select its corresponding workspace.
Do not reuse names that must be unique in the same account/Region. Renaming
the cinema identifier of a deployed environment requires deliberate state
migration; do not simply start with empty state.

Keep local state backed up with restricted access. For team/production use,
move the workspaces to an existing encrypted, versioned remote backend with
locking and least-privilege access. For S3, preserve these workspace names;
`workspace_key_prefix` and base `key` determine each non-default workspace's
separate object (`<prefix>/<workspace>/<key>`). Initialize/migrate deliberately
and verify state contents before planning. No backend bucket is provisioned.
Workspaces separate state, not AWS permissions/accounts; verify the identity
and Region as well.

## Password input, validation, plan and deployment

The required sensitive password has no default and is absent from the example.
In PowerShell, read it without echoing or placing it in shell history:

~~~powershell
$securePassword = Read-Host 'RDS master password' -AsSecureString
$passwordPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try {
    $env:TF_VAR_db_password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($passwordPointer)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($passwordPointer)
    $securePassword.Dispose()
    Remove-Variable securePassword, passwordPointer
}

try {
    terraform fmt -check -recursive
    if ($LASTEXITCODE -ne 0) { throw 'Formatting failed' }
    terraform validate
    if ($LASTEXITCODE -ne 0) { throw 'Validation failed' }
    terraform plan -var-file=new-cinema-prod.tfvars -out=new-cinema-prod.tfplan
    if ($LASTEXITCODE -ne 0) { throw 'Plan failed' }
} finally {
    Remove-Item Env:TF_VAR_db_password -ErrorAction SilentlyContinue
}
~~~

On Bash, use `read -r -s -p 'RDS master password: ' TF_VAR_db_password`, export
the variable for planning, then `unset TF_VAR_db_password`. Avoid command-line
`-var` passwords and plaintext credential files.

**Sensitive means display redaction, not encrypted state.** This module uses
ordinary `password`, so state and saved plans can contain the password in
plaintext. The environment temporarily contains it too. Protect state, plans
and logs; use encrypted remote storage and restricted access. Write-only
password functionality would need a separate configuration using ephemeral
input and a password version counter; it is not enabled here.

After prerequisites pass, review the saved plan and confirm the account,
workspace, Region, counts and replacement actions. The operator can then deploy:

~~~powershell
terraform show new-cinema-prod.tfplan
terraform workspace show
terraform apply new-cinema-prod.tfplan
terraform output
~~~

These are documentation commands; **no apply was run during implementation**.
Saved plans contain their inputs; never reuse them across clients or after
changing settings. Outputs include VPC/subnet IDs, EC2 ID/public IP/DNS,
security group IDs, private RDS endpoint/port and initial database name.
There is no password output.

## Deletion, updates and snapshots

`deletion_protection = true` and `skip_final_snapshot = false` are the defaults.
For intentional teardown, first change deletion protection to false and apply
that change; then separately plan/review destruction. A final snapshot defaults
to `<db_identifier>-final`. Set `final_snapshot_identifier` to an unused name for
repeated lifecycles; RDS rejects snapshot-name collisions. Skipping the final
snapshot is explicit and loses that recovery point. Final snapshots remain
outside Terraform management and incur storage charges. Managed CloudWatch
groups are removed on destroy; export logs that must survive.

Storage autoscaling cannot shrink storage. Automatic minor upgrades can advance
the running engine beyond the configured patch; update `db_engine_version`
deliberately after reviewing upgrade status and subsequent plans. Do not attempt
an RDS downgrade. Other modification settings retain provider defaults;
some database updates wait for the maintenance window.

## Verification performed

On 2026-09-16, Terraform 1.12.0 and AWS provider 6.64.0 were used:

- `terraform fmt -recursive` and a final formatting check.
- `terraform init -backend=false -input=false`; downloaded the signed provider
  and generated its lock file without accessing a production backend.
- `terraform validate`.
- 18 mocked-provider tests covering NAT modes, subnets, workspace mismatch,
  naming, quotas, missing exports, logging, schedules, storage and ARM64.

To rerun tests from this directory without AWS credentials:

~~~powershell
terraform init -backend=false -input=false
$previousWorkspace = $env:TF_WORKSPACE
try {
    $env:TF_WORKSPACE = 'new-cinema-production'
    terraform test
} finally {
    if ($null -eq $previousWorkspace) {
        Remove-Item Env:TF_WORKSPACE -ErrorAction SilentlyContinue
    } else {
        $env:TF_WORKSPACE = $previousWorkspace
    }
}
~~~

Tests use synthetic inputs and mock all AWS calls; they neither deploy nor
establish regional availability. The local CLI reported `Unable to locate
credentials`. **No live plan, regional quota check or account-specific RDS
option/version/class verification was possible.** Complete the read-only checks
and supply real client inputs before deployment. The example key-pair name is
a placeholder.
