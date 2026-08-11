# Purpose: Pins providers, configures the S3 backend, and declares regional aliases.
# Modules: None; module versions are pinned where each module is instantiated.

terraform {
  required_version = "= 1.15.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "= 5.100.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "= 2.17.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "= 2.38.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "= 3.7.2"
    }
  }

  backend "s3" {
    key          = "multi-region/infrastructure.tfstate"
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

provider "kubernetes" {
  alias                  = "primary"
  host                   = module.primary_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.primary_eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.primary_eks.cluster_name, "--region", var.primary_region]
  }
}

provider "kubernetes" {
  alias                  = "secondary"
  host                   = module.secondary_eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.secondary_eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", module.secondary_eks.cluster_name, "--region", var.secondary_region]
  }
}

provider "helm" {
  alias = "primary"

  kubernetes {
    host                   = module.primary_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.primary_eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.primary_eks.cluster_name, "--region", var.primary_region]
    }
  }
}

provider "helm" {
  alias = "secondary"

  kubernetes {
    host                   = module.secondary_eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.secondary_eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.secondary_eks.cluster_name, "--region", var.secondary_region]
    }
  }
}
