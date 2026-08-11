variable "project_name" {
  type    = string
  default = "multi-region-lab"

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

variable "domain_name" {
  type        = string
  description = "Application hostname, for example app.example.com."
}

variable "route53_zone_id" {
  type        = string
  description = "Route53 public hosted zone ID for domain_name."
}

variable "primary_traffic_dial" {
  type    = number
  default = 100

  validation {
    condition     = var.primary_traffic_dial >= 0 && var.primary_traffic_dial <= 100
    error_message = "primary_traffic_dial must be between 0 and 100."
  }
}

variable "secondary_traffic_dial" {
  type    = number
  default = 0

  validation {
    condition     = var.secondary_traffic_dial >= 0 && var.secondary_traffic_dial <= 100
    error_message = "secondary_traffic_dial must be between 0 and 100."
  }
}

