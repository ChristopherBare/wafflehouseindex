terraform {
  backend "s3" {
    bucket         = "whi-terraform-state"
    key            = "api/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "whi-terraform-lock"
  }
}