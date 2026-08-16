# Purpose: Pins the AWS provider and configures the edge S3 backend and aliases.
# Modules: None; the edge root declares only direct AWS resources.

terraform {
  required_version = "= 1.15.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.100.0"
    }
  }

  backend "s3" {
    key          = "multi-region/edge.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
    }
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
    }
  }
}

# Global Accelerator exposes its control-plane API in us-west-2.
provider "aws" {
  alias  = "global"
  region = "us-west-2"

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "Terraform"
    }
  }
}
