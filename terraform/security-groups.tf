data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_servicequotas_service_quota" "sg_rules" {
  service_code = "vpc"
  quota_code   = "L-0EA8095F"
}

resource "aws_security_group" "ec2" {
  name        = local.ec2_security_group_name
  description = "SSH and CloudFront IPv4 origin HTTP/HTTPS"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = local.ec2_security_group_name }

  lifecycle {
    precondition {
      condition     = data.aws_servicequotas_service_quota.sg_rules.value >= local.required_ingress_quota
      error_message = "The VPC inbound rules-per-SG quota must be at least ${local.required_ingress_quota}: two CloudFront references at weight 55 plus one rule per SSH CIDR. Request a regional increase for L-0EA8095F."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each          = var.ssh_allowed_cidrs
  security_group_id = aws_security_group.ec2.id
  description       = "SSH from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  tags              = { Name = "${local.ec2_name}-ssh-${replace(each.value, "/", "-")}" }
}

resource "aws_vpc_security_group_ingress_rule" "cloudfront" {
  for_each          = { http = 80, https = 443 }
  security_group_id = aws_security_group.ec2.id
  description       = "CloudFront IPv4 origin ${each.key}"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  from_port         = each.value
  to_port           = each.value
  ip_protocol       = "tcp"
  tags              = { Name = "${local.ec2_name}-cloudfront-${each.key}" }
}

resource "aws_vpc_security_group_egress_rule" "ec2" {
  security_group_id = aws_security_group.ec2.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  tags              = { Name = "${local.ec2_name}-egress" }
}

resource "aws_security_group" "rds" {
  name        = local.rds_security_group_name
  description = "MySQL from the cinema EC2 security group"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = local.rds_security_group_name }
}

resource "aws_vpc_security_group_ingress_rule" "mysql" {
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.ec2.id
  description                  = "MySQL from cinema EC2"
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
  tags                         = { Name = "${local.db_identifier}-mysql" }
}

resource "aws_vpc_security_group_egress_rule" "rds" {
  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  tags              = { Name = "${local.db_identifier}-egress" }
}
