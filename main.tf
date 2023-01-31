### Module Main

provider "aws" {
  region = var.aws_region
}


terraform {
  backend "s3" {
    bucket="terraform-state-tp"
    key="state"
    region="us-east-1"
  }
}

resource "aws_vpc" "vpc_1" {
  cidr_block = var.cidr_block

  tags = {
    Name = "${var.vpc_name}-vpc"
  }
}

resource "aws_subnet" "public" {

  for_each = var.azs
  vpc_id = aws_vpc.vpc_1.id
  cidr_block = cidrsubnet(var.cidr_block, 4, each.value)
  availability_zone = "${var.aws_region}${each.key}"
  map_public_ip_on_launch = true
  

  tags = {
    Name = "${var.vpc_name}-public-${var.aws_region}${each.key}"
  }
}

resource "aws_subnet" "private" {
  for_each = var.azs
  vpc_id = aws_vpc.vpc_1.id
  cidr_block = cidrsubnet(var.cidr_block, 4, 15 - each.value)
  availability_zone = "${var.aws_region}${each.key}"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.vpc_name}-private-${var.aws_region}${each.key}"
  }
  
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc_1.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}


data "aws_ami" "nat_ami_vtp" {
  most_recent = true
  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn-ami-vpc-nat-2018.03.0.2021*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

}

// create ami with ubuntu 20.04

data "aws_ami" "ubuntu_ami" {
  most_recent = true
  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

}

resource "aws_security_group" "allowAllEgress" {

  name = "allowAllIngress"
  description = "Allow all outbound traffic"
  vpc_id = aws_vpc.vpc_1.id

  egress {
    from_port = 0
    to_port = 0
    protocol = "-1"
    cidr_blocks =["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}


resource "aws_security_group_rule" "allowSshIntoVpc" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.allowAllEgress.id
}

//allow all port tcp
resource "aws_security_group_rule" "allowAllTcp" {
  type = "ingress"
  from_port = 0
  to_port = 65535
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.allowAllEgress.id
}



resource "aws_security_group_rule" "allowHttpAndHttps" {
  type = "ingress"
  from_port = 80
  to_port = 80
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.allowAllEgress.id
}

resource "aws_security_group_rule" "allowHttpAndHttps2" {
  type = "ingress"
  from_port = 443
  to_port = 443
  protocol = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.allowAllEgress.id
}

//allow icmp ping
resource "aws_security_group_rule" "allowPing" {
  type = "ingress"
  from_port = 0
  to_port = 0
  protocol = "icmp"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.allowAllEgress.id
}




resource "aws_key_pair" "auth_key_pair" {
  key_name = "auth_key_pair"
  public_key = file("C:/Users/ALEXA/.ssh/id_ed25519.pub")
}

resource "aws_instance" "ec2_instance_private_subnet" {
  //create new instance in a different subnet for each AZ
  for_each = var.azs
  subnet_id = aws_subnet.private[each.key].id
  vpc_security_group_ids = [aws_security_group.allowAllEgress.id]
  ami = data.aws_ami.ubuntu_ami.id
  key_name = aws_key_pair.auth_key_pair.key_name
  instance_type = "t2.micro"
  source_dest_check = false
  tags = {
    Name = "Instance-TP-private-${var.aws_region}-${each.key}"
  }
  
}

resource "aws_instance" "ec2_instance_public_subnet" {
  //create new instance in a different subnet for each AZ
  for_each = var.azs
  subnet_id = aws_subnet.public[each.key].id
  vpc_security_group_ids = [aws_security_group.allowAllEgress.id]
  ami = data.aws_ami.nat_ami_vtp.id
  key_name = aws_key_pair.auth_key_pair.key_name
  instance_type = "t2.micro"
  source_dest_check = false
  tags = {
    Name = "Instance-TP-public-${var.aws_region}-${each.key}"
  }
  
}


resource "aws_eip" "eip_static" {
  for_each = var.azs
  vpc      = true
}

resource "aws_eip_association" "eip_assoc" {
  //find all instance ids in the private
  for_each = var.azs
  instance_id = aws_instance.ec2_instance_public_subnet[each.key].id
  allocation_id = aws_eip.eip_static[each.key].id
}



resource "aws_route_table" "rt-private" {
  for_each = var.azs
  vpc_id = aws_vpc.vpc_1.id
  tags= {
    Name = "rt-private-${var.aws_region}-${each.key}"
  }
}

resource "aws_route_table" "rt-public" {
  vpc_id = aws_vpc.vpc_1.id
  tags= {
    Name = "rt-public-${var.aws_region}"
  }
}

resource "aws_route_table_association" "rt-private" {
  for_each = var.azs
  subnet_id = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.rt-private[each.key].id
}


resource "aws_route_table_association" "rt-public" {
  for_each = var.azs
  subnet_id = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.rt-public.id
}

// create 1 route for each private subnet
resource "aws_route" "rt-private" {
  for_each = var.azs
  route_table_id = aws_route_table.rt-private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id = aws_instance.ec2_instance_private_subnet[each.key].primary_network_interface_id
}

// 1 route for public subnet
resource "aws_route" "rt-public" {
  route_table_id = aws_route_table.rt-public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id = aws_internet_gateway.igw.id
}










