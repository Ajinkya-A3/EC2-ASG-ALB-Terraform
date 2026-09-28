locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # AZ name -> index. Subnets are keyed by AZ name (for_each), so adding an AZ
  # never touches existing subnets.
  az_index = { for i, az in local.azs : az => i }

  # Private subnets use index + offset so they never collide with public CIDRs
  private_offset = 100

  nat_azs = var.single_nat_gateway ? [local.azs[0]] : local.azs
}