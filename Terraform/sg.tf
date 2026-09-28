# ---------- ALB SG ----------
resource "aws_security_group" "alb" {
  name_prefix = "${var.project}-alb-"
  description = "ALB: HTTP from the internet"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project}-alb-sg" }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [ingress, egress]
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "ALB to app instances"
  referenced_security_group_id = aws_security_group.app.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

# ---------- App SG ----------
resource "aws_security_group" "app" {
  name_prefix = "${var.project}-app-"
  description = "App instances: traffic only from the ALB"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${var.project}-app-sg" }

  lifecycle {
    create_before_destroy = true
    ignore_changes = [ingress, egress]
  }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "App port from ALB only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.app_port
  to_port                      = var.app_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "app_all_out" {
  security_group_id = aws_security_group.app.id
  description       = "All outbound (goes via NAT)"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}