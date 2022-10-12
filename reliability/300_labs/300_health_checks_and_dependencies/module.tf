variable "naming_prefix" {
  description = "The naming prefix for resources created by this template, and exported values that can be referenced by other stacks."
  type = string
  default = "WebApp1"
}

variable "vpc_ipv4_cidr_block" {
  description = "VPC CIDR block for IPv4. Default of 10.0.0.0/16 is recommended for testing."
  type = string
  default = "10.0.0.0/16"
}

variable "vpc_subnet_i_pv4_size" {
  description = "Host bit mask length of each subnet, e.g. default of 8 will be a /24 subnet size."
  type = number
  default = 8
}

variable "vpc_number_of_i_pv4_subnets" {
  description = "Number of equally sized IPv4 subnets that will be created within the VPC CIDR block. Default of 256 is recommended for testing."
  type = number
  default = 256
}

variable "vpc_subnet_i_pv6_size" {
  description = "Host bit mask length of each subnet, e.g. default of 64 will be a /64 subnet size."
  type = number
  default = 64
}

variable "vpc_number_of_i_pv6_subnets" {
  description = "Number of equally sized IPv6 subnets that will be created within the VPC CIDR block."
  type = number
  default = 256
}

variable "vpc_flow_log_retention" {
  description = "VPC Flow Log retention time in days. Note that VPC Flow Logs will be deleted when this stack is deleted."
  type = number
  default = 90
}

variable "alb1_subnets_enabled" {
  description = "Create subnets and other resources for application load balancer (ALB) tier. False disables the ALB tier completely."
  type = bool
  default = true
}

variable "app1_subnets_internet_route" {
  description = "Application subnets route to the internet through Nat Gateways (IPv4) or egress only internet gateway (IPv6). If set to true then shared tier also must be enabled."
  type = bool
  default = true
}

variable "app1_subnets_private_link_endpoints" {
  description = "VPC Endpoints can be used to access example common AWS services privately within a subnet, instead of via a NAT Gateway. Note for testing purposes a NAT Gateway is more cost effective than enabling endpoint services."
  type = bool
  default = false
}

variable "db1_subnets_enabled" {
  description = "Create subnets and other resources for database (DB) tier. False disables the DB tier completely."
  type = bool
  default = true
}

variable "db1_tcp_port_number" {
  description = "TCP/IP port number used in DB tier for Network ACL (NACL). Default is 3306 for MySQL. Examples; 5432 for PostgreSQL, 1433 for SQL Server, , 11211 for Memcache/Elasticache, 6379 for Redis."
  type = number
  default = 3306
}

variable "shared1_subnets_enabled" {
  description = "Create subnets for shared tier. Set to true when enabling application route to internet parameter as the shared tier contains NAT gateways that allow IPv4 traffic in the application tier to connect to the internet. False disables the shared tier completely."
  type = bool
  default = true
}


data "aws_region" "current" {
}

data "aws_caller_identity" "current" {
}

data "aws_partition" "current" {
}


resource "aws_vpc" "vpc" {
  cidr_block = var.vpc_ipv4_cidr_block
  enable_dns_support = true
  enable_dns_hostnames = true
  instance_tenancy = "default"
  tags = {
    Name = "${var.naming_prefix}-VPC"
  }
}


resource "aws_vpc_ipv6_cidr_block_association" "ipv6_cidr_block" {
  ipv6_cidr_block = true
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_iot_thing_group" "vpc_flow_log_group" {
  // CF Property(RetentionInDays) = var.vpc_flow_log_retention
}

resource "aws_flow_log" "vpc_flow_log" {
  iam_role_arn = aws_iam_role.vpc_flow_log_role.arn
  log_destination_type = "VPC"
  log_group_name = aws_iot_thing_group.vpc_flow_log_group.arn
  eni_id = aws_vpc.vpc.arn
  traffic_type = "ALL"
}

resource "aws_iam_role" "vpc_flow_log_role" {
  name = "${var.naming_prefix}-VPCFlowLog-${data.aws_region.current.name}-${aws_vpc.vpc.arn}"
  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "vpc-flow-logs.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
POLICY
  path = "/"
  inline_policy {
    name = "VPCFlowLog"
    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:DescribeLogGroups", "logs:DescribeLogStreams", "logs:PutLogEvents"]
          Effect   = "Allow"
          Resource = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:${local.stack_name}-VPCFlowLogGroup-*"
        },
      ]
    })
}

resource "aws_internet_gateway" "igw" {
  tags = {
    Name = "${var.naming_prefix}-IGW"
  }
}

resource "aws_vpn_gateway_attachment" "igw_attach" {
  vpc_id = aws_internet_gateway.igw.id
}

