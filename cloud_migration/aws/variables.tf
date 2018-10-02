# variables.tf – commonly configured parameters for our environment (i.e. projectName)

#################################################
# AWS Region
variable "aws_region" {
  default = "us-east-2"
}

variable "keyPairName" {}

variable "webAmi" {
  default = "ami-5e8bb23b" # AWS 2 for us-east-2
}
