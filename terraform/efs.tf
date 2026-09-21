resource "aws_efs_file_system" "web" {
  creation_token   = local.efs_creation_token
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "elastic"
  # No AZ name means Regional. No kms_key_id uses alias/aws/elasticfilesystem.
  # No lifecycle policies: no IA or Archive transitions.
  tags = { Name = local.efs_name }
}

resource "aws_efs_backup_policy" "web" {
  file_system_id = aws_efs_file_system.web.id
  backup_policy {
    status = "DISABLED"
  }
}

resource "aws_efs_mount_target" "web" {
  for_each        = local.private_subnets
  file_system_id  = aws_efs_file_system.web.id
  subnet_id       = aws_subnet.private[each.key].id
  security_groups = [aws_security_group.efs.id]
  # Mount targets and backup policies do not support tags.
}
