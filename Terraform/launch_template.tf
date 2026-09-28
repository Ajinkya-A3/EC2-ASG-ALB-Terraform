resource "aws_launch_template" "app" {
  name_prefix            = "${var.project}-lt-"
  image_id               = "resolve:ssm:${var.ami_ssm_parameter}" # resolved at launch, no AMI drift in state
  instance_type          = var.instance_type
  update_default_version = true
  vpc_security_group_ids = [aws_security_group.app.id]

  iam_instance_profile {
    name = aws_iam_instance_profile.app.name
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size           = 8
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    app_port = var.app_port
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "${var.project}-app" }
  }

  tag_specifications {
    resource_type = "volume"
    tags          = { Name = "${var.project}-app" }
  }

  lifecycle {
    create_before_destroy = true
  }
}