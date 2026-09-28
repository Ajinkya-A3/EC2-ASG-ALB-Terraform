resource "aws_autoscaling_group" "app" {
  name                = "${var.project}-asg" # changing this forces ASG replacement, avoid renaming
  min_size            = var.asg_min_size
  max_size            = var.asg_max_size
  desired_capacity    = var.asg_desired_capacity
  vpc_zone_identifier = [for s in aws_subnet.private : s.id]

  target_group_arns         = [aws_lb_target_group.app.arn]
  health_check_type         = "ELB"
  health_check_grace_period = 120

  launch_template {
    id      = aws_launch_template.app.id
    version = aws_launch_template.app.latest_version # explicit version so template changes trigger a refresh
  }

  # Launch new instances first, then terminate old ones (no capacity dip)
  instance_refresh {
    strategy = "Rolling"

    preferences {
      min_healthy_percentage = 100
      max_healthy_percentage = 200
      instance_warmup        = 120
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.project}-app"
    propagate_at_launch = true
  }

  # Instances need NAT to install packages at boot
  depends_on = [aws_route.private_nat]

  lifecycle {
    ignore_changes = [desired_capacity] # the scaling policy owns this after creation
  }
}

resource "aws_autoscaling_policy" "cpu" {
  name                      = "${var.project}-cpu-target"
  autoscaling_group_name    = aws_autoscaling_group.app.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 120

  target_tracking_configuration {
    target_value = var.cpu_target

    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
  }
}