# ---------- General ----------
variable "project" {
  description = "Name prefix for all resources"
  type        = string
  default     = "ha-web"

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.project))
    error_message = "project must be 3-20 chars: lowercase letters, digits, hyphens (ALB name limit is 32)."
  }
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}

# ---------- Network ----------
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of AZs (and therefore public + private subnet pairs) to use"
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 6
    error_message = "az_count must be between 2 and 6."
  }
}

variable "subnet_newbits" {
  description = "Extra bits added to vpc_cidr per subnet (16 + 8 = /24 subnets)"
  type        = number
  default     = 8
}

variable "single_nat_gateway" {
  description = "true = one shared NAT (cheap, dev). false = one NAT per AZ (real HA)"
  type        = bool
  default     = true
}

# ---------- App / compute ----------
variable "app_port" {
  description = "Port the app listens on (ALB -> instance)"
  type        = number
  default     = 80
}

variable "health_check_path" {
  description = "ALB target group health check path"
  type        = string
  default     = "/health"
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "ami_ssm_parameter" {
  description = "SSM public parameter resolved at instance launch (always latest AL2023)"
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "asg_min_size" {
  type    = number
  default = 2
}

variable "asg_desired_capacity" {
  description = "Initial desired capacity only. Ignored after creation (scaling policy owns it)."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  type    = number
  default = 6
}

variable "cpu_target" {
  description = "Target average CPU % for target tracking scaling"
  type        = number
  default     = 50
}


variable "enable_deletion_protection" {
  type    = bool
  default = false
}