resource "aws_egress_only_internet_gateway" "igw_egress_onlyv6" {
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_route" "internet_route" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.igw.id
  route_table_id = aws_route_table.internet_route_table.id
}

resource "aws_route" "internet_routev6" {
  destination_ipv6_cidr_block = "::/0"
  route_table_id = aws_route_table.internet_route_table.id
  egress_only_gateway_id = aws_egress_only_internet_gateway.igw_egress_onlyv6.id
}

resource "aws_route_table" "internet_route_table" {
  vpc_id = aws_vpc.vpc.arn
  tags = {
    Name = "${var.naming_prefix}-Public-RTB"
  }
}

resource "aws_subnet" "alb1_subnet1" {
  assign_ipv6_address_on_creation = true
  availability_zone = element(data.aws_availability_zones.available.names, 0)
  cidr_block = ""
  ipv6_cidr_block = ""
  tags = {
    Name = "${var.naming_prefix}-ALB1-a"
  }
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_subnet" "alb1_subnet2" {
  assign_ipv6_address_on_creation = true
  availability_zone = element(data.aws_availability_zones.available.names, 1)
  cidr_block = ""
  ipv6_cidr_block = ""
    tags = {
    Name = "${var.naming_prefix}-ALB1-b"
  }
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_subnet" "alb1_subnet3" {
  availability_zone = element(data.aws_availability_zones.available.names, 2)
  cidr_block = ""
  ipv6_cidr_block = ""
  tags = {
    Name = "${var.naming_prefix}-ALB1-c"
  }
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_route_table_association" "alb1_subnet1_route_to_internet" {
  route_table_id = aws_route_table.internet_route_table.id
  subnet_id = aws_subnet.alb1_subnet1.id
}

resource "aws_route_table_association" "alb1_subnet2_route_to_internet" {
  route_table_id = aws_route_table.internet_route_table.id
  subnet_id = aws_subnet.alb1_subnet2.id
}

resource "aws_route_table_association" "alb1_subnet3_route_to_internet" {
  route_table_id = aws_route_table.internet_route_table.id
  subnet_id = aws_subnet.alb1_subnet3.id
}

resource "aws_network_acl" "alb1_network_acl1" {
  vpc_id = aws_vpc.vpc.arn
  tags = {
    Name = "${var.naming_prefix}-ALB1"
  }
}


resource "aws_network_acl_rule" "alb1_in_from_internet_http_acl_entry" {
  network_acl_id = aws_network_acl.alb1_network_acl1.id
  rule_number    = 50
  egress         = false
  protocol       = 6
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "alb1_in_from_internet_http_acl_entryv6" {
  network_acl_id = aws_network_acl.alb1_network_acl1.id
  rule_number    = 56
  egress         = false
  protocol       = 6
  rule_action    = "allow"
  cidr_block     = "::/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "alb1_in_from_internet_https_acl_entry" {
  network_acl_id = aws_network_acl.alb1_network_acl1.id
  rule_number    = 100
  egress         = false
  protocol       = 6
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "alb1_in_from_internet_https_acl_entryv6" {
  network_acl_id = aws_network_acl.alb1_network_acl1.id
  rule_number    = 106
  egress         = false
  protocol       = 6
  rule_action    = "allow"
  cidr_block     = "::/0"
  from_port      = 443
  to_port        = 443
}
resource "aws_network_acl_rule" "alb1_in_network_ephemeral_vpc_acl_entry1" {
  network_acl_id = aws_network_acl.alb1_network_acl1.id
  rule_number    = 1100
  egress         = false
  protocol       = 6
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "alb1_in_network_ephemeral_vpc_acl_entry1v6" {
  network_acl_id = aws_network_acl.alb1_network_acl1.id
  rule_number    = 1106
  egress         = false
  protocol       = 6
  rule_action    = "allow"
  cidr_block     = "::/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_default_network_acl" "alb1_in_network_ephemeral_vpc_acl_entry2" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "1200"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "alb1_in_network_ephemeral_vpc_acl_entry2v6" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "1206"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "alb1_in_network_ephemeral_vpc_acl_entry3" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "1300"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "alb1_in_network_ephemeral_vpc_acl_entry3v6" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "1306"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "alb1_out_network_ephemeral_acl_entry" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "1000"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "alb1_out_network_ephemeral_acl_entryv6" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "1006"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "alb1_out_network_httpvpc_acl_entry1" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "1100"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "80", 'To': "80"}
}

resource "aws_default_network_acl" "alb1_out_network_httpvpc_acl_entry1v6" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "1106"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "80", 'To': "80"}
}

resource "aws_default_network_acl" "alb1_out_network_httpvpc_acl_entry2" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "1200"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "80", 'To': "80"}
}

