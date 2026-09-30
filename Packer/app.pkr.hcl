packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1.3"
    }
  }
}

variable "region" {
  type    = string
  default = "ap-south-1"
}

variable "git_sha" {
  type        = string
  description = "Git commit SHA that triggered this build — tagged onto the AMI for traceability"
}

source "amazon-ebs" "app" {
  ami_name      = "ha-web-app-${var.git_sha}"
  instance_type = "t3.micro"
  region        = var.region

  source_ami_filter {
    filters = {
      name                = "al2023-ami-*-x86_64"
      virtualization-type = "hvm"
      root-device-type    = "ebs"
    }
    owners      = ["137112412989"] # Amazon
    most_recent = true
  }

  ssh_username = "ec2-user"

  tags = {
    Name      = "ha-web-app"
    GitSha    = var.git_sha
    ManagedBy = "packer"
  }
}

build {
  sources = ["source.amazon-ebs.app"]

  provisioner "shell" {
    inline = ["mkdir -p /tmp/app"]
  }

  provisioner "file" {
    source      = "../App/"
    destination = "/tmp/app"
  }

  provisioner "file" {
    source      = "../nginx.conf"
    destination = "/tmp/nginx.conf"
  }

  provisioner "file" {
    source      = "render-index.sh"
    destination = "/tmp/render-index.sh"
  }

  provisioner "file" {
    source      = "render-index.service"
    destination = "/tmp/render-index.service"
  }

  provisioner "shell" {
    script = "install.sh"
  }

  post-processor "manifest" {
    output = "manifest.json"
  }
}