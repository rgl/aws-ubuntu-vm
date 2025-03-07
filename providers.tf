# see https://github.com/hashicorp/terraform
terraform {
  required_version = "1.11.1"
  required_providers {
    # see https://registry.terraform.io/providers/hashicorp/random
    # see https://github.com/hashicorp/terraform-provider-random
    random = {
      source  = "hashicorp/random"
      version = "3.7.1"
    }
    # see https://registry.terraform.io/providers/hashicorp/cloudinit
    # see https://github.com/hashicorp/terraform-provider-cloudinit
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "2.3.6"
    }
    # see https://registry.terraform.io/providers/hashicorp/aws
    # see https://github.com/hashicorp/terraform-provider-aws
    aws = {
      source  = "hashicorp/aws"
      version = "5.90.0"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "aws-ubuntu-vm"
      Environment = "test"
    }
  }
}
