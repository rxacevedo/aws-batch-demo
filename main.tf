########################################################
# Setup

provider "aws" {
  region  = "us-east-1"
  profile = "rxacevedo"  # That's me!
}

data "aws_caller_identity" "current" {}

# ASG/compute capacity stuff
variable "asg_min" {
  default = 0
}

variable "asg_max" {
  default = 0
}

variable "asg_desired" {
  default = 0
}

variable "asg_instance_type" {
  default = "t2.micro"
}

variable "dynamic_asg_min" {
  default = 0
}
variable "dynamic_asg_max" {
  default = 3
}

# Job stuff
variable "image" {}
variable "s3_bucket" {}
variable "slack_webhook_url" {}