resource "aws_default_network_acl" "alb1_out_network_httpvpc_acl_entry2v6" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "1206"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "80", 'To': "80"}
}

resource "aws_default_network_acl" "alb1_out_network_httpvpc_acl_entry3" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "1300"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "80", 'To': "80"}
}

resource "aws_default_network_acl" "alb1_out_network_httpvpc_acl_entry3v6" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "1306"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "80", 'To': "80"}
}

resource "aws_default_network_acl" "alb1_out_network_httpsvpc_acl_entry1" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "2100"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "443", 'To': "443"}
}

resource "aws_default_network_acl" "alb1_out_network_httpsvpc_acl_entry1v6" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "2106"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "443", 'To': "443"}
}

resource "aws_default_network_acl" "alb1_out_network_httpsvpc_acl_entry2" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "2200"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "443", 'To': "443"}
}

resource "aws_default_network_acl" "alb1_out_network_httpsvpc_acl_entry2v6" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "2206"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "443", 'To': "443"}
}

resource "aws_default_network_acl" "alb1_out_network_httpsvpc_acl_entry3" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "2300"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "443", 'To': "443"}
}

resource "aws_default_network_acl" "alb1_out_network_httpsvpc_acl_entry3v6" {
  default_network_acl_id = aws_network_acl.alb1_network_acl1.id
  // CF Property(RuleNumber) = "2306"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "443", 'To': "443"}
}

resource "aws_network_acl_association" "alb1_subnet_network_acl_assocation1" {
  subnet_id = aws_subnet.alb1_subnet1.id
  network_acl_id = aws_network_acl.alb1_network_acl1.id
}

resource "aws_network_acl_association" "alb1_subnet_network_acl_assocation2" {
  subnet_id = aws_subnet.alb1_subnet2.id
  network_acl_id = aws_network_acl.alb1_network_acl1.id
}

resource "aws_network_acl_association" "alb1_subnet_network_acl_assocation3" {
  subnet_id = aws_subnet.alb1_subnet3.id
  network_acl_id = aws_network_acl.alb1_network_acl1.id
}

resource "aws_subnet" "app1_subnet1" {
  assign_ipv6_address_on_creation = true
  availability_zone = element(data.aws_availability_zones.available.names, 0)
  cidr_block = ""
  ipv6_cidr_block = ""
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-App1-a"}]
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_subnet" "app1_subnet2" {
  assign_ipv6_address_on_creation = true
  availability_zone = element(data.aws_availability_zones.available.names, 1)
  cidr_block = ""
  ipv6_cidr_block = ""
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-App1-b"}]
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_subnet" "app1_subnet3" {
  assign_ipv6_address_on_creation = true
  availability_zone = element(data.aws_availability_zones.available.names, 2)
  cidr_block = ""
  ipv6_cidr_block = ""
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-App1-c"}]
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_route_table" "app1_route_table1" {
  vpc_id = aws_vpc.vpc.arn
  tags = [{'Key': "Name", 'Value': 'join("-", [var.naming_prefix, "App1", "RTB1"])'}]
}

resource "aws_route" "app1_internet_route1" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.shared1_natgw1.id
  route_table_id = aws_route_table.app1_route_table1.id
}

resource "aws_route" "app1_internet_route1v6" {
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id = aws_egress_only_internet_gateway.igw_egress_onlyv6.id
  route_table_id = aws_route_table.app1_route_table1.id
}

resource "aws_route_table" "app1_route_table2" {
  vpc_id = aws_vpc.vpc.arn
  tags = [{'Key': "Name", 'Value': 'join("-", [var.naming_prefix, "App1", "RTB2"])'}]
}

resource "aws_route" "app1_internet_route2" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.shared1_natgw2.id
  route_table_id = aws_route_table.app1_route_table2.id
}

resource "aws_route" "app1_internet_route2v6" {
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id = aws_egress_only_internet_gateway.igw_egress_onlyv6.id
  route_table_id = aws_route_table.app1_route_table2.id
}

resource "aws_route_table" "app1_route_table3" {
  vpc_id = aws_vpc.vpc.arn
  tags = [{'Key': "Name", 'Value': 'join("-", [var.naming_prefix, "App1", "RTB3"])'}]
}

resource "aws_route" "app1_internet_route3" {
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.shared1_natgw3.id
  route_table_id = aws_route_table.app1_route_table3.id
}

resource "aws_route" "app1_internet_route3v6" {
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id = aws_egress_only_internet_gateway.igw_egress_onlyv6.id
  route_table_id = aws_route_table.app1_route_table3.id
}

resource "aws_route_table_association" "app1_subnet_route_table_association1" {
  subnet_id = aws_subnet.app1_subnet1.id
  route_table_id = aws_route_table.app1_route_table1.id
}

