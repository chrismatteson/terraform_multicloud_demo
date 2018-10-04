# variables.tf – commonly configured parameters for our environment (i.e. projectName)

#################################################
# Azure Location
variable "location" {
  default = "eastus"
}

#################################################
# AWS Region
variable "aws_region" {
  default = "us-east-2"
}
