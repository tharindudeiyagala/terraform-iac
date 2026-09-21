resource "aws_security_group" "alb" {
  name        = local.alb_security_group_name
  description = "HTTP and HTTPS from CloudFront IPv4 origins"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = local.alb_security_group_name }

  lifecycle {
    precondition {
      condition     = data.aws_servicequotas_service_quota.sg_rules.value >= local.alb_required_ingress_quota
      error_message = "The ALB needs at least ${local.alb_required_ingress_quota} inbound rules per SG: two CloudFront references at weight 55. Increase regional VPC quota L-0EA8095F before deployment."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_cloudfront" {
  for_each          = { http = 80, https = 443 }
  security_group_id = aws_security_group.alb.id
  description       = "CloudFront IPv4 origin ${each.key}"
  prefix_list_id    = data.aws_ec2_managed_prefix_list.cloudfront.id
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  tags              = { Name = "${local.alb_name}-cloudfront-${each.key}" }
}

resource "aws_vpc_security_group_egress_rule" "alb" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  tags              = { Name = "${local.alb_name}-egress" }
}

resource "aws_security_group" "ecs" {
  name        = local.ecs_security_group_name
  description = "Web traffic from the cinema ALB"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = local.ecs_security_group_name }
}

resource "aws_vpc_security_group_ingress_rule" "ecs_alb" {
  for_each                     = { http = 80, https = 443 }
  security_group_id            = aws_security_group.ecs.id
  referenced_security_group_id = aws_security_group.alb.id
  description                  = "ALB ${each.key} to ECS"
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  tags                         = { Name = "${local.ecs_service_name}-alb-${each.key}" }
}

resource "aws_vpc_security_group_egress_rule" "ecs" {
  security_group_id = aws_security_group.ecs.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  tags              = { Name = "${local.ecs_service_name}-egress" }
}

resource "aws_security_group" "efs" {
  name        = local.efs_security_group_name
  description = "NFS only from the cinema ECS security group"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = local.efs_security_group_name }
}

resource "aws_vpc_security_group_ingress_rule" "efs_ecs" {
  security_group_id            = aws_security_group.efs.id
  referenced_security_group_id = aws_security_group.ecs.id
  description                  = "NFS from ECS (one source rule)"
  ip_protocol                  = "tcp"
  from_port                    = 2049
  to_port                      = 2049
  tags                         = { Name = "${local.efs_name}-ecs-nfs" }
}

resource "aws_vpc_security_group_egress_rule" "efs" {
  security_group_id = aws_security_group.efs.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  tags              = { Name = "${local.efs_name}-egress" }
}