resource "aws_route_table_association" "app1_subnet_route_table_association2" {
  subnet_id = aws_subnet.app1_subnet2.id
  route_table_id = aws_route_table.app1_route_table2.id
}

resource "aws_route_table_association" "app1_subnet_route_table_association3" {
  subnet_id = aws_subnet.app1_subnet3.id
  route_table_id = aws_route_table.app1_route_table3.id
}

resource "aws_network_acl" "app1_network_acl1" {
  vpc_id = aws_vpc.vpc.arn
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-App1"}]
}

resource "aws_default_network_acl" "app1_in_network_http_acl_entry" {
  default_network_acl_id = aws_network_acl.app1_network_acl1.id
  // CF Property(RuleNumber) = "50"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "80", 'To': "80"}
}

resource "aws_default_network_acl" "app1_in_network_http_acl_entryv6" {
  default_network_acl_id = aws_network_acl.app1_network_acl1.id
  // CF Property(RuleNumber) = "56"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "80", 'To': "80"}
}

resource "aws_default_network_acl" "app1_in_network_https_acl_entry" {
  default_network_acl_id = aws_network_acl.app1_network_acl1.id
  // CF Property(RuleNumber) = "100"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "443", 'To': "443"}
}

resource "aws_default_network_acl" "app1_in_network_https_acl_entryv6" {
  default_network_acl_id = aws_network_acl.app1_network_acl1.id
  // CF Property(RuleNumber) = "106"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "443", 'To': "443"}
}

resource "aws_default_network_acl" "app1_in_network_ephemeral_acl_entry" {
  default_network_acl_id = aws_network_acl.app1_network_acl1.id
  // CF Property(RuleNumber) = "150"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "app1_in_network_ephemeral_acl_entryv6" {
  default_network_acl_id = aws_network_acl.app1_network_acl1.id
  // CF Property(RuleNumber) = "156"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "app1_out_network_http_acl_entry" {
  default_network_acl_id = aws_network_acl.app1_network_acl1.id
  // CF Property(RuleNumber) = "100"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "80", 'To': "80"}
}

resource "aws_default_network_acl" "app1_out_network_http_acl_entryv6" {
  default_network_acl_id = aws_network_acl.app1_network_acl1.id
  // CF Property(RuleNumber) = "106"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "80", 'To': "80"}
}

resource "aws_default_network_acl" "app1_out_network_https_acl_entry" {
  default_network_acl_id = aws_network_acl.app1_network_acl1.id
  // CF Property(RuleNumber) = "150"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "443", 'To': "443"}
}

resource "aws_default_network_acl" "app1_out_network_https_acl_entryv6" {
  default_network_acl_id = aws_network_acl.app1_network_acl1.id
  // CF Property(RuleNumber) = "156"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "443", 'To': "443"}
}

resource "aws_default_network_acl" "app1_out_networ_vpc_acl_entry" {
  default_network_acl_id = aws_network_acl.app1_network_acl1.id
  // CF Property(RuleNumber) = "200"
  // CF Property(Protocol) = "-1"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "1", 'To': "65535"}
}

resource "aws_default_network_acl" "app1_out_networ_vpc_acl_entryv6" {
  default_network_acl_id = aws_network_acl.app1_network_acl1.id
  // CF Property(RuleNumber) = "206"
  // CF Property(Protocol) = "-1"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "1", 'To': "65535"}
}

resource "aws_network_acl_association" "app1_subnet_network_acl_assocation1" {
  subnet_id = aws_subnet.app1_subnet1.id
  network_acl_id = aws_network_acl.app1_network_acl1.id
}

resource "aws_network_acl_association" "app1_subnet_network_acl_assocation2" {
  subnet_id = aws_subnet.app1_subnet2.id
  network_acl_id = aws_network_acl.app1_network_acl1.id
}

resource "aws_network_acl_association" "app1_subnet_network_acl_assocation3" {
  subnet_id = aws_subnet.app1_subnet3.id
  network_acl_id = aws_network_acl.app1_network_acl1.id
}

