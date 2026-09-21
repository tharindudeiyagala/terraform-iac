# terraform-iac

Reusable AWS infrastructure for cinema clients: a two-AZ VPC, Ubuntu ARM64 EC2,
private Single-AZ RDS MySQL, separate ECS Fargate web and API stacks with ECR
and ALBs, and Regional EFS for the web stack.

See [terraform/README.md](terraform/README.md) for configuration, isolated client
state, required AWS checks, and deployment instructions. Start with the sanitized
[example inputs](terraform/new-cinema-prod.example.tfvars).

The [web infrastructure guide](terraform/WEB-INFRASTRUCTURE.md) covers the new
inputs and prerequisites. ECS starts at zero tasks; EFS is provisioned without
an application mount. Existing shared IAM roles are reused without modification.

The [API infrastructure guide](terraform/API-INFRASTRUCTURE.md) covers the
separate API cluster, `/health.php` health checks, API inputs, and short deployment
steps. Both services start at zero tasks and share the existing VPC and public subnets.
