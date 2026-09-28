resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.project}-vpc" }

  lifecycle {
    precondition {
      condition     = var.az_count <= length(data.aws_availability_zones.available.names)
      error_message = "az_count is higher than the number of AZs available in this region."
    }
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

# ---------- Subnets ----------
resource "aws_subnet" "public" {
  for_each = local.az_index

  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.vpc_cidr, var.subnet_newbits, each.value)
  map_public_ip_on_launch = false

  tags = { Name = "${var.project}-public-${each.key}", Tier = "public" }
}

resource "aws_subnet" "private" {
  for_each = local.az_index

  vpc_id            = aws_vpc.main.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.vpc_cidr, var.subnet_newbits, each.value + local.private_offset)

  tags = { Name = "${var.project}-private-${each.key}", Tier = "private" }
}

# ---------- Public routing ----------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-public-rt" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# ---------- NAT ----------
resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain     = "vpc"
  tags       = { Name = "${var.project}-nat-eip-${each.key}" }
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = { Name = "${var.project}-nat-${each.key}" }
  depends_on    = [aws_internet_gateway.main]
}

# ---------- Private routing (one route table per AZ) ----------
resource "aws_route_table" "private" {
  for_each = local.az_index

  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-private-rt-${each.key}" }
}

resource "aws_route" "private_nat" {
  for_each = local.az_index

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main[var.single_nat_gateway ? local.azs[0] : each.key].id
}

resource "aws_route_table_association" "private" {
  for_each = aws_subnet.private

  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}