resource "aws_vpc_endpoint" "app1_vpc_endpoint_s3" {
  policy = {
    Version = "2012-10-17"
    Statement = [{'Effect': "Allow", 'Principal': "*", 'Action': "s3:*", 'Resource': "arn:${data.aws_partition.current.partition}:s3:::*"}]
  }
  route_table_ids = ['aws_route_table.app1_route_table1.id', 'aws_route_table.app1_route_table2.id', 'aws_route_table.app1_route_table3.id']
  service_name = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_vpc_endpoint" "app1_vpc_endpoint_dynamo_db" {
  policy = {
    Version = "2012-10-17"
    Statement = [{'Effect': "Allow", 'Principal': "*", 'Action': "dynamodb:*", 'Resource': "arn:${data.aws_partition.current.partition}:dynamodb:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"}]
  }
  route_table_ids = ['aws_route_table.app1_route_table1.id', 'aws_route_table.app1_route_table2.id', 'aws_route_table.app1_route_table3.id']
  service_name = "com.amazonaws.${data.aws_region.current.name}.dynamodb"
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_security_group" "app1_endpoint_security_group" {
  description = "Enable access to endpoints"
  ingress = [{'protocol': "tcp", 'from_port': "443", 'to_port': "443", 'cidr_blocks': "None"}, {'protocol': "tcp", 'from_port': "443", 'to_port': "443", 'ipv6_cidr_blocks': "None"}, {'protocol': "tcp", 'from_port': "443", 'to_port': "443", 'cidr_blocks': "None"}, {'protocol': "tcp", 'from_port': "443", 'to_port': "443", 'ipv6_cidr_blocks': "None"}, {'protocol': "tcp", 'from_port': "443", 'to_port': "443", 'cidr_blocks': "None"}, {'protocol': "tcp", 'from_port': "443", 'to_port': "443", 'ipv6_cidr_blocks': "None"}]
  tags = [{'Key': "Name", 'Value': 'join("-", [var.naming_prefix, "Endpoint"])'}]
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_vpc_endpoint" "app1_vpc_endpointec2" {
  vpc_id = aws_vpc.vpc.arn
  service_name = "com.amazonaws.${data.aws_region.current.name}.ec2"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  subnet_ids = ['aws_subnet.app1_subnet1.id', 'aws_subnet.app1_subnet2.id', 'aws_subnet.app1_subnet3.id']
  security_group_ids = ['aws_security_group.app1_endpoint_security_group.arn']
}

resource "aws_vpc_endpoint" "app1_vpc_endpointec2messages" {
  vpc_id = aws_vpc.vpc.arn
  service_name = "com.amazonaws.${data.aws_region.current.name}.ec2messages"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  subnet_ids = ['aws_subnet.app1_subnet1.id', 'aws_subnet.app1_subnet2.id', 'aws_subnet.app1_subnet3.id']
  security_group_ids = ['aws_security_group.app1_endpoint_security_group.arn']
}

resource "aws_vpc_endpoint" "app1_vpc_endpointcloudformation" {
  vpc_id = aws_vpc.vpc.arn
  service_name = "com.amazonaws.${data.aws_region.current.name}.cloudformation"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  subnet_ids = ['aws_subnet.app1_subnet1.id', 'aws_subnet.app1_subnet2.id', 'aws_subnet.app1_subnet3.id']
  security_group_ids = ['aws_security_group.app1_endpoint_security_group.arn']
}

resource "aws_vpc_endpoint" "app1_vpc_endpointlogs" {
  vpc_id = aws_vpc.vpc.arn
  service_name = "com.amazonaws.${data.aws_region.current.name}.logs"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  subnet_ids = ['aws_subnet.app1_subnet1.id', 'aws_subnet.app1_subnet2.id', 'aws_subnet.app1_subnet3.id']
  security_group_ids = ['aws_security_group.app1_endpoint_security_group.arn']
}

resource "aws_vpc_endpoint" "app1_vpc_endpointmonitoring" {
  vpc_id = aws_vpc.vpc.arn
  service_name = "com.amazonaws.${data.aws_region.current.name}.monitoring"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  subnet_ids = ['aws_subnet.app1_subnet1.id', 'aws_subnet.app1_subnet2.id', 'aws_subnet.app1_subnet3.id']
  security_group_ids = ['aws_security_group.app1_endpoint_security_group.arn']
}

resource "aws_vpc_endpoint" "app1_vpc_endpointssm" {
  vpc_id = aws_vpc.vpc.arn
  service_name = "com.amazonaws.${data.aws_region.current.name}.ssm"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  subnet_ids = ['aws_subnet.app1_subnet1.id', 'aws_subnet.app1_subnet2.id', 'aws_subnet.app1_subnet3.id']
  security_group_ids = ['aws_security_group.app1_endpoint_security_group.arn']
}

resource "aws_vpc_endpoint" "app1_vpc_endpointssmmessages" {
  vpc_id = aws_vpc.vpc.arn
  service_name = "com.amazonaws.${data.aws_region.current.name}.ssmmessages"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  subnet_ids = ['aws_subnet.app1_subnet1.id', 'aws_subnet.app1_subnet2.id', 'aws_subnet.app1_subnet3.id']
  security_group_ids = ['aws_security_group.app1_endpoint_security_group.arn']
}

