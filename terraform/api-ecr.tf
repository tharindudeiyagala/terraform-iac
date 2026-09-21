resource "aws_ecr_repository" "api" {
  name                 = local.api_ecr_repository_name
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = local.api_ecr_repository_name }
}
