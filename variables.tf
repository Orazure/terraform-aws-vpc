variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "cidr_block" {
  type    = string
  default = "172.20.0.0/16"
}

variable "vpc_name" {
  type    = string
  default = "vpc_1"
}

variable "azs"{
  type = map(string)
  default = {
    a = "0",
    b = "1",
    c = "2"
  }
}


