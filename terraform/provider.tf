terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  
backend "s3" {
  bucket = "group2-terraform-state"
  key    = "cicd/terraform.tfstate"
  region = "us-east-1"
  encrypt = true  # ← ADD THIS (encrypt state file)
  dynamodb_table = "group2-cicd-terraform-locks"
}

}

provider "aws" {
  region = var.aws_region
}