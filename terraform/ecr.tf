resource "aws_ecr_repository" "web" {
  name                 = local.ecr_repository_name
  image_tag_mutability = "MUTABLE"

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = { Name = local.ecr_repository_name }
}
