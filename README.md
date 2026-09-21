# terraform-iac

Reusable AWS infrastructure for cinema clients: a two-AZ VPC, Ubuntu ARM64 EC2,
private Single-AZ RDS MySQL, and an ECS Fargate web stack with ECR, ALB and EFS.

See [terraform/README.md](terraform/README.md) for configuration, isolated client
state, required AWS checks, and deployment instructions. Start with the sanitized
[example inputs](terraform/new-cinema-prod.example.tfvars).

The [web infrastructure guide](terraform/WEB-INFRASTRUCTURE.md) covers the new
inputs and prerequisites. ECS starts at zero tasks; EFS is provisioned without
an application mount. Existing shared IAM roles are reused without modification.
