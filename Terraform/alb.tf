resource "aws_lb" "app" {
  name                       = "${var.project}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = [for s in aws_subnet.public : s.id]
  drop_invalid_header_fields = true
  enable_deletion_protection = var.enable_deletion_protection

  tags = { Name = "${var.project}-alb" }
}

resource "aws_lb_target_group" "app" {
  name_prefix          = "app-"
  port                 = var.app_port
  protocol             = "HTTP"
  vpc_id               = aws_vpc.main.id
  target_type          = "instance"
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  lifecycle {
    create_before_destroy = true
  }
}

# HTTP only for now. Add an aws_lb_listener "https" + var.certificate_arn later
# and switch this default_action to a redirect when HTTPS is ready.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}