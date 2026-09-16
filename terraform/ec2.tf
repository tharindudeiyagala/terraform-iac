data "aws_ssm_parameter" "ubuntu" {
  count           = var.ami_id == "" ? 1 : 0
  name            = "/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id"
  with_decryption = false
}

data "aws_ami" "selected" {
  filter {
    name   = "image-id"
    values = [var.ami_id != "" ? var.ami_id : nonsensitive(data.aws_ssm_parameter.ubuntu[0].value)]
  }
}

data "aws_ec2_instance_type" "selected" {
  instance_type = var.instance_type
}

data "aws_key_pair" "existing" {
  key_name = var.key_pair_name
}

resource "aws_instance" "this" {
  ami                         = data.aws_ami.selected.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public[tostring(var.ec2_public_subnet_index)].id
  associate_public_ip_address = true
  key_name                    = data.aws_key_pair.existing.key_name
  vpc_security_group_ids      = [aws_security_group.ec2.id]

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = var.root_volume_type
    tags        = merge(local.common_tags, { Name = "${local.ec2_name}-root" })
  }

  tags = { Name = local.ec2_name }

  lifecycle {
    precondition {
      condition     = data.aws_ami.selected.architecture == "arm64" && contains(data.aws_ec2_instance_type.selected.supported_architectures, "arm64")
      error_message = "The AMI and EC2 instance type must both support ARM64. An explicit AMI must also be Ubuntu Server 24.04 LTS."
    }
  }
}
