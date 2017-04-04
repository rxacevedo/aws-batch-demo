########################################################
# Setup

provider "aws" {
  region  = "us-east-1"
  profile = "rxacevedo"  # That's me!
}

# ASG/compute capacity stuff
variable "asg_min" {}
variable "asg_max" {}
variable "asg_desired" {}
variable "asg_instance_type" {
  default = "t2.micro"
}

# Job stuff
variable "image" {}
variable "s3_bucket" {}
variable "s3_key" {}