resource "aws_vpc_endpoint" "app1_vpc_endpointsecretsmanager" {
  vpc_id = aws_vpc.vpc.arn
  service_name = "com.amazonaws.${data.aws_region.current.name}.secretsmanager"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  subnet_ids = ['aws_subnet.app1_subnet1.id', 'aws_subnet.app1_subnet2.id', 'aws_subnet.app1_subnet3.id']
  security_group_ids = ['aws_security_group.app1_endpoint_security_group.arn']
}

resource "aws_vpc_endpoint" "app1_vpc_endpointkms" {
  vpc_id = aws_vpc.vpc.arn
  service_name = "com.amazonaws.${data.aws_region.current.name}.kms"
  vpc_endpoint_type = "Interface"
  private_dns_enabled = true
  subnet_ids = ['aws_subnet.app1_subnet1.id', 'aws_subnet.app1_subnet2.id', 'aws_subnet.app1_subnet3.id']
  security_group_ids = ['aws_security_group.app1_endpoint_security_group.arn']
}

resource "aws_subnet" "shared1_subnet1" {
  assign_ipv6_address_on_creation = true
  availability_zone = element(data.aws_availability_zones.available.names, 0)
  cidr_block = ""
  ipv6_cidr_block = ""
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-Shared1-a"}]
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_subnet" "shared1_subnet2" {
  assign_ipv6_address_on_creation = true
  availability_zone = element(data.aws_availability_zones.available.names, 1)
  cidr_block = ""
  ipv6_cidr_block = ""
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-Shared1-b"}]
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_subnet" "shared1_subnet3" {
  assign_ipv6_address_on_creation = true
  availability_zone = element(data.aws_availability_zones.available.names, 2)
  cidr_block = ""
  ipv6_cidr_block = ""
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-Shared1-c"}]
  vpc_id = aws_vpc.vpc.arn
}

resource "aws_nat_gateway" "shared1_natgw1" {
  allocation_id = aws_ec2_fleet.shared1_nat1_eip.id
  subnet_id = aws_subnet.shared1_subnet1.id
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-Shared1-a"}]
}

resource "aws_nat_gateway" "shared1_natgw2" {
  allocation_id = aws_ec2_fleet.shared1_nat2_eip.id
  subnet_id = aws_subnet.shared1_subnet2.id
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-Shared1-b"}]
}

resource "aws_nat_gateway" "shared1_natgw3" {
  allocation_id = aws_ec2_fleet.shared1_nat3_eip.id
  subnet_id = aws_subnet.shared1_subnet3.id
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-Shared1-c"}]
}

resource "aws_ec2_fleet" "shared1_nat1_eip" {
  // CF Property(Domain) = "vpc"
}

resource "aws_ec2_fleet" "shared1_nat2_eip" {
  // CF Property(Domain) = "vpc"
}

resource "aws_ec2_fleet" "shared1_nat3_eip" {
  // CF Property(Domain) = "vpc"
}

resource "aws_route" "shared1_route1" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.igw.id
  route_table_id = aws_route_table.shared1_route_table1.id
}

resource "aws_route" "shared1_route1v6" {
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id = aws_egress_only_internet_gateway.igw_egress_onlyv6.id
  route_table_id = aws_route_table.shared1_route_table1.id
}

resource "aws_route_table" "shared1_route_table1" {
  vpc_id = aws_vpc.vpc.arn
  tags = [{'Key': "Name", 'Value': 'join("-", [var.naming_prefix, "Shared", "RTB1"])'}]
}

resource "aws_route_table_association" "shared1_subnet_route_table_association1" {
  route_table_id = aws_route_table.shared1_route_table1.id
  subnet_id = aws_subnet.shared1_subnet1.id
}

resource "aws_route" "shared1_route2" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.igw.id
  route_table_id = aws_route_table.shared1_route_table2.id
}

resource "aws_route" "shared1_route2v6" {
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id = aws_egress_only_internet_gateway.igw_egress_onlyv6.id
  route_table_id = aws_route_table.shared1_route_table2.id
}

resource "aws_route_table" "shared1_route_table2" {
  vpc_id = aws_vpc.vpc.arn
  tags = [{'Key': "Name", 'Value': 'join("-", [var.naming_prefix, "Shared", "RTB2"])'}]
}

resource "aws_route_table_association" "shared1_subnet_route_table_association2" {
  route_table_id = aws_route_table.shared1_route_table2.id
  subnet_id = aws_subnet.shared1_subnet2.id
}

resource "aws_route" "shared1_route3" {
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.igw.id
  route_table_id = aws_route_table.shared1_route_table3.id
}

resource "aws_route" "shared1_route3v6" {
  destination_ipv6_cidr_block = "::/0"
  egress_only_gateway_id = aws_egress_only_internet_gateway.igw_egress_onlyv6.id
  route_table_id = aws_route_table.shared1_route_table3.id
}

