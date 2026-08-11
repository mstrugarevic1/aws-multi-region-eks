variable "project_name" {
  type        = string
  description = "Short lowercase name used in AWS resource names."
  default     = "multi-region-lab"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,18}[a-z0-9]$", var.project_name))
    error_message = "project_name must be 3-20 lowercase letters, numbers, or hyphens, without leading/trailing hyphens."
  }
}

variable "primary_region" {
  type    = string
  default = "eu-central-1"
}

variable "secondary_region" {
  type    = string
  default = "eu-west-1"
}

variable "primary_vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "secondary_vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "domain_name" {
  type        = string
  description = "Application hostname, for example app.example.com."
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 public hosted zone ID for domain_name."
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appadmin"
}

