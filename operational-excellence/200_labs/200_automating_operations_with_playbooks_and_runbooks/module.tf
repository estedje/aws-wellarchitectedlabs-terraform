
variable "availability_zone" {
  description = "The Availability Zone in which resources are launched."
  type        = string
  default     = "eu-west-1c"
}
resource "tls_private_key" "example_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = tls_private_key.example_ssh.public_key_openssh
}

resource "aws_vpc" "vpc" {
  cidr_block = "172.31.0.0/16"
  tags = {
    Name = "walab-ops-base-resources-VPC"    
  }
}

resource "aws_subnet" "PublicSubnet1" {
  availability_zone       = var.availability_zone
  cidr_block              = "172.31.1.0/24"
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = "true"

}
resource "aws_subnet" "PublicSubnet2" {
  availability_zone       = var.availability_zone
  cidr_block              = "172.31.3.0/24"
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = "true"
}

resource "aws_subnet" "PrivateSubnet1" {
  availability_zone       = var.availability_zone
  cidr_block              = "172.31.2.0/24"
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = "false"
}
resource "aws_subnet" "PrivateSubnet2" {
  availability_zone       = var.availability_zone
  cidr_block              = "172.31.4.0/24"
  vpc_id                  = aws_vpc.vpc.id
  map_public_ip_on_launch = "false"
}

resource "aws_internet_gateway" "IGW" {
}

resource "aws_internet_gateway_attachment" "IGWAttach" {
  internet_gateway_id = aws_internet_gateway.IGW.id
  vpc_id              = aws_vpc.vpc.id
}

resource "aws_eip" "NatPublicIP" {
  vpc              = true
}

resource "aws_nat_gateway" "NatGateway" {
  allocation_id = aws_eip.NatPublicIP.id
  subnet_id     = aws_subnet.PublicSubnet1.id
  depends_on = [aws_eip.NatPublicIP]
}

resource "aws_route_table" "PublicRouteTable1" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "walab-ops-base-resources-Public-RouteTable1"    
  }
}

resource "aws_route_table" "PublicRouteTable2" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "walab-ops-base-resources-Public-RouteTable2"    
  }
}

resource "aws_route" "PublicRoute1" {
  route_table_id         = aws_route_table.PublicRouteTable1.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  depends_on = [aws_internet_gateway_attachment.IGWAttach]
}
resource "aws_route" "PublicRoute2" {
  route_table_id         = aws_route_table.PublicRouteTable2.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.internet_gateway.id
  depends_on = [aws_internet_gateway_attachment.IGWAttach]
}

resource "aws_route_table_association" "PublicSubnet1RouteTableAssociation1" {
  subnet_id      = aws_subnet.PublicSubnet1.id
  route_table_id = aws_route_table.PublicRouteTable1.id
}

resource "aws_route_table_association" "PublicSubnet1RouteTableAssociation2" {
  subnet_id      = aws_subnet.PublicSubnet2.id
  route_table_id = aws_route_table.PublicRouteTable2.id
}

resource "aws_route_table" "PrivateRouteTable1" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route_table" "PrivateRouteTable2" {
  vpc_id = aws_vpc.vpc.id
}

resource "aws_route" "PrivateRoute1" {
  route_table_id         = aws_route_table.PrivateRouteTable1.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id             = aws_internet_gateway.NatGateway.id
  depends_on = [aws_internet_gateway_attachment.IGWAttach]
}

resource "aws_route" "PrivateRoute2" {
  route_table_id         = aws_route_table.PrivateRouteTable2.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id             = aws_internet_gateway.NatGateway.id
  depends_on = [aws_internet_gateway_attachment.IGWAttach]
}

resource "aws_route_table_association" "PrivateSubnet1RouteTableAssociation1" {
  subnet_id      = aws_subnet.PrivateSubnet1.id
  route_table_id = aws_route_table.PrivateRouteTable1.id
}

resource "aws_route_table_association" "PrivateSubnet1RouteTableAssociation2" {
  subnet_id      = aws_subnet.PrivateSubnet2.id
  route_table_id = aws_route_table.PrivateRouteTable2.id
}


resource "aws_ecr_repository" "AppContainerRepository" {
  name                 = "walab-ops-sample-application"
}

resource "aws_cloud9_environment_ec2" "Cloud9" {
  instance_type = "t2.small"
  name          = "WellArchitectedOps-walab-ops-base-resources"
  image_id = amazonlinux-2-x86_64
  automatic_stop_time_minutes = 30
  subnet_id = aws_subnet.PublicSubnet1.id 
  
}
