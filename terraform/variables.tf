variable "aws_region" {
  type        = string
  description = "The AWS Region to deploy resources"
  default     = "sa-east-1"
}

variable "instance_type" {
  type        = string
  description = "The EC2 instance type"
  default     = "t3.micro"
}

variable "vpc_cidr" {
  type        = map(string)
  description = "CIDR block for the VPC mapped by workspace"
  default = {
    default = "10.0.0.0/16"
    dev     = "10.0.0.0/16"
    prod    = "10.1.0.0/16"
  }
}

variable "subnet_cidr" {
  type        = map(string)
  description = "CIDR block for the subnet mapped by workspace"
  default = {
    default = "10.0.1.0/24"
    dev     = "10.0.1.0/24"
    prod    = "10.1.1.0/24"
  }
}