resource "aws_route_table" "shared1_route_table3" {
  vpc_id = aws_vpc.vpc.arn
  tags = [{'Key': "Name", 'Value': 'join("-", [var.naming_prefix, "Shared", "RTB3"])'}]
}

resource "aws_route_table_association" "shared1_subnet_route_table_association3" {
  route_table_id = aws_route_table.shared1_route_table3.id
  subnet_id = aws_subnet.shared1_subnet3.id
}

resource "aws_network_acl" "shared1_network_acl1" {
  vpc_id = aws_vpc.vpc.arn
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-Shared1"}]
}

resource "aws_default_network_acl" "shared1_in_network_ephemeral_acl_entry1" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "50"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "shared1_in_network_ephemeral_acl_entry1v6" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "56"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "shared1_in_network_app1_entry1" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "100"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "0", 'To': "65535"}
}

resource "aws_default_network_acl" "shared1_in_network_app1_entry1v6" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "106"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "0", 'To': "65535"}
}

resource "aws_default_network_acl" "shared1_in_network_app1_entry2" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "150"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "0", 'To': "65535"}
}

resource "aws_default_network_acl" "shared1_in_network_app1_entry2v6" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "156"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "0", 'To': "65535"}
}

resource "aws_default_network_acl" "shared1_in_network_app1_entry3" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "200"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "0", 'To': "65535"}
}

resource "aws_default_network_acl" "shared1_in_network_app1_entry3v6" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "206"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "0", 'To': "65535"}
}

resource "aws_default_network_acl" "shared1_out_network_ephemeral_acl_entry" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "50"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "shared1_out_network_ephemeral_acl_entryv6" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "56"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "shared1_out_network_http_acl_entry" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "100"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "80", 'To': "80"}
}

resource "aws_default_network_acl" "shared1_out_network_http_acl_entryv6" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "106"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "80", 'To': "80"}
}

resource "aws_default_network_acl" "shared1_out_network_https_acl_entry" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "200"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "443", 'To': "443"}
}

resource "aws_default_network_acl" "shared1_out_network_https_acl_entryv6" {
  default_network_acl_id = aws_network_acl.shared1_network_acl1.id
  // CF Property(RuleNumber) = "206"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "443", 'To': "443"}
}

resource "aws_network_acl_association" "shared1_subnet1_network_acl_assocation1" {
  subnet_id = aws_subnet.shared1_subnet1.id
  network_acl_id = aws_network_acl.shared1_network_acl1.id
}

resource "aws_network_acl_association" "shared1_subnet1_network_acl_assocation2" {
  subnet_id = aws_subnet.shared1_subnet2.id
  network_acl_id = aws_network_acl.shared1_network_acl1.id
}

resource "aws_network_acl_association" "shared1_subnet1_network_acl_assocation3" {
  subnet_id = aws_subnet.shared1_subnet3.id
  network_acl_id = aws_network_acl.shared1_network_acl1.id
}

resource "aws_subnet" "db1_subnet1" {
  assign_ipv6_address_on_creation = true
  vpc_id = aws_vpc.vpc.arn
  availability_zone = element(data.aws_availability_zones.available.names, 0)
  cidr_block = ""
  ipv6_cidr_block = ""
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-DB1-a"}]
}

resource "aws_subnet" "db1_subnet2" {
  assign_ipv6_address_on_creation = true
  vpc_id = aws_vpc.vpc.arn
  availability_zone = element(data.aws_availability_zones.available.names, 1)
  cidr_block = ""
  ipv6_cidr_block = ""
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-DB1-b"}]
}

resource "aws_subnet" "db1_subnet3" {
  assign_ipv6_address_on_creation = true
  vpc_id = aws_vpc.vpc.arn
  availability_zone = element(data.aws_availability_zones.available.names, 2)
  cidr_block = ""
  ipv6_cidr_block = ""
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-DB1-c"}]
}

resource "aws_route_table" "db1_route_table1" {
  vpc_id = aws_vpc.vpc.arn
  tags = [{'Key': "Name", 'Value': 'join("-", [var.naming_prefix, "DB1", "RTB1"])'}]
}

resource "aws_route_table" "db1_route_table2" {
  vpc_id = aws_vpc.vpc.arn
  tags = [{'Key': "Name", 'Value': 'join("-", [var.naming_prefix, "DB1", "RTB2"])'}]
}

resource "aws_route_table" "db1_route_table3" {
  vpc_id = aws_vpc.vpc.arn
  tags = [{'Key': "Name", 'Value': 'join("-", [var.naming_prefix, "DB1", "RTB3"])'}]
}

