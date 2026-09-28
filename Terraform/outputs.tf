output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "app_url" {
  value = "http://${aws_lb.app.dns_name}"
}

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_ids" {
  value = { for az, s in aws_subnet.public : az => s.id }
}

output "private_subnet_ids" {
  value = { for az, s in aws_subnet.private : az => s.id }
}

output "nat_public_ips" {
  description = "Egress IPs. curl ifconfig.me from a private instance should match one of these."
  value       = { for az, e in aws_eip.nat : az => e.public_ip }
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}