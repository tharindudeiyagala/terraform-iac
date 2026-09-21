resource "aws_lb_target_group" "web" {
  name             = local.alb_target_group_name
  target_type      = "ip"
  protocol         = "HTTP"
  port             = 80
  ip_address_type  = "ipv4"
  vpc_id           = aws_vpc.this.id
  protocol_version = "HTTP1"

  health_check {
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = "/api/health"
    healthy_threshold   = 5
    unhealthy_threshold = 2
    interval            = 30
    matcher             = "200-299"
  }

  # Target Optimizer stays disabled: no target_control_port.
  # ECS registers task IPs; there are no static target attachments.
  tags = { Name = local.alb_target_group_name }
}

resource "aws_lb" "web" {
  name               = local.alb_name
  internal           = false
  load_balancer_type = "application"
  ip_address_type    = "ipv4"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for k in ["0", "1"] : aws_subnet.public[k].id]
  tags               = { Name = local.alb_name }

  depends_on = [aws_internet_gateway.this, aws_route.public_internet, aws_route_table_association.public]

  lifecycle {
    precondition {
      condition     = !startswith(lower(local.alb_name), "internal-")
      error_message = "AWS reserves the internal- ALB name prefix. Set alb_name to another name for this client."
    }
    precondition {
      condition     = alltrue([for cidr in var.public_subnet_cidrs : try(tonumber(split("/", cidr)[1]) <= 27, false)])
      error_message = "An ALB requires public subnets of /27 or larger, with at least eight free IP addresses per subnet."
    }
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }

  tags = { Name = "${local.alb_name}-http" }
}
