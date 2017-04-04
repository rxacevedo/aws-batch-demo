data "aws_availability_zones" "available" {
  # Doesn't fucking work
  state = "available"
}

output "availability_zones" {
  value = "${data.aws_availability_zones.available.names}"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.10.0.0/16"
  instance_tenancy     = "default"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags {
    Name = "main"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = "${aws_vpc.main.id}"

  tags {
    Name = "main"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = "${aws_vpc.main.id}"
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "${data.aws_availability_zones.available.names[1]}"
  map_public_ip_on_launch = true

  tags {
    Name = "main"
  }
}

resource "aws_route_table" "rt_1" {
  vpc_id = "${aws_vpc.main.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.main.id}"
  }

  tags {
    Name = "main"
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = "${aws_subnet.main.id}"
  route_table_id = "${aws_route_table.rt_1.id}"
}

resource "aws_vpc_endpoint" "private-s3" {
  vpc_id          = "${aws_vpc.main.id}"
  service_name    = "com.amazonaws.us-east-1.s3"
  route_table_ids = ["${aws_route_table.rt_1.id}"]
}
