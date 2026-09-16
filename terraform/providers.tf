provider "aws" {
  region = var.aws_region

  # Use the standard AWS credential chain, AWS_PROFILE, or an assumed IAM role.
  default_tags {
    tags = local.common_tags
  }
}