resource "aws_route_table_association" "db1_subnet_route_table_association1" {
  subnet_id = aws_subnet.db1_subnet1.id
  route_table_id = aws_route_table.db1_route_table1.id
}

resource "aws_route_table_association" "db1_subnet_route_table_association2" {
  subnet_id = aws_subnet.db1_subnet2.id
  route_table_id = aws_route_table.db1_route_table2.id
}

resource "aws_route_table_association" "db1_subnet_route_table_association3" {
  subnet_id = aws_subnet.db1_subnet3.id
  route_table_id = aws_route_table.db1_route_table3.id
}

resource "aws_network_acl" "db1_network_acl1" {
  vpc_id = aws_vpc.vpc.arn
  tags = [{'Key': "Name", 'Value': "${var.naming_prefix}-DB1"}]
}

resource "aws_default_network_acl" "db1_in_from_app1_acl_entry1" {
  default_network_acl_id = aws_network_acl.db1_network_acl1.id
  // CF Property(RuleNumber) = "50"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': 'var.db1_tcp_port_number', 'To': 'var.db1_tcp_port_number'}
}

resource "aws_default_network_acl" "db1_in_from_app1_acl_entry1v6" {
  default_network_acl_id = aws_network_acl.db1_network_acl1.id
  // CF Property(RuleNumber) = "56"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': 'var.db1_tcp_port_number', 'To': 'var.db1_tcp_port_number'}
}

resource "aws_default_network_acl" "db1_in_from_app1_acl_entry2" {
  default_network_acl_id = aws_network_acl.db1_network_acl1.id
  // CF Property(RuleNumber) = "100"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': 'var.db1_tcp_port_number', 'To': 'var.db1_tcp_port_number'}
}

resource "aws_default_network_acl" "db1_in_from_app1_acl_entry2v6" {
  default_network_acl_id = aws_network_acl.db1_network_acl1.id
  // CF Property(RuleNumber) = "106"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': 'var.db1_tcp_port_number', 'To': 'var.db1_tcp_port_number'}
}

resource "aws_default_network_acl" "db1_in_from_app1_acl_entry3" {
  default_network_acl_id = aws_network_acl.db1_network_acl1.id
  // CF Property(RuleNumber) = "150"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': 'var.db1_tcp_port_number', 'To': 'var.db1_tcp_port_number'}
}

resource "aws_default_network_acl" "db1_in_from_app1_acl_entry3v6" {
  default_network_acl_id = aws_network_acl.db1_network_acl1.id
  // CF Property(RuleNumber) = "156"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "false"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': 'var.db1_tcp_port_number', 'To': 'var.db1_tcp_port_number'}
}

resource "aws_default_network_acl" "db1_out_network_ephemeral_acl_entry1" {
  default_network_acl_id = aws_network_acl.db1_network_acl1.id
  // CF Property(RuleNumber) = "50"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "db1_out_network_ephemeral_acl_entry1v6" {
  default_network_acl_id = aws_network_acl.db1_network_acl1.id
  // CF Property(RuleNumber) = "56"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "db1_out_network_ephemeral_acl_entry2" {
  default_network_acl_id = aws_network_acl.db1_network_acl1.id
  // CF Property(RuleNumber) = "100"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "db1_out_network_ephemeral_acl_entry2v6" {
  default_network_acl_id = aws_network_acl.db1_network_acl1.id
  // CF Property(RuleNumber) = "106"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "db1_out_network_ephemeral_acl_entry3" {
  default_network_acl_id = aws_network_acl.db1_network_acl1.id
  // CF Property(RuleNumber) = "150"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(CidsrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_default_network_acl" "db1_out_network_ephemeral_acl_entry3v6" {
  default_network_acl_id = aws_network_acl.db1_network_acl1.id
  // CF Property(RuleNumber) = "156"
  // CF Property(Protocol) = "6"
  // CF Property(RuleAction) = "allow"
  egress = "true"
  // CF Property(Ipv6CidrBlock) = ""
  // CF Property(PortRange) = {'From': "1024", 'To': "65535"}
}

resource "aws_network_acl_association" "db1_subnet_network_acl_assocation1" {
  subnet_id = aws_subnet.db1_subnet1.id
  network_acl_id = aws_network_acl.db1_network_acl1.id
}

resource "aws_network_acl_association" "db1_subnet_network_acl_assocation2" {
  subnet_id = aws_subnet.db1_subnet2.id
  network_acl_id = aws_network_acl.db1_network_acl1.id
}

resource "aws_network_acl_association" "db1_subnet_network_acl_assocation3" {
  subnet_id = aws_subnet.db1_subnet3.id
  network_acl_id = aws_network_acl.db1_network_acl1.id
}

