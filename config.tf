terraform {
  backend "s3" {
    bucket = "rxacevedo-tfstate"
    key    = "tf_test/terraform.tfstate"
    region = "us-east-1"
  }
}
