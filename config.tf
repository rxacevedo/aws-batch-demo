terraform {
  backend "s3" {
    bucket = "rxacevedo-tfstate"
    key    = "batch/terraform.tfstate"
    region = "us-east-1"
  }

  required_version = "> 0.7.0"
}
