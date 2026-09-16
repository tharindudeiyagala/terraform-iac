# terraform-iac

Reusable AWS infrastructure for cinema clients: a two-AZ VPC, Ubuntu ARM64 EC2,
and private Single-AZ RDS MySQL.

See [terraform/README.md](terraform/README.md) for configuration, isolated client
state, required AWS checks, and deployment instructions. Start with the sanitized
[example inputs](terraform/new-cinema-prod.example.tfvars